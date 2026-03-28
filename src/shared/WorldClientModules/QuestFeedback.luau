--!strict
-- src/shared/WorldClientModules/QuestFeedback.luau

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

local player = Players.LocalPlayer
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = Shared:WaitForChild("Remotes")
local GetRemote = require(Remotes:WaitForChild("GetRemote"))

local questFeedbackRemote = GetRemote("QuestComplete", "RemoteEvent") :: RemoteEvent

local M = {}
local started = false

local QUEST_ACCEPTED_SOUND_ID = "rbxassetid://0" -- TODO
local QUEST_COMPLETED_SOUND_ID = "rbxassetid://0" -- TODO

local ACCEPTED_COLOR = Color3.fromRGB(90, 170, 255)
local COMPLETED_COLOR = Color3.fromRGB(120, 255, 140)

local function log(...)
	print("[QuestFeedback]", ...)
end

local function getRoot(): BasePart?
	local char = player.Character
	if not char then
		log("No character yet")
		return nil
	end

	local hrp = char:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:IsA("BasePart") then
		return hrp
	end

	log("No HumanoidRootPart found")
	return nil
end

local function getRootWithRetry(): BasePart?
	local root = getRoot()
	if root then
		return root
	end

	for _ = 1, 10 do
		task.wait(0.05)
		root = getRoot()
		if root then
			return root
		end
	end

	return nil
end

local function playFeedbackSound(root: BasePart, soundId: string)
	if soundId == "" or soundId == "rbxassetid://0" then
		log("Sound placeholder not set, skipping sound")
		return
	end

	local s = Instance.new("Sound")
	s.Name = "QuestFeedbackSound"
	s.SoundId = soundId
	s.Volume = 0.9
	s.RollOffMaxDistance = 50
	s.Parent = root
	s:Play()
	Debris:AddItem(s, 4)
end

local function emitFeedbackFx(effectName: string, color: Color3)
	local root = getRootWithRetry()
	if not root then
		log("Failed to emit effect, root not found:", effectName)
		return
	end

	log("Emitting FX:", effectName, "at", root:GetFullName())

	local holder = Instance.new("Attachment")
	holder.Name = effectName
	holder.Parent = root

	local particles = Instance.new("ParticleEmitter")
	particles.Name = "QuestGlow"
	particles.Parent = holder
	particles.Color = ColorSequence.new(color)
	particles.LightEmission = 1
	particles.Lifetime = NumberRange.new(0.8, 1.4)
	particles.Rate = 0
	particles.Speed = NumberRange.new(4, 8)
	particles.SpreadAngle = Vector2.new(360, 360)
	particles.Rotation = NumberRange.new(0, 360)
	particles.RotSpeed = NumberRange.new(-50, 50)
	particles.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.8),
		NumberSequenceKeypoint.new(0.5, 1.2),
		NumberSequenceKeypoint.new(1, 0),
	})
	particles.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.15),
		NumberSequenceKeypoint.new(0.7, 0.35),
		NumberSequenceKeypoint.new(1, 1),
	})
	particles.Texture = "rbxasset://textures/particles/sparkles_main.dds"

	local pointLight = Instance.new("PointLight")
	pointLight.Color = color
	pointLight.Brightness = 2
	pointLight.Range = 12
	pointLight.Parent = root

	particles:Emit(40)

	task.spawn(function()
		local steps = 12
		for i = 1, steps do
			pointLight.Brightness = 2 * (1 - i / steps)
			task.wait(0.06)
		end
		if pointLight.Parent then
			pointLight:Destroy()
		end
	end)

	Debris:AddItem(holder, 2)
end

local function handleAccepted()
	local root = getRootWithRetry()
	if not root then
		log("Accepted FX skipped: no root")
		return
	end

	log("Handling accepted FX")
	playFeedbackSound(root, QUEST_ACCEPTED_SOUND_ID)
	emitFeedbackFx("QuestAcceptedFX", ACCEPTED_COLOR)
end

local function handleCompleted()
	local root = getRootWithRetry()
	if not root then
		log("Completed FX skipped: no root")
		return
	end

	log("Handling completed FX")
	playFeedbackSound(root, QUEST_COMPLETED_SOUND_ID)
	emitFeedbackFx("QuestCompletedFX", COMPLETED_COLOR)
end

function M.Start()
	if started then
		return
	end
	started = true

	log("Started")

	questFeedbackRemote.OnClientEvent:Connect(function(data)
		log("Remote received:", data)

		local effect = "QuestComplete"

		if type(data) == "table" then
			local effectAny = (data :: any).effect
			if type(effectAny) == "string" then
				effect = effectAny
			end
		end

		log("Effect parsed:", effect)

		if effect == "BlacksmithQuestAccepted" or effect == "QuestAccepted" then
			handleAccepted()
			return
		end

		if effect == "BlacksmithQuestComplete" or effect == "QuestComplete" then
			handleCompleted()
			return
		end

		log("Unknown effect, fallback to completed")
		handleCompleted()
	end)
end

return M