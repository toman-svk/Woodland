--!strict
-- src/shared/WorldClientModules/Combat.luau
--
-- ┌─────────────────────────────────────────────────────────────────────────┐
-- │  WHAT THIS FILE DOES                                                    │
-- │                                                                         │
-- │  This is the CLIENT-SIDE half of the combat system.                     │
-- │  Its job is to:                                                          │
-- │    1. Detect when the player wants to attack (mouse click or F key)     │
-- │    2. Play an attack animation on the local character                   │
-- │    3. Tell the SERVER that an attack happened (via RemoteEvent)         │
-- │    4. When the server confirms a hit, display a floating damage number  │
-- │                                                                         │
-- │  IMPORTANT: The client NEVER decides how much damage to deal.           │
-- │  That would let cheaters modify their client to deal infinite damage.   │
-- │  All damage is calculated on the server (CombatService.luau).           │
-- └─────────────────────────────────────────────────────────────────────────┘

-- ── Services ──────────────────────────────────────────────────────────────
-- Roblox services are global singletons you access via GetService().
-- Think of them as the "standard library" of the Roblox engine.

local UserInputService = game:GetService("UserInputService")
-- UserInputService lets us listen to keyboard and mouse input.

local Players = game:GetService("Players")
-- Players gives us access to all connected players, and LocalPlayer (the person running this client).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
-- ReplicatedStorage is a folder that is shared between server and client.
-- We put RemoteEvents and other shared assets here.

local TweenService = game:GetService("TweenService")
-- TweenService smoothly animates properties over time (e.g. moving a GUI element).

-- ── Local player reference ────────────────────────────────────────────────
-- LocalPlayer only exists on the CLIENT. Server scripts cannot use this.
local player = Players.LocalPlayer

-- ── Remote events ─────────────────────────────────────────────────────────
-- A RemoteEvent is a one-way message channel between client and server (or vice versa).
--
--   client:FireServer()     → sends a message FROM this client TO the server
--   server:FireAllClients() → sends a message FROM the server TO every client
--
-- We have two events:
--   CombatAttack  – client fires this to tell the server "I swung my weapon"
--   CombatHit     – server fires this to tell all clients "this enemy was hit for X damage"

local Shared       = ReplicatedStorage:WaitForChild("Shared")
local RemotesFolder = Shared:WaitForChild("Remotes")

-- GetRemote is a small helper that fetches (or creates) a Remote by name.
-- Passing "RemoteEvent" as the second arg tells it what class to expect.
local GetRemote = require(RemotesFolder:WaitForChild("GetRemote"))

local attackEvent = GetRemote("CombatAttack", "RemoteEvent") :: RemoteEvent
local hitEvent    = GetRemote("CombatHit",    "RemoteEvent") :: RemoteEvent

-- ── Input / cooldown settings ─────────────────────────────────────────────
-- ATTACK_KEY is the keyboard key that triggers an armed attack.
-- F is a common choice because it is close to WASD movement keys.
local ATTACK_KEY = Enum.KeyCode.F

-- COOLDOWN prevents spamming attacks.
-- If the player tries to attack again within 0.5 seconds, the input is ignored.
-- (The server also has its own cooldown check as a safety net.)
local COOLDOWN   = 0.5

-- os.clock() returns the current time in seconds (high precision).
-- We store the timestamp of the last attack to compare against later.
local lastAttack = 0.0

-- ── Unarmed punch animation ───────────────────────────────────────────────
-- Set this to a valid Roblox animation asset ID to play a punch animation
-- when the player attacks with bare hands (no tool equipped).
-- Example free punch animations (R15):
--   rbxassetid://3716472724  (right punch)
--   rbxassetid://522635514   (karate chop)
-- Leave as "" to have no punch animation.
local PUNCH_ANIM_ID = "rbxassetid://116235674827914"

-- ── Animation state ───────────────────────────────────────────────────────
-- Animations in Roblox work like this:
--   1. You have an Animation object that holds an AnimationId (asset URL).
--   2. You load it into an Animator (a child of Humanoid) → get back an AnimationTrack.
--   3. You call track:Play() to actually play it.
--
-- We cache these so we don't reload the animation from the server every single attack.
local humanoid:       Humanoid?       = nil  -- the local character's Humanoid
local animator:       Animator?       = nil  -- the Animator inside the Humanoid
local currentTool:    Tool?           = nil  -- which Tool was equipped when we loaded the animation
local currentAnimObj: Animation?      = nil  -- the Animation instance inside that Tool
local currentTrack:   AnimationTrack? = nil  -- the loaded, ready-to-play track
local currentAnimId:  string?         = nil  -- the AnimationId string (to detect changes)

