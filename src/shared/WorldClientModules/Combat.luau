--!strict
-- src/shared/WorldClientModules/Combat.client.luau
-- Combat client module: fires CombatAttack, listens to CombatHit.

local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer

local Shared = ReplicatedStorage:WaitForChild("Shared")
local RemotesFolder = Shared:WaitForChild("Remotes")

local GetRemote = require(RemotesFolder:WaitForChild("GetRemote"))

local attackEvent = GetRemote("CombatAttack", "RemoteEvent") :: RemoteEvent
local hitEvent = GetRemote("CombatHit", "RemoteEvent") :: RemoteEvent

-- Tuning
local ATTACK_KEY = Enum.KeyCode.F
local COOLDOWN = 0.5
local lastAttack = 0.0

-- Sounds (replace with your own IDs)
local SWING_SOUND_ID = "rbxassetid://12222225"
local HIT_SOUND_ID = "rbxassetid://12222124"

-- Animation cache
local humanoid: Humanoid? = nil
local animator: Animator? = nil

local currentTool: Tool? = nil
local currentAnimObj: Animation? = nil
local currentTrack: AnimationTrack? = nil
local currentAnimId: string? = nil

local started = false
local connections: { RBXScriptConnection } = {}

local function log(...)
	print("[Combat]", ...)
end

local function getAnimatorForChar(char: Model): Animator?
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum then
		return nil
	end

	local existing = hum:FindFirstChildOfClass("Animator")
	if existing then
		return existing
	end

	local created = Instance.new("Animator")
	created.Parent = hum
	return created
end

local function playSoundOnCharacter(soundId: string, volume: number, pitch: number?)
	local char = player.Character
	if not char then
		return
	end

	local root = char:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return
	end

	local s = Instance.new("Sound")
	s.SoundId = soundId
	s.Volume = volume
	s.RollOffMaxDistance = 40
	if pitch then
		s.PlaybackSpeed = pitch
	end
	s.Parent = root
	s:Play()
	s.Ended:Connect(function()
		s:Destroy()
	end)
end

local function getEquippedTool(): Tool?
	local char = player.Character
	if not char then
		return nil
	end

	for _, child in ipairs(char:GetChildren()) do
		if child:IsA("Tool") then
			return child
		end
	end
	return nil
end

local function clearCachedTrack()
	local track = currentTrack
	if track then
		if track.IsPlaying then
			track:Stop(0.05)
		end
	end

	currentTool = nil
	currentAnimObj = nil
	currentTrack = nil
	currentAnimId = nil
end

local function ensureToolTrack(): AnimationTrack?
	local char = player.Character
	if not char then
		return nil
	end

	animator = animator or getAnimatorForChar(char)
	local anim = animator
	if not anim then
		return nil
	end

	local tool = getEquippedTool()
	if not tool then
		clearCachedTrack()
		return nil
	end

	local animObj = tool:FindFirstChild("SwingAnim")
	if not animObj or not animObj:IsA("Animation") then
		clearCachedTrack()
		currentTool = tool
		return nil
	end

	local animId = animObj.AnimationId
	local toolChanged = (tool ~= currentTool)
	local idChanged = (animId ~= currentAnimId)

	if toolChanged or idChanged or (currentTrack == nil) then
		currentTool = tool
		currentAnimObj = animObj
		currentAnimId = animId

		local ok, result = pcall(function()
			return anim:LoadAnimation(animObj)
		end)

		if not ok then
			log("Failed to LoadAnimation:", result)
			currentTrack = nil
			return nil
		end

		local track = result :: AnimationTrack
		track.Priority = Enum.AnimationPriority.Action
		currentTrack = track

		log("Loaded SwingAnim from tool:", tool.Name, "AnimId:", animId)
	end

	return currentTrack
end

local function bindCharacter(char: Model)
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum then
		task.defer(function()
			local hum2 = char:FindFirstChildOfClass("Humanoid")
			if hum2 then
				humanoid = hum2
				animator = getAnimatorForChar(char)
				clearCachedTrack()
				log("Bound character (deferred). animator=", animator ~= nil)
			end
		end)
		return
	end

	humanoid = hum
	animator = getAnimatorForChar(char)
	clearCachedTrack()
	log("Bound character. animator=", animator ~= nil)
end

local function playSwing()
	playSoundOnCharacter(SWING_SOUND_ID, 0.6, 1.0)

	local track = ensureToolTrack()
	if track then
		track:Play(0.05, 1, 1.0)
	end
end

local function showDamageNumber(targetModel: Model, amount: number)
	local hrp = targetModel:FindFirstChild("HumanoidRootPart")
	if not hrp or not hrp:IsA("BasePart") then
		return
	end

	local gui = Instance.new("BillboardGui")
	gui.Name = "DamageNumber"
	gui.Adornee = hrp
	gui.Size = UDim2.fromOffset(200, 60)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 3, 0)
	gui.AlwaysOnTop = true
	gui.Parent = hrp

	local txt = Instance.new("TextLabel")
	txt.BackgroundTransparency = 1
	txt.Size = UDim2.fromScale(1, 1)
	txt.Text = tostring(math.floor(amount + 0.5))
	txt.TextScaled = true
	txt.Font = Enum.Font.GothamBlack
	txt.TextColor3 = Color3.fromRGB(255, 220, 220)
	txt.TextStrokeTransparency = 0.4
	txt.Parent = gui

	local startOffset = gui.StudsOffsetWorldSpace
	local goalOffset = startOffset + Vector3.new(0, 2.0, 0)

	local tween1 = TweenService:Create(
		gui,
		TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ StudsOffsetWorldSpace = goalOffset }
	)

	local tween2 = TweenService:Create(
		txt,
		TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ TextTransparency = 1, TextStrokeTransparency = 1 }
	)

	tween1:Play()
	tween2:Play()

	task.delay(0.4, function()
		gui:Destroy()
	end)
end

local function tryAttack(source: string)
	local now = os.clock()
	if now - lastAttack < COOLDOWN then
		return
	end
	lastAttack = now

	playSwing()
	attackEvent:FireServer()
	-- log("ATTACK fired. source=", source)
end

local M = {}

function M.Start()
	if started then
		return
	end
	started = true

	if player.Character then
		bindCharacter(player.Character)
	end
	table.insert(connections, player.CharacterAdded:Connect(bindCharacter))

	table.insert(connections, UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			local tool = getEquippedTool()
			if not tool then
				tryAttack("MouseButton1_Unarmed")
			end
		elseif input.KeyCode == ATTACK_KEY then
			tryAttack("Key_F")
		end
	end))

	table.insert(connections, hitEvent.OnClientEvent:Connect(function(targetModel: Model, damage: number)
		if typeof(damage) ~= "number" then
			return
		end
		playSoundOnCharacter(HIT_SOUND_ID, 0.7, 1.0)
		showDamageNumber(targetModel, damage)
	end))

	log("Combat started.")
end

return M