--!strict
-- src/shared/WorldClientModules/Spells.luau

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")

local player = Players.LocalPlayer
if not player then
	warn("[Spells] LocalPlayer missing")
	return {} -- ModuleScript must return one value
end

local Shared = ReplicatedStorage:WaitForChild("Shared")
local RemotesFolder = Shared:WaitForChild("Remotes")
local GetRemote = require(RemotesFolder:WaitForChild("GetRemote"))

local CastSpell = GetRemote("CastSpell", "RemoteEvent") :: RemoteEvent

-- ===== Tuning =====
local ACTION_NAME = "CastSpell_Q"
local COOLDOWN = 1.0

local function getEquippedTool(): Tool?
	local character = player.Character
	if not character then return nil end
	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("Tool") then
			return child
		end
	end
	return nil
end

local function createSlashTrail(tool: Tool): Trail?
	local handle = tool:FindFirstChild("Handle")
	if not (handle and handle:IsA("BasePart")) then
		return nil
	end

	local existing = handle:FindFirstChild("SpellTrail")
	if existing and existing:IsA("Trail") then
		return existing
	end

	local a0 = Instance.new("Attachment")
	a0.Name = "SpellTrailA0"
	a0.Position = Vector3.new(0, 0.6, 0)
	a0.Parent = handle

	local a1 = Instance.new("Attachment")
	a1.Name = "SpellTrailA1"
	a1.Position = Vector3.new(0, -0.6, 0)
	a1.Parent = handle

	local trail = Instance.new("Trail")
	trail.Name = "SpellTrail"
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Enabled = false
	trail.Lifetime = 0.12
	trail.MinLength = 0.02
	trail.LightEmission = 1
	trail.FaceCamera = true

	trail.WidthScale = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.0),
		NumberSequenceKeypoint.new(0.15, 0.35),
		NumberSequenceKeypoint.new(1, 0.0),
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

local CAST_ANIM_ID = "rbxassetid://78755950367678"

local lastCast = 0.0
local castTrack: AnimationTrack? = nil
local castAnimObj: Animation? = nil

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

local function ensureCastTrack(): AnimationTrack?
	local _, animator = getHumanoidAndAnimator()
	if not animator then
		return nil
	end

	if not castAnimObj then
		local a = Instance.new("Animation")
		a.Name = "SpellCastAnim"
		a.AnimationId = CAST_ANIM_ID
		castAnimObj = a
	end

	local anim = castAnimObj :: Animation

	if not castTrack then
		local track = animator:LoadAnimation(anim)
		track.Priority = Enum.AnimationPriority.Action
		castTrack = track
	end

	return castTrack
end

local function playCastAnim()
	local track = ensureCastTrack()
	if not track then return end

	if CAST_ANIM_ID == "rbxassetid://0" or CAST_ANIM_ID == "" then
		warn("[Spells] CAST_ANIM_ID not set yet.")
		return
	end

	track:Play(0.05, 1, 1)
	track:AdjustSpeed(2.5)
end

local function canCast(): boolean
	local now = os.clock()
	return (now - lastCast) >= COOLDOWN
end

local function cast()
	if not canCast() then return end
	lastCast = os.clock()

	playCastAnim()
	enableTrailForCast(0.35)

	CastSpell:FireServer({
		spellId = "BasicStrike",
	})
end

local function onAction(_actionName: string, inputState: Enum.UserInputState, _inputObj: InputObject)
	if inputState ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end
	cast()
	return Enum.ContextActionResult.Sink
end

local function createMobileButton()
	if not UserInputService.TouchEnabled then
		return
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "SpellButtonGui"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 20
	gui.Parent = player:WaitForChild("PlayerGui")

	local btn = Instance.new("TextButton")
	btn.Name = "CastSpellButton"
	btn.AnchorPoint = Vector2.new(1, 1)
	btn.Position = UDim2.new(1, -28, 1, -28)
	btn.Size = UDim2.new(0, 88, 0, 88)
	btn.BackgroundColor3 = Color3.fromRGB(35, 35, 45)
	btn.BackgroundTransparency = 0.15
	btn.BorderSizePixel = 0
	btn.Text = "Q"
	btn.TextScaled = true
	btn.Font = Enum.Font.GothamBold
	btn.TextColor3 = Color3.fromRGB(255, 255, 255)
	btn.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 18)
	corner.Parent = btn

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Transparency = 0.25
	stroke.Parent = btn

	btn.Activated:Connect(cast)
end

local M = {}
local started = false

function M.Start()
	if started then return end
	started = true

	ContextActionService:BindAction(ACTION_NAME, onAction, false, Enum.KeyCode.Q)

	player.CharacterAdded:Connect(function()
		castTrack = nil
		task.defer(function()
			ensureCastTrack()
		end)
	end)

	createMobileButton()
end

return M