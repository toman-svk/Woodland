--!strict
-- src/shared/WorldClientModules/AmbientAudio.luau

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local shared = ReplicatedStorage:WaitForChild("Shared")
local remotes = shared:WaitForChild("Remotes")

local dayStarted = remotes:WaitForChild("DayStarted") :: RemoteEvent
local phaseChanged = remotes:WaitForChild("PhaseChanged") :: RemoteEvent

local audioFolder = shared:WaitForChild("Audio") :: Folder

type Phase = "Day" | "Night"

local FADE_TIME = 1.25
local DAY_VOL = 0.35
local NIGHT_VOL = 0.35

local function getSoundTemplate(name: string): Sound?
	local inst = audioFolder:FindFirstChild(name)
	if inst and inst:IsA("Sound") then
		return inst
	end
	warn("[AmbientAudio] Missing sound template:", name)
	return nil
end

local function getOrCloneToSoundService(name: string): Sound?
	local existing = SoundService:FindFirstChild(name)
	if existing and existing:IsA("Sound") then
		return existing
	end

	local template = getSoundTemplate(name)
	if not template then
		return nil
	end

	local clone = template:Clone()
	clone.Name = name
	clone.Parent = SoundService
	return clone
end

local ambientDay = getOrCloneToSoundService("Ambient_Forest_Sound_Day")
local ambientNight = getOrCloneToSoundService("Ambient_Forest_Sound_Night")
local birds = getOrCloneToSoundService("Morning_Birds")
local rooster = getOrCloneToSoundService("Rooster")

local currentPhase: Phase? = nil
local birdsConn: RBXScriptConnection? = nil

local function tweenVolume(s: Sound, toVol: number, timeSec: number): Tween
	local info = TweenInfo.new(timeSec, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	local tween = TweenService:Create(s, info, {Volume = toVol})
	tween:Play()
	return tween
end

local function fadeOutAndMaybeStop(s: Sound, timeSec: number)
	tweenVolume(s, 0, timeSec)
	task.delay(timeSec + 0.05, function()
		if s.IsPlaying and s.Volume <= 0.01 then
			s:Stop()
		end
	end)
end

local function startAtZeroAndFadeIn(s: Sound, targetVol: number, timeSec: number)
	s.Looped = true
	if not s.IsPlaying then
		s.Volume = 0
		s:Play()
	end
	tweenVolume(s, targetVol, timeSec)
end

local function setPhase(phase: Phase)
	if currentPhase == phase then
		return
	end
	currentPhase = phase

	if phase == "Day" then
		if ambientNight then
			if ambientNight.IsPlaying then
				fadeOutAndMaybeStop(ambientNight, FADE_TIME)
			else
				ambientNight.Volume = 0
			end
		end

		if ambientDay then
			startAtZeroAndFadeIn(ambientDay, DAY_VOL, FADE_TIME)
		end
	else
		if ambientDay then
			if ambientDay.IsPlaying then
				fadeOutAndMaybeStop(ambientDay, FADE_TIME)
			else
				ambientDay.Volume = 0
			end
		end

		if ambientNight then
			startAtZeroAndFadeIn(ambientNight, NIGHT_VOL, FADE_TIME)
		end
	end
end

local function playBirdsThreeTimes()
	if not birds then
		return
	end

	birds.Looped = false
	birds.TimePosition = 0

	if birdsConn then
		birdsConn:Disconnect()
		birdsConn = nil
	end

	local playsLeft = 3

	local function playOnce()
		if not birds then
			return
		end
		birds.TimePosition = 0
		birds:Play()
	end

	birdsConn = birds.Ended:Connect(function()
		playsLeft -= 1
		if playsLeft > 0 then
			playOnce()
		else
			if birdsConn then
				birdsConn:Disconnect()
				birdsConn = nil
			end
		end
	end)

	playOnce()
end

local function onDayStarted(_dayNumber: number)
	if rooster then
		rooster.Looped = false
		rooster.TimePosition = 0
		rooster:Play()

		rooster.Ended:Once(function()
			playBirdsThreeTimes()
		end)
	else
		task.delay(0.8, playBirdsThreeTimes)
	end
end

phaseChanged.OnClientEvent:Connect(function(phaseAny: any)
	if phaseAny == "Day" then
		setPhase("Day")
	elseif phaseAny == "Night" then
		setPhase("Night")
	else
		warn("[AmbientAudio] PhaseChanged got invalid value:", tostring(phaseAny))
	end
end)

dayStarted.OnClientEvent:Connect(function(dayNumber: any)
	if type(dayNumber) == "number" then
		onDayStarted(dayNumber)
	end
end)

return {
	Start = function()
		print("[AmbientAudio] Started.")
	end,
}