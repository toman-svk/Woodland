--!strict
-- src/shared/WorldClientModules/Spells.luau
--
-- CLIENT-SIDE spell system.
-- Currently manages one spell: "BasicStrike" (Q key).
--
-- ── COMBO REQUIREMENT ────────────────────────────────────────────────────────
-- The Q spell is locked behind a combo threshold (COMBO_THRESHOLD hits).
-- When the player reaches that combo, a circular "Q" indicator appears on
-- screen and wiggles to signal that the ability is ready.
-- Pressing Q consumes the combo (resets it to 0) and fires a combo-strike
-- at the server, which deals 2× normal damage.
--
-- ── FLOW ─────────────────────────────────────────────────────────────────────
--   ComboCounter.OnComboChanged fires when combo changes
--     → if count > COMBO_THRESHOLD: show Q indicator + start wiggle animation
--     → if count <= COMBO_THRESHOLD: hide Q indicator
--
--   Player presses Q
--     → cast() checks combo >= threshold and cooldown
--       → ComboCounter.ConsumeCombo() — resets the counter, hides display
--       → plays cast animation + trail
--       → CastSpell:FireServer({ spellId="BasicStrike", comboStrike=true })
--         → SpellService finds nearest enemy, deals 2× damage

local Players             = game:GetService("Players")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local UserInputService    = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local TweenService        = game:GetService("TweenService")

local player = Players.LocalPlayer
if not player then
	warn("[Spells] LocalPlayer missing")
	return {}
end

-- Require ComboCounter to read the current combo state and subscribe to changes.
-- Roblox caches module requires, so this returns the SAME table that
-- ClientBootstrap already loaded — no duplicate setup occurs.
local ComboCounter = require(script.Parent:WaitForChild("ComboCounter"))

local Shared        = ReplicatedStorage:WaitForChild("Shared")
local RemotesFolder = Shared:WaitForChild("Remotes")
local GetRemote     = require(RemotesFolder:WaitForChild("GetRemote"))
local CastSpell     = GetRemote("CastSpell", "RemoteEvent") :: RemoteEvent

-- ── Tuning ────────────────────────────────────────────────────────────────────

local ACTION_NAME      = "CastSpell_Q"
local COOLDOWN         = 1.0    -- minimum seconds between casts
local CAST_ANIM_ID     = "rbxassetid://78755950367678"

-- Minimum combo required to use the Q spell.
-- Must be STRICTLY GREATER THAN this value (i.e. 4 hits to unlock at threshold 3).
local COMBO_THRESHOLD  = 2

-- ── State ─────────────────────────────────────────────────────────────────────

local lastCast   = 0.0
local castTrack: AnimationTrack? = nil
local castAnimObj: Animation?    = nil