-- Unarmed punch track — loaded once and reused.
local punchTrack: AnimationTrack? = nil

-- ── Module state ──────────────────────────────────────────────────────────
local started     = false                           -- guard against calling Start() twice
local connections: { RBXScriptConnection } = {}    -- list of all event connections so we can clean them up later

-- ── Helper: logging ───────────────────────────────────────────────────────
local function log(...)
	print("[Combat]", ...)
end

-- ── Helper: get the Animator from a character ─────────────────────────────
-- Every R15 rig has a Humanoid, and every Humanoid needs an Animator to play
-- animations. This function finds the existing Animator or creates one if missing.
local function getAnimatorForChar(char: Model): Animator?
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum then
		return nil
	end

	-- FindFirstChildOfClass returns the first child that is exactly that class.
	local existing = hum:FindFirstChildOfClass("Animator")
	if existing then
		return existing
	end

	-- If no Animator exists yet, create one. This is safe to do on the client.
	local created = Instance.new("Animator")
	created.Parent = hum
	return created
end

-- ── Helper: get the currently equipped Tool ───────────────────────────────
-- In Roblox, when a player equips a Tool, it moves from their Backpack into
-- their Character model. So we scan the Character's children for a Tool.
local function getEquippedTool(): Tool?
	local char = player.Character
	if not char then
		return nil
	end

	for _, child in ipairs(char:GetChildren()) do
		if child:IsA("Tool") then
			return child  -- can only have one Tool equipped at a time
		end
	end
	return nil
end

-- ── Helper: clear the cached animation track ─────────────────────────────
-- Called when the player unequips a tool or switches tools.
-- We stop the old animation and clear the references so the next attack
-- loads a fresh track for the new tool.
local function clearCachedTrack()
	local track = currentTrack
	if track then
		if track.IsPlaying then
			-- Stop with a 0.05-second fade-out so it doesn't cut abruptly.
			track:Stop(0.05)
		end
	end

	currentTool    = nil
	currentAnimObj = nil
	currentTrack   = nil
	currentAnimId  = nil
end

-- ── Helper: load (or reuse) the swing animation for the current tool ──────
-- Returns the AnimationTrack ready to play, or nil if there's no animation.
--
-- We only reload the animation if:
--   • The tool changed (player switched weapons)
--   • The AnimationId changed (tool was modified at runtime)
--   • We don't have a cached track yet
local function ensureToolTrack(): AnimationTrack?
	local char = player.Character
	if not char then
		return nil
	end

	-- Make sure we have an Animator reference.
	animator = animator or getAnimatorForChar(char)
	local anim = animator
	if not anim then
		return nil
	end

	local tool = getEquippedTool()
	if not tool then
		-- No tool equipped → no animation needed (unarmed punch has no special anim).
		clearCachedTrack()
		return nil
	end

	-- Each Tool can have a child Animation object named "SwingAnim".
	-- If the tool doesn't have one, we skip the animation but still allow the attack.
	local animObj = tool:FindFirstChild("SwingAnim")
	if not animObj or not animObj:IsA("Animation") then
		clearCachedTrack()
		currentTool = tool  -- remember this tool even though it has no anim
		return nil
	end

	local animId     = animObj.AnimationId
	local toolChanged = (tool ~= currentTool)
	local idChanged   = (animId ~= currentAnimId)

	if toolChanged or idChanged or (currentTrack == nil) then
		-- Cache the new tool/id before loading so we don't re-enter this block.
		currentTool    = tool
		currentAnimObj = animObj
		currentAnimId  = animId

		-- LoadAnimation can fail if the AnimationId is invalid, so we use pcall.
		-- pcall (protected call) catches errors and returns: ok, result.
		-- If ok is false, result is the error message.
		local ok, result = pcall(function()
			return anim:LoadAnimation(animObj)
		end)

		if not ok then
			log("Failed to LoadAnimation:", result)
			currentTrack = nil
			return nil
		end

		local track = result :: AnimationTrack
		-- Action priority ensures the swing plays over default idle/walk animations.
		-- Roblox animation priority order: Idle < Movement < Action < Action2 < Action3 < Action4
		track.Priority = Enum.AnimationPriority.Action
		currentTrack   = track

		log("Loaded SwingAnim from tool:", tool.Name, "AnimId:", animId)
	end

	return currentTrack
end

