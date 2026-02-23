--!strict
-- src/client/Spells.client.luau

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")

local player = Players.LocalPlayer
if not player then
	warn("[Spells] LocalPlayer missing")
	return
end

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = Shared:WaitForChild("Remotes")
local CastSpell = Remotes:WaitForChild("CastSpell") :: RemoteEvent

-- ===== Tuning =====
local ACTION_NAME = "CastSpell_Q"
local COOLDOWN = 1.0

local Debris = game:GetService("Debris")

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

	-- If you already have a trail from a previous cast, reuse it
	local existing = handle:FindFirstChild("SpellTrail")
	if existing and existing:IsA("Trail") then
		return existing
	end

	-- Attachments define the ribbon endpoints
	local a0 = Instance.new("Attachment")
	a0.Name = "SpellTrailA0"
	a0.Position = Vector3.new(0, 0.6, 0) -- adjust later
	a0.Parent = handle

	local a1 = Instance.new("Attachment")
	a1.Name = "SpellTrailA1"
	a1.Position = Vector3.new(0, -0.6, 0) -- adjust later
	a1.Parent = handle

	local trail = Instance.new("Trail")
	trail.Name = "SpellTrail"
	trail.Attachment0 = a0
	trail.Attachment1 = a1

	-- Look/feel tuning (no custom colors required, but you can)
	trail.Enabled = false
	trail.Lifetime = 0.12
	trail.MinLength = 0.02
	trail.LightEmission = 1
	trail.FaceCamera = true

	-- Width curve (thin->thicker->thin)
	trail.WidthScale = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.0),
		NumberSequenceKeypoint.new(0.15, 0.35),
		NumberSequenceKeypoint.new(1, 0.0),
	})

	-- Optional transparency fade
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

	-- Turn off after duration
	task.delay(duration, function()
		-- tool might be gone / unequipped
		if trail and trail.Parent then
			trail.Enabled = false
		end
	end)
end

-- Replace later with your animation id:
-- Example: "rbxassetid://1234567890"
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
	local humanoid, animator = getHumanoidAndAnimator()
	if not humanoid or not animator then 
		return nil 
	end

	if not castAnimObj then
		local a = Instance.new("Animation")
		a.Name = "SpellCastAnim"
		a.AnimationId = CAST_ANIM_ID
		castAnimObj = a
	end

	-- Now Luau still thinks castAnimObj is Animation?
	-- So we assert it:
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

	-- If you haven’t set the ID yet, don’t spam errors
	if CAST_ANIM_ID == "rbxassetid://0" or CAST_ANIM_ID == "" then
		warn("[Spells] CAST_ANIM_ID not set yet. Put your rbxassetid in CAST_ANIM_ID.")
		return
	end

	track:Play(0.05, 1, 1)
    track:AdjustSpeed(2.5) -- make animation faster
end

local function canCast(): boolean
	local now = os.clock()
	return (now - lastCast) >= COOLDOWN
end

local function cast()
	if not canCast() then return end
	lastCast = os.clock()

	-- Play locally (responsive)
	playCastAnim()
    enableTrailForCast(0.35) -- tune based on your animation

	-- Tell server to apply gameplay effect
	CastSpell:FireServer({
		spellId = "BasicStrike",
	})
end

-- ===== Input bindings =====
local function onAction(_actionName: string, inputState: Enum.UserInputState, _inputObj: InputObject)
	if inputState ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end
	cast()
	return Enum.ContextActionResult.Sink
end

-- Bind for keyboard + gamepad if you want later
ContextActionService:BindAction(ACTION_NAME, onAction, false, Enum.KeyCode.Q)

-- ===== Mobile button =====
-- ContextActionService automatically shows a touch button if you pass `true` for createTouchButton.
-- BUT positioning is limited. For full control, we’ll make our own ScreenGui button.

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
	btn.Position = UDim2.new(1, -28, 1, -28) -- bottom-right
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

	btn.Activated:Connect(function()
		cast()
	end)
end

-- Rebuild track on respawn (animator changes)
player.CharacterAdded:Connect(function()
	castTrack = nil
	task.defer(function()
		ensureCastTrack()
	end)
end)

createMobileButton()