-- Tracks whether Q is currently castable.
-- Becomes true when the combo hits a new multiple of COMBO_THRESHOLD.
-- Becomes false as soon as Q is cast (until the NEXT multiple is reached).
-- Resets to false when the combo timer expires and the counter resets to 0.
--
-- Why a boolean instead of checking combo % threshold directly?
-- Because without it, pressing Q at combo=6 would still show qAvailable at 6
-- after consuming it (the combo doesn't reset, so 6 % 3 would still be 0).
-- The boolean lets us "consume" the availability exactly once per multiple.
local qAvailable   = false

-- Tracks whether the Q indicator is currently shown.
-- We use this to avoid running the show animation multiple times.
local indicatorVisible = false
local isWiggling       = false

-- ── Helpers: character ────────────────────────────────────────────────────────

local function getEquippedTool(): Tool?
	local character = player.Character
	if not character then return nil end
	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("Tool") then return child end
	end
	return nil
end

local function getHumanoidAndAnimator(): (Humanoid?, Animator?)
	local character = player.Character
	if not character then return nil, nil end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return nil, nil end
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end
	return humanoid, animator
end

-- ── Helpers: cast animation ───────────────────────────────────────────────────

local function ensureCastTrack(): AnimationTrack?
	local _, animator = getHumanoidAndAnimator()
	if not animator then return nil end

	if not castAnimObj then
		local a = Instance.new("Animation")
		a.Name        = "SpellCastAnim"
		a.AnimationId = CAST_ANIM_ID
		castAnimObj   = a
	end

	if not castTrack then
		local track = animator:LoadAnimation(castAnimObj :: Animation)
		track.Priority = Enum.AnimationPriority.Action
		castTrack      = track
	end

	return castTrack
end

local function playCastAnim()
	local track = ensureCastTrack()
	if not track then return end
	if CAST_ANIM_ID == "rbxassetid://0" or CAST_ANIM_ID == "" then
		warn("[Spells] CAST_ANIM_ID not set.")
		return
	end
	track:Play(0.05, 1, 1)
	track:AdjustSpeed(2.5)
end

-- ── Helpers: weapon trail ─────────────────────────────────────────────────────

local function createSlashTrail(tool: Tool): Trail?
	local handle = tool:FindFirstChild("Handle")
	if not (handle and handle:IsA("BasePart")) then return nil end
	local existing = handle:FindFirstChild("SpellTrail")
	if existing and existing:IsA("Trail") then return existing end

	local a0 = Instance.new("Attachment")
	a0.Name     = "SpellTrailA0"
	a0.Position = Vector3.new(0, 0.6, 0)
	a0.Parent   = handle

	local a1 = Instance.new("Attachment")
	a1.Name     = "SpellTrailA1"
	a1.Position = Vector3.new(0, -0.6, 0)
	a1.Parent   = handle

	local trail = Instance.new("Trail")
	trail.Name         = "SpellTrail"
	trail.Attachment0  = a0
	trail.Attachment1  = a1
	trail.Enabled      = false
	trail.Lifetime     = 0.12
	trail.MinLength    = 0.02
	trail.LightEmission = 1
	trail.FaceCamera   = true
	trail.WidthScale   = NumberSequence.new({
		NumberSequenceKeypoint.new(0,    0.0),
		NumberSequenceKeypoint.new(0.15, 0.35),
		NumberSequenceKeypoint.new(1,    0.0),
	})
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(1, 1.0),
	})
	trail.Parent = handle
	return trail
end

local function enableTrailForCast(duration: number)
	local tool = getEquippedTool()
	if not tool then return end
	local trail = createSlashTrail(tool)
	if not trail then return end
	trail.Enabled = true
	task.delay(duration, function()
		if trail and trail.Parent then
			trail.Enabled = false
		end
	end)
end

-- ── Q Indicator UI ────────────────────────────────────────────────────────────
-- A circular badge with "Q" inside that appears at the bottom-centre of the
-- screen when the combo threshold is reached. It wiggles continuously as a
-- call-to-action so the player knows to press Q.

local playerGui = player:WaitForChild("PlayerGui")

local indicatorGui = Instance.new("ScreenGui")
indicatorGui.Name           = "SpellIndicator"
indicatorGui.ResetOnSpawn   = false
indicatorGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
indicatorGui.IgnoreGuiInset = true
indicatorGui.Parent         = playerGui

-- Outer circle frame. UICorner with 0.5 CornerRadius makes any square a circle.
local indicatorFrame = Instance.new("Frame")
indicatorFrame.Name                = "QIndicator"
indicatorFrame.AnchorPoint         = Vector2.new(0.5, 0.5)
indicatorFrame.Position            = UDim2.new(0.5, 0, 0.78, 0)
indicatorFrame.Size                = UDim2.new(0, 90, 0, 90)
indicatorFrame.BackgroundColor3    = Color3.fromRGB(15, 15, 25)
indicatorFrame.BackgroundTransparency = 0.25
indicatorFrame.BorderSizePixel     = 0
indicatorFrame.Visible             = false  -- hidden until combo threshold reached
indicatorFrame.Parent              = indicatorGui

local indicatorCorner = Instance.new("UICorner")
indicatorCorner.CornerRadius = UDim.new(0.5, 0)  -- 0.5 = perfect circle
indicatorCorner.Parent       = indicatorFrame

-- Glowing border ring. Color matches the COMBO TIERS — we'll update it
-- to match the current combo tier color when showing.
local indicatorStroke = Instance.new("UIStroke")
indicatorStroke.Thickness    = 3
indicatorStroke.Color        = Color3.fromRGB(255, 220, 40)  -- golden default
indicatorStroke.Transparency = 0.1
indicatorStroke.Parent       = indicatorFrame