-- ── Helper: load (or reload) the unarmed punch animation track ───────────
-- Called after binding a character so the punch track is ready before the
-- first attack. Safe to call multiple times — skips work if already loaded.
local function loadPunchTrack()
	if PUNCH_ANIM_ID == "" then
		return  -- no animation configured
	end

	local anim = animator
	if not anim then
		return
	end

	-- If we already have a valid track we can reuse it.
	-- A track becomes invalid (IsPlaying but Stopped internally) after the
	-- character respawns, so we also clear punchTrack in bindCharacter.
	if punchTrack then
		return
	end

	-- Create a temporary Animation object just to load the track.
	-- We don't need to keep the Animation object around after loading.
	local animObj = Instance.new("Animation")
	animObj.AnimationId = PUNCH_ANIM_ID

	local ok, result = pcall(function()
		return anim:LoadAnimation(animObj)
	end)

	animObj:Destroy()  -- clean up; the track is what we keep, not the Animation

	if not ok then
		log("Failed to load punch animation:", result)
		return
	end

	local track = result :: AnimationTrack
	track.Priority = Enum.AnimationPriority.Action
	punchTrack = track
	log("Punch animation loaded.")
end

-- ── Helper: bind the local character ─────────────────────────────────────
-- Called whenever the player's character spawns (or respawns).
-- Refreshes our references to the Humanoid and Animator.
local function bindCharacter(char: Model)
	-- Clear the punch track on respawn — old tracks become invalid after the
	-- character model is destroyed and recreated.
	punchTrack = nil

	local hum = char:FindFirstChildOfClass("Humanoid")

	if not hum then
		-- The Character model isn't fully loaded yet (parts stream in async).
		-- task.defer runs our callback at the end of the current frame,
		-- giving the engine a moment to finish adding children.
		task.defer(function()
			local hum2 = char:FindFirstChildOfClass("Humanoid")
			if hum2 then
				humanoid = hum2
				animator = getAnimatorForChar(char)
				clearCachedTrack()
				loadPunchTrack()
				log("Bound character (deferred). animator=", animator ~= nil)
			end
		end)
		return
	end

	humanoid = hum
	animator = getAnimatorForChar(char)
	clearCachedTrack()
	loadPunchTrack()
	log("Bound character. animator=", animator ~= nil)
end

-- ── Helper: play the swing or punch animation ────────────────────────────
-- If a tool is equipped and has a SwingAnim, plays that.
-- If unarmed, plays the punch animation (if configured).
-- The attack fires to the server regardless of whether an animation plays.
local function playSwing()
	-- To add a swing sound effect, uncomment this line and replace the ID:
	-- playSoundOnCharacter("rbxassetid://YOUR_SOUND_ID_HERE", 0.6, 1.0)

	local toolTrack = ensureToolTrack()
	if toolTrack then
		-- Play(fadeTime, weight, speed)
		-- fadeTime 0.05 = quick blend-in so it doesn't snap
		-- weight 1 = full influence on the rig
		-- speed 1.0 = normal playback speed
		toolTrack:Play(0.05, 1, 1.0)
		return
	end

	-- No tool track → try the unarmed punch animation.
	-- We lazily load it here too in case it wasn't ready when the character spawned.
	if not punchTrack then
		loadPunchTrack()
	end

	local punch = punchTrack
	if punch then
		punch:Play(0.05, 1, 1.0)
	end
end

-- ── Helper: show a floating damage number over a hit enemy ────────────────
-- BillboardGui is a GUI that lives in 3D space, always facing the camera.
-- We attach it to the enemy's HumanoidRootPart so it floats above them.
-- TweenService animates it upward and fades it out in 0.35 seconds.
local function showDamageNumber(targetModel: Model, amount: number)
	local hrp = targetModel:FindFirstChild("HumanoidRootPart")
	if not hrp or not hrp:IsA("BasePart") then
		return
	end

	-- Create the BillboardGui container.
	local gui = Instance.new("BillboardGui")
	gui.Name                  = "DamageNumber"
	gui.Adornee               = hrp          -- attach to the enemy's root part
	gui.Size                  = UDim2.fromOffset(200, 60)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 3, 0)  -- start 3 studs above the root part
	gui.AlwaysOnTop           = true         -- visible through walls (good for gameplay feedback)
	gui.Parent                = hrp

	-- Create the text label that shows the damage number.
	local txt = Instance.new("TextLabel")
	txt.BackgroundTransparency = 1           -- no background box
	txt.Size                   = UDim2.fromScale(1, 1)  -- fill the BillboardGui
	txt.Text                   = tostring(math.floor(amount + 0.5))  -- round to nearest integer
	txt.TextScaled             = true        -- font scales to fit the label size
	txt.Font                   = Enum.Font.GothamBlack
	txt.TextColor3             = Color3.fromRGB(255, 220, 220)  -- pale red
	txt.TextStrokeTransparency = 0.4         -- slight dark outline for readability
	txt.Parent                 = gui

	-- Animate: float upward and fade out simultaneously.
	local startOffset = gui.StudsOffsetWorldSpace
	local goalOffset  = startOffset + Vector3.new(0, 2.0, 0)  -- rise 2 studs

	-- TweenInfo.new(duration, easingStyle, easingDirection)
	-- Quad easing with Out means it starts fast and slows down at the end.
	local tweenInfo = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

	-- Tween 1: move the billboard upward.
	local tween1 = TweenService:Create(gui, tweenInfo, { StudsOffsetWorldSpace = goalOffset })

	-- Tween 2: fade the text to fully transparent.
	local tween2 = TweenService:Create(txt, tweenInfo, {
		TextTransparency      = 1,
		TextStrokeTransparency = 1,
	})

	tween1:Play()
	tween2:Play()

	-- Clean up the GUI after the animation finishes.
	-- task.delay(seconds, callback) runs the callback after a delay.
	task.delay(0.4, function()
		gui:Destroy()
	end)
