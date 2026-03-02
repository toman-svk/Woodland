--!strict
-- ServerScriptService/Server/Systems/TreeSound.luau

local Debris = game:GetService("Debris")

local TreeSound = {}

-- Put your tree sounds here:
TreeSound.IMPACT_SOUND_ID = "rbxassetid://79771534291718"
TreeSound.BREAK_SOUND_ID = "rbxassetid://5451436860"

-- Tuning
TreeSound.VOLUME_IMPACT = 0.75
TreeSound.VOLUME_BREAK = 0.9

TreeSound.PLAYBACK_SPEED_MIN = 0.95
TreeSound.PLAYBACK_SPEED_MAX = 1.05

TreeSound.MAX_DISTANCE = 80 -- 3D rolloff distance

local function pickSoundParent(target: Instance): BasePart?
	if target:IsA("BasePart") then
		return target
	end
	if target:IsA("Model") then
		local pp = target.PrimaryPart
		if pp then return pp end
		local anyPart = target:FindFirstChildWhichIsA("BasePart", true)
		return anyPart
	end
	return nil
end

local function newTempEmitter(pos: Vector3): BasePart
	local p = Instance.new("Part")
	p.Name = "TreeSoundEmitter"
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Transparency = 1
	p.Size = Vector3.new(0.5, 0.5, 0.5)
	p.CFrame = CFrame.new(pos)
	p.Parent = workspace
	return p
end

local function playOnPart(part: BasePart, soundId: string, volume: number, randomizeSpeed: boolean)
	local s = Instance.new("Sound")
	s.SoundId = soundId
	s.Volume = volume
	s.RollOffMaxDistance = TreeSound.MAX_DISTANCE

	if randomizeSpeed then
		local speed = TreeSound.PLAYBACK_SPEED_MIN + math.random() * (TreeSound.PLAYBACK_SPEED_MAX - TreeSound.PLAYBACK_SPEED_MIN)
		s.PlaybackSpeed = speed
	end

	s.Parent = part
	s:Play()
	Debris:AddItem(s, 4)
end

function TreeSound.PlayImpact(target: Instance)
	local parentPart = pickSoundParent(target)
	if not parentPart then return end
	playOnPart(parentPart, TreeSound.IMPACT_SOUND_ID, TreeSound.VOLUME_IMPACT, true)
end

function TreeSound.PlayImpactAt(pos: Vector3)
	local emitter = newTempEmitter(pos)
	playOnPart(emitter, TreeSound.IMPACT_SOUND_ID, TreeSound.VOLUME_IMPACT, true)
	Debris:AddItem(emitter, 4)
end

function TreeSound.PlayBreakAt(pos: Vector3)
	local emitter = newTempEmitter(pos)

	local s = Instance.new("Sound")
	s.SoundId = TreeSound.BREAK_SOUND_ID
	s.Volume = TreeSound.VOLUME_BREAK
	s.RollOffMaxDistance = TreeSound.MAX_DISTANCE

	-- ✅ Speed up 2x
	s.PlaybackSpeed = 3

	s.Parent = emitter
	s:Play()

	-- ✅ Stop after 2 seconds (4 seconds of original audio at 2x speed)
	task.delay(1, function()
		if s and s.Parent then
			s:Stop()
		end
	end)

	-- Clean up
	Debris:AddItem(emitter, 3)
end

return TreeSound