-- UIScale child — we animate this for the "pop in" entrance and exit.
local indicatorScale = Instance.new("UIScale")
indicatorScale.Scale  = 0  -- starts at 0; tweened to 1 on show
indicatorScale.Parent = indicatorFrame

-- The "Q" label inside the circle.
local qLabel = Instance.new("TextLabel")
qLabel.Name                   = "QKey"
qLabel.BackgroundTransparency = 1
qLabel.Size                   = UDim2.fromScale(1, 1)
qLabel.Text                   = "Q"
qLabel.TextScaled             = true
qLabel.Font                   = Enum.Font.GothamBlack
qLabel.TextColor3             = Color3.fromRGB(255, 255, 255)
qLabel.TextStrokeTransparency = 0.3
qLabel.Parent                 = indicatorFrame

-- ── Indicator animation ───────────────────────────────────────────────────────

-- Starts a looping left-right rotation wiggle on the indicator frame.
-- The wiggle makes the "Q" look alive and urgent — a classic game-juice trick.
-- We use task.spawn to run the loop in its own thread so it doesn't block.
-- `isWiggling` acts as a stop flag: setting it to false exits the loop cleanly.
local function startWiggle()
	if isWiggling then return end
	isWiggling = true

	task.spawn(function()
		-- Each iteration: tilt right → tilt left → return to centre → pause.
		while isWiggling do
			-- Lean right (+12°).
			local t1 = TweenService:Create(indicatorFrame,
				TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ Rotation = 12 })
			t1:Play()
			t1.Completed:Wait()  -- :Wait() suspends this coroutine until done
			if not isWiggling then break end

			-- Lean left (−12°).
			local t2 = TweenService:Create(indicatorFrame,
				TweenInfo.new(0.24, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut),
				{ Rotation = -12 })
			t2:Play()
			t2.Completed:Wait()
			if not isWiggling then break end

			-- Return to upright (0°).
			local t3 = TweenService:Create(indicatorFrame,
				TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{ Rotation = 0 })
			t3:Play()
			t3.Completed:Wait()
			if not isWiggling then break end

			-- Brief pause so it's not constant shaking.
			task.wait(0.5)
		end

		-- Always clean up rotation when we exit the loop.
		indicatorFrame.Rotation = 0
	end)
end

local function stopWiggle()
	isWiggling = false
	-- Rotation resets inside the task.spawn loop above after it detects isWiggling=false.
end

-- Shows the Q indicator with a "pop-in" scale animation.
-- `tierColor` tints the stroke ring to match the current combo tier.
local function showIndicator(tierColor: Color3)
	if indicatorVisible then
		-- Already visible — just update the color without re-animating.
		indicatorStroke.Color = tierColor
		return
	end
	indicatorVisible = true
	indicatorFrame.Visible = true
	indicatorStroke.Color  = tierColor

	-- Pop in from scale 0 → 1 with a bouncy Back easing.
	-- Back easing overshoots slightly then settles — feels snappy and satisfying.
	local info  = TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	TweenService:Create(indicatorScale, info, { Scale = 1.0 }):Play()

	startWiggle()
end

-- Hides the Q indicator with a quick scale-down animation.
local function hideIndicator()
	if not indicatorVisible then return end
	indicatorVisible = false
	stopWiggle()

	local info = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	local tween = TweenService:Create(indicatorScale, info, { Scale = 0.0 })
	tween:Play()
	tween.Completed:Connect(function()
		-- Only hide if we didn't immediately re-show while the tween was playing.
		if not indicatorVisible then
			indicatorFrame.Visible = false
		end
	end)
end

-- ── Cast logic ────────────────────────────────────────────────────────────────

local function canCast(): boolean
	return (os.clock() - lastCast) >= COOLDOWN
end

local function cast()
	-- Gate 1: Q must be available (combo hit a new multiple of COMBO_THRESHOLD).
	-- Cooldown is reset automatically when a new multiple is reached, so if
	-- qAvailable is true the cooldown check will always pass — but we keep it
	-- as a safety net against edge cases (e.g. rapid firing via exploits).
	if not qAvailable then return end
	if not canCast() then return end

	-- Mark Q as used. It won't become available again until the NEXT multiple.
	-- (The combo counter keeps running — we do NOT reset it.)
	qAvailable = false
	lastCast   = os.clock()

	-- Hide the indicator immediately so the player gets instant visual feedback
	-- that the ability was consumed.
	hideIndicator()

	-- Play visual effects.
	playCastAnim()
	enableTrailForCast(0.35)

	-- Notify the server. comboStrike=true tells SpellService to apply 2× damage.
	CastSpell:FireServer({
		spellId     = "BasicStrike",
		comboStrike = true,
	})