end

-- ── Core: attempt an attack ───────────────────────────────────────────────
-- This is the single entry point for all attack inputs.
-- It enforces the client-side cooldown, plays the animation,
-- and fires the RemoteEvent to the server.
local function tryAttack()
	-- Client-side cooldown: ignore rapid re-presses.
	-- os.clock() gives high-precision elapsed time in seconds.
	local now = os.clock()
	if now - lastAttack < COOLDOWN then
		return
	end
	lastAttack = now

	-- Play the swing animation (if any). This is purely visual — it does not
	-- affect damage. The server doesn't care about animations.
	playSwing()

	-- Tell the server we attacked. The server will:
	--   1. Check its own cooldown (prevents cheaters who bypass the client cooldown)
	--   2. Find the nearest enemy within range
	--   3. Apply damage based on which tool the player has equipped (server-side lookup)
	--   4. Fire CombatHit back to all clients so everyone sees the damage number
	attackEvent:FireServer()
end

-- ── Module ────────────────────────────────────────────────────────────────
-- Modules in Roblox return a table. Other scripts do:
--   local Combat = require(Combat)
--   Combat.Start()
local M = {}

function M.Start()
	-- Guard: Start() should only run once even if called multiple times.
	if started then
		return
	end
	started = true

	-- If the character already exists when this module loads, bind it immediately.
	if player.Character then
		bindCharacter(player.Character)
	end

	-- CharacterAdded fires every time the player spawns or respawns.
	-- We use table.insert(connections, ...) to keep a reference to the connection
	-- so we could disconnect it later if needed (e.g. module cleanup).
	table.insert(connections, player.CharacterAdded:Connect(bindCharacter))

	-- ── Input detection ────────────────────────────────────────────────────
	-- InputBegan fires when ANY input starts: key press, mouse click, gamepad, etc.
	-- `gameProcessed` is true when Roblox already handled the input (e.g. typing in
	-- a TextBox, clicking a GUI button). We return early so we don't attack while
	-- the player is typing in a chat box.
	table.insert(connections, UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then
			return
		end

		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			-- Left click → always try a combat attack.
			-- When a tool IS equipped:
			--   • Combat.luau fires CombatAttack → CombatService deals damage to
			--     enemies (IsEnemy models) based on the equipped tool name.
			--   • The tool's own AxeClient/etc. also fires via tool.Activated, which
			--     handles tree-cutting and its own sphere overlap. The two systems
			--     target different things so there's no double-damage on skeletons.
			-- When NO tool is equipped:
			--   • CombatService deals unarmed (fist) damage.
			tryAttack()

		elseif input.KeyCode == ATTACK_KEY then
			-- F key → attack with whatever is equipped (or bare fists if nothing is).
			-- This is the universal "swing" input regardless of tool type.
			tryAttack()
		end
	end))

	-- ── Hit feedback ───────────────────────────────────────────────────────
	-- The server fires CombatHit to ALL clients when a hit lands.
	-- Arguments: (attacker: Player, targetModel: Model, damage: number)
	-- `attacker` was added so ComboCounter.luau can tell whose combo to update.
	-- Here we only care about showing the floating damage number above the target.
	table.insert(connections, hitEvent.OnClientEvent:Connect(function(_attacker: Player, targetModel: Model, damage: number)
		if typeof(damage) ~= "number" then
			return
		end
		showDamageNumber(targetModel, damage)
	end))

	log("Combat started.")
end

return M
