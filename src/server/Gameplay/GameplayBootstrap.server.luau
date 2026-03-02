-- main entrypoint for gameplay 

-- ServerScriptService/Server/NPC/BlacksmithAnimation.server.lua
--!strict

local Players = game:GetService("Players")
local Debris = game:GetService("Debris")

-- CONFIG
local GENERATED = workspace:WaitForChild("Generated")
local NPC_MODEL = GENERATED:WaitForChild("Blacksmith") :: Model

local ANIMATION_ID = "rbxassetid://76100627562076"
local GREET_SOUND_ID = "rbxassetid://132538344661103"

local TRIGGER_DISTANCE = 25
local COOLDOWN = 20 -- seconds (per player)

-- Sound tuning
local SOUND_VOLUME = 0.9
local SOUND_MAX_DISTANCE = 60
local SOUND_SPEED_MIN = 0.98
local SOUND_SPEED_MAX = 1.03

-- Gameconfig

local ServerScriptService = game:GetService("ServerScriptService")
local GameConfigService = require(ServerScriptService.Server.Gameplay.GameConfigService)::any

GameConfigService.Init()

-- =========================
-- Helpers (strict + nil-safe)
-- =========================

local function getAnyRoot(model: Model): BasePart?
	-- Prefer PrimaryPart if set
	local pp = model.PrimaryPart
	if pp and pp:IsA("BasePart") then
		return pp
	end

	-- Prefer HumanoidRootPart if exists
	local hrp = model:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:IsA("BasePart") then
		return hrp
	end

	-- Fallback: first BasePart anywhere in model
	local anyPart = model:FindFirstChildWhichIsA("BasePart", true)
	if anyPart then
		return anyPart
	end

	return nil
end

local function getOrCreateAnimator(parent: Instance): Animator?
	-- parent can be Humanoid or AnimationController
	local existing = parent:FindFirstChildOfClass("Animator")
	if existing then
		return existing
	end

	local animator = Instance.new("Animator")
	animator.Parent = parent
	return animator
end

local function loadTrack(animator: Animator): AnimationTrack?
	local animation = Instance.new("Animation")
	animation.AnimationId = ANIMATION_ID

	local ok, result = pcall(function()
		return animator:LoadAnimation(animation)
	end)

	if not ok then
		warn("[BlacksmithAnimation] LoadAnimation failed (likely rig mismatch).")
		return nil
	end

	if typeof(result) == "Instance" and result:IsA("AnimationTrack") then
		local track = result :: AnimationTrack
		track.Priority = Enum.AnimationPriority.Action
		track.Looped = false
		return track
	end

	warn("[BlacksmithAnimation] LoadAnimation returned unexpected:", result)
	return nil
end

local function playGreetSound(parentPart: BasePart)
	-- If you already have a Sound under Blacksmith (like “hey guys”), we can reuse it,
	-- but to be deterministic we spawn a temporary one:
	local s = Instance.new("Sound")
	s.Name = "BlacksmithGreet"
	s.SoundId = GREET_SOUND_ID
	s.Volume = SOUND_VOLUME
	s.RollOffMaxDistance = SOUND_MAX_DISTANCE
	s.PlaybackSpeed = SOUND_SPEED_MIN + math.random() * (SOUND_SPEED_MAX - SOUND_SPEED_MIN)
	s.Parent = parentPart
	s:Play()
	Debris:AddItem(s, 4)
end

local function facePlayerYaw(npc: Model, npcRoot: BasePart, playerRoot: BasePart)
	local npcPos = npcRoot.Position
	local playerPos = playerRoot.Position

	local flatDir = Vector3.new(playerPos.X - npcPos.X, 0, playerPos.Z - npcPos.Z)
	if flatDir.Magnitude < 0.001 then
		return
	end

	-- Keep position; change yaw to look at player
	local pivotNow = npc:GetPivot()
	local lookAt = pivotNow.Position + flatDir.Unit

	local newPivot = CFrame.new(
		pivotNow.Position,
		Vector3.new(lookAt.X, pivotNow.Position.Y, lookAt.Z)
	)

	npc:PivotTo(newPivot)
end

-- =========================
-- Init: find animation driver
-- =========================

local humanoid = NPC_MODEL:FindFirstChildOfClass("Humanoid")
local animController = NPC_MODEL:FindFirstChildOfClass("AnimationController")

local animator: Animator? = nil
if humanoid then
	animator = getOrCreateAnimator(humanoid)
elseif animController then
	animator = getOrCreateAnimator(animController)
else
	warn("[BlacksmithAnimation] No Humanoid or AnimationController found under:", NPC_MODEL:GetFullName())
	warn("[BlacksmithAnimation] Add a Humanoid (for rigged NPC) or AnimationController (for animated model).")
	return
end

if not animator then
	warn("[BlacksmithAnimation] Could not create/find Animator under NPC.")
	return
end

local greetTrack: AnimationTrack? = loadTrack(animator)

local npcRoot = getAnyRoot(NPC_MODEL)
if not npcRoot then
	warn("[BlacksmithAnimation] No BasePart found to act as root under:", NPC_MODEL:GetFullName())
	return
end

-- Per-player cooldown
local lastTrigger: { [number]: number } = {}

local function tryTrigger(player: Player)
	local char = player.Character
	if not char then return end

	local pr = char:FindFirstChild("HumanoidRootPart")
	if not (pr and pr:IsA("BasePart")) then return end
	local playerRoot = pr :: BasePart

	local dist = (playerRoot.Position - npcRoot.Position).Magnitude
	if dist > TRIGGER_DISTANCE then return end

	local tNow = os.clock()
	local tLast = lastTrigger[player.UserId] or 0
	if (tNow - tLast) < COOLDOWN then return end
	lastTrigger[player.UserId] = tNow

	-- Face player, then play sound + anim at the same time
	facePlayerYaw(NPC_MODEL, npcRoot, playerRoot)
	playGreetSound(npcRoot)

	if greetTrack then
		if greetTrack.IsPlaying then
			greetTrack:Stop(0.05)
		end
		greetTrack:Play(0.05, 1, 1)
	else
		warn("[BlacksmithAnimation] No animation track (rig mismatch likely). Sound + facing still work.")
	end
end

-- Polling loop (simple and fine for small player counts)
while true do
	task.wait(1)

	-- If NPC removed, stop
	if NPC_MODEL.Parent == nil then
		warn("[BlacksmithAnimation] NPC removed; stopping.")
		break
	end

	for _, p in ipairs(Players:GetPlayers()) do
		tryTrigger(p)
	end
end