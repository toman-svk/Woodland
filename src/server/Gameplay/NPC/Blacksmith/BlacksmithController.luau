--!strict
-- src/server/Gameplay/NPC/Blacksmith/BlacksmithController.luau

local Players = game:GetService("Players")
local Debris = game:GetService("Debris")

local BlacksmithController = {}

local ANIMATION_ID = "rbxassetid://76100627562076"
local GREET_SOUND_ID = "rbxassetid://132538344661103"

local TRIGGER_DISTANCE = 25
local COOLDOWN = 20

local SOUND_VOLUME = 0.9
local SOUND_MAX_DISTANCE = 60
local SOUND_SPEED_MIN = 0.98
local SOUND_SPEED_MAX = 1.03

local running = false



local function getAnyRoot(model: Model): BasePart?
	local pp = model.PrimaryPart
	if pp and pp:IsA("BasePart") then
		return pp
	end

	local hrp = model:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:IsA("BasePart") then
		return hrp
	end

	local anyPart = model:FindFirstChildWhichIsA("BasePart", true)
	if anyPart then
		return anyPart
	end

	return nil
end

local function getOrCreateAnimator(parent: Instance): Animator?
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
		warn("[BlacksmithController] LoadAnimation failed.")
		return nil
	end

	if typeof(result) == "Instance" and result:IsA("AnimationTrack") then
		local track = result :: AnimationTrack
		track.Priority = Enum.AnimationPriority.Action
		track.Looped = false
		return track
	end

	return nil
end

local function playGreetSound(parentPart: BasePart)
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

	local pivotNow = npc:GetPivot()
	local lookAt = pivotNow.Position + flatDir.Unit

	local newPivot = CFrame.new(
		pivotNow.Position,
		Vector3.new(lookAt.X, pivotNow.Position.Y, lookAt.Z)
	)

	npc:PivotTo(newPivot)
end

function BlacksmithController.Start(generated: Folder)
	if running then
		return
	end
	running = true

	local npcModel = generated:FindFirstChild("Blacksmith")
	if not (npcModel and npcModel:IsA("Model")) then
		warn("[BlacksmithController] Blacksmith model not found under", generated:GetFullName())
		return
	end

	local humanoid = npcModel:FindFirstChildOfClass("Humanoid")
	local animController = npcModel:FindFirstChildOfClass("AnimationController")

	local animator: Animator? = nil
	if humanoid then
		animator = getOrCreateAnimator(humanoid)
	elseif animController then
		animator = getOrCreateAnimator(animController)
	else
		warn("[BlacksmithController] No Humanoid or AnimationController found under:", npcModel:GetFullName())
		return
	end

	if not animator then
		warn("[BlacksmithController] Could not create/find Animator under NPC.")
		return
	end

	local greetTrack = loadTrack(animator)

	local npcRoot = getAnyRoot(npcModel)
	if not npcRoot then
		warn("[BlacksmithController] No BasePart found under:", npcModel:GetFullName())
		return
	end

	local lastTrigger: {[number]: number} = {}

	task.spawn(function()
		while npcModel.Parent ~= nil do
			task.wait(1)

			for _, player in ipairs(Players:GetPlayers()) do
				local char = player.Character
				if not char then
					continue
				end

				local playerRoot = char:FindFirstChild("HumanoidRootPart")
				if not (playerRoot and playerRoot:IsA("BasePart")) then
					continue
				end

				local dist = (playerRoot.Position - npcRoot.Position).Magnitude
				if dist > TRIGGER_DISTANCE then
					continue
				end

				local now = os.clock()
				local last = lastTrigger[player.UserId] or 0
				if (now - last) < COOLDOWN then
					continue
				end
				lastTrigger[player.UserId] = now

				facePlayerYaw(npcModel, npcRoot, playerRoot)
				playGreetSound(npcRoot)

				if greetTrack then
					if greetTrack.IsPlaying then
						greetTrack:Stop(0.05)
					end
					greetTrack:Play(0.05, 1, 1)
				end
			end
		end
	end)

	print("[BlacksmithController] Started for", npcModel:GetFullName())
end

return BlacksmithController