end

-- ── Input binding ─────────────────────────────────────────────────────────────

local function onAction(_actionName: string, inputState: Enum.UserInputState, _inputObj: InputObject)
	if inputState ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end
	cast()
	return Enum.ContextActionResult.Sink
end

local function createMobileButton()
	if not UserInputService.TouchEnabled then return end

	local gui = Instance.new("ScreenGui")
	gui.Name           = "SpellButtonGui"
	gui.ResetOnSpawn   = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder   = 20
	gui.Parent         = player:WaitForChild("PlayerGui")

	local btn = Instance.new("TextButton")
	btn.Name                  = "CastSpellButton"
	btn.AnchorPoint           = Vector2.new(1, 1)
	btn.Position              = UDim2.new(1, -28, 1, -28)
	btn.Size                  = UDim2.new(0, 88, 0, 88)
	btn.BackgroundColor3      = Color3.fromRGB(35, 35, 45)
	btn.BackgroundTransparency = 0.15
	btn.BorderSizePixel       = 0
	btn.Text                  = "Q"
	btn.TextScaled            = true
	btn.Font                  = Enum.Font.GothamBold
	btn.TextColor3            = Color3.fromRGB(255, 255, 255)
	btn.Parent                = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 18)
	corner.Parent       = btn

	local stroke = Instance.new("UIStroke")
	stroke.Thickness    = 2
	stroke.Transparency = 0.25
	stroke.Parent       = btn

	btn.Activated:Connect(cast)
end

-- ── Combo tier colour helper ──────────────────────────────────────────────────
-- Returns the same colour that ComboCounter uses for a given count,
-- so the Q indicator ring matches the current combo tier visually.
local TIER_COLORS: { { count: number, color: Color3 } } = {
	{ count = 20, color = Color3.fromRGB(200,  80, 255) },
	{ count = 15, color = Color3.fromRGB(255,  60,  60) },
	{ count = 10, color = Color3.fromRGB(255, 150,  30) },
	{ count =  5, color = Color3.fromRGB(255, 220,  40) },
	{ count =  1, color = Color3.fromRGB(255, 255, 255) },
}

local function getTierColor(count: number): Color3
	for _, tier in ipairs(TIER_COLORS) do
		if count >= tier.count then
			return tier.color
		end
	end
	return Color3.fromRGB(255, 255, 255)
end

-- ── Module ────────────────────────────────────────────────────────────────────

local M = {}
local started = false

function M.Start()
	if started then return end
	started = true

	ContextActionService:BindAction(ACTION_NAME, onAction, false, Enum.KeyCode.Q)

	-- Reset cached animation track on respawn (old track becomes invalid
	-- because the Animator is recreated with the new character model).
	player.CharacterAdded:Connect(function()
		castTrack = nil
		task.defer(ensureCastTrack)
	end)

	-- Subscribe to combo changes.
	-- Q becomes available (and its cooldown resets) at every multiple of
	-- COMBO_THRESHOLD: 3 → 6 → 9 → 12 → ...
	-- When the combo timer expires (count resets to 0), Q is locked again.
	ComboCounter.OnComboChanged(function(count: number)
		if count == 0 then
			-- Combo timed out — lock Q and hide the indicator.
			qAvailable = false
			hideIndicator()
			return
		end

		if count % COMBO_THRESHOLD == 0 then
			-- Hit a new multiple (3, 6, 9, …) — unlock Q and reset its cooldown
			-- so the player can cast immediately without waiting.
			qAvailable = true
			lastCast   = 0  -- cooldown reset: next canCast() call returns true instantly
			showIndicator(getTierColor(count))
		end
		-- Non-multiples: don't change qAvailable or the indicator.
		-- If Q is still available from the current multiple, the indicator stays.
	end)

	createMobileButton()

	print("[Spells] Started. Combo threshold for Q:", COMBO_THRESHOLD)
end

return M
