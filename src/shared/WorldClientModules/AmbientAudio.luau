--!strict
-- src/client/AmbientAudio.client.luau
-- Plays ambient day/night loops + DayStarted cues (rooster once, birds 3x)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local shared = ReplicatedStorage:WaitForChild("Shared")
local remotes = shared:WaitForChild("Remotes")
local dayStarted = remotes:WaitForChild("DayStarted") :: RemoteEvent
local phaseChanged = remotes:WaitForChild("PhaseChanged") :: RemoteEvent

local audioFolder = shared:WaitForChild("Audio") :: Folder

type Phase = "Day" | "Night"

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
	if not template then return nil end

	local clone = template:Clone()
	clone.Name = name
	clone.Parent = SoundService
	return clone
end

local dayAmb = getOrCloneToSoundService("Ambient_Forest_Sound_Day")
local nightAmb = getOrCloneToSoundService("Ambient_Forest_Sound_Night")
local birds = getOrCloneToSoundService("Morning_Birds")
local rooster = getOrCloneToSoundService("Rooster")

local function stopSound(s: Sound?)
	if not s then return end
	if s.IsPlaying then
		s:Stop()
	end
end

local function playLoop(s: Sound?)
	if not s then return end
	s.Looped = true
	if not s.IsPlaying then
		s.TimePosition = 0
		s:Play()
	end
end

local function setPhase(phase: Phase)
	if phase == "Day" then
		stopSound(nightAmb)
		playLoop(dayAmb)
	else
		stopSound(dayAmb)
		playLoop(nightAmb)
	end
end

local birdsConn: RBXScriptConnection? = nil

local function playBirdsThreeTimes()
	if not birds then return end

	-- Ensure not infinite loop
	birds.Looped = false
	birds.TimePosition = 0

	-- Disconnect previous counter if any
	if birdsConn then
		birdsConn:Disconnect()
		birdsConn = nil
	end

	local playsLeft = 3

	local function playOnce()
		if not birds then return end
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
	-- Rooster once, then birds 3x
	if rooster then
		rooster.Looped = false
		rooster.TimePosition = 0
		rooster:Play()
	end

	-- Start birds after rooster finishes (fallback delay if Ended isn’t reliable)
	if rooster then
		rooster.Ended:Once(function()
			playBirdsThreeTimes()
		end)
	else
		-- fallback
		task.delay(0.8, playBirdsThreeTimes)
	end
end

local TweenService = game:GetService("TweenService")


local FADE_TIME = 1.25 -- tweak: 0.6..2.0 feels nice
local DAY_VOL = 0.35
local NIGHT_VOL = 0.35

-- These should be your ambient Sound instances (however you created/parented them)
local ambientDay: Sound = ... :: Sound
local ambientNight: Sound = ... :: Sound

local currentPhase: Phase? = nil

local function tweenVolume(s: Sound, toVol: number, timeSec: number): Tween
	local tinfo = TweenInfo.new(timeSec, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	local tween = TweenService:Create(s, tinfo, { Volume = toVol })
	tween:Play()
	return tween
end

local function fadeOutAndMaybeStop(s: Sound, timeSec: number)
	-- Fade to 0 and stop after fade (only if it’s still playing)
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
	else
		-- If already playing, still ensure we fade from current value smoothly
		-- (don’t force Volume = 0 here)
	end
	tweenVolume(s, targetVol, timeSec)
end

local function setPhase(phase: Phase)
	if currentPhase == phase then
		return
	end
	currentPhase = phase

	if phase == "Day" then
		-- Crossfade: Night -> Day
		if ambientNight.IsPlaying then
			fadeOutAndMaybeStop(ambientNight, FADE_TIME)
		else
			-- ensure it isn't audible if it got left nonzero
			ambientNight.Volume = 0
		end
		startAtZeroAndFadeIn(ambientDay, DAY_VOL, FADE_TIME)

	elseif phase == "Night" then
		-- Crossfade: Day -> Night
		if ambientDay.IsPlaying then
			fadeOutAndMaybeStop(ambientDay, FADE_TIME)
		else
			ambientDay.Volume = 0
		end
		startAtZeroAndFadeIn(ambientNight, NIGHT_VOL, FADE_TIME)
	end
end

phaseChanged.OnClientEvent:Connect(function(phaseAny: any)
	-- Strict-safe narrowing from `any` to our literal union type
	if phaseAny == "Day" then
		setPhase("Day")
	elseif phaseAny == "Night" then
		setPhase("Night")
	else
		warn("[AmbientAudio] PhaseChanged got invalid value:", tostring(phaseAny))
	end
end)

dayStarted.OnClientEvent:Connect(function(dayNumber: any)
	onDayStarted(dayNumber :: number)
end)