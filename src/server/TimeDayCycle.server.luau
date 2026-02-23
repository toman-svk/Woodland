--!strict
-- src/server/TimeDayCycle.server.luau
-- Server-authoritative day counter + lighting day/night cycle

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")

-- CONFIG
local DAY_LENGTH_SECONDS = 120 -- testing

-- Lighting times (Roblox "ClockTime" is 0..24)
local DAY_START_CLOCK = 8      -- morning
local NIGHT_START_CLOCK = 19   -- evening
local NIGHT_END_CLOCK = 6      -- dawn (next day)

-- Optional: tweak look
local DAY_BRIGHTNESS = 2
local NIGHT_BRIGHTNESS = 0.7

local DAY_AMBIENT = Color3.fromRGB(128, 128, 128)
local NIGHT_AMBIENT = Color3.fromRGB(40, 40, 60)

--========================
-- Shared folder + RemoteEvent (strict-safe)
--========================
local sharedFolder = ReplicatedStorage:FindFirstChild("Shared")
if not sharedFolder then
	sharedFolder = Instance.new("Folder")
	sharedFolder.Name = "Shared"
	sharedFolder.Parent = ReplicatedStorage
end

local found = sharedFolder:FindFirstChild("DayStarted")
local dayStartedEvent: RemoteEvent
if found and found:IsA("RemoteEvent") then
	dayStartedEvent = found
else
	local ev = Instance.new("RemoteEvent")
	ev.Name = "DayStarted"
	ev.Parent = sharedFolder
	dayStartedEvent = ev
end

-- Day value
local currentDay = 1

--========================
-- Lighting helpers
--========================
local function tweenLighting(props: {[string]: any}, duration: number)
	local info = TweenInfo.new(duration, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	local tween = TweenService:Create(Lighting, info, props)
	tween:Play()
	return tween
end

local function setPhase(clockTime: number, duration: number, isNight: boolean)
	local props: {[string]: any} = {
		ClockTime = clockTime,
		Brightness = isNight and NIGHT_BRIGHTNESS or DAY_BRIGHTNESS,
		Ambient = isNight and NIGHT_AMBIENT or DAY_AMBIENT,
		OutdoorAmbient = isNight and NIGHT_AMBIENT or DAY_AMBIENT,
	}
	tweenLighting(props, duration)
end

--========================
-- Main cycle
--========================
local function runLightingCycle()
	local dayPart = DAY_LENGTH_SECONDS * 0.6
	local nightPart = DAY_LENGTH_SECONDS * 0.4

	-- Set initial day lighting
	Lighting.ClockTime = DAY_START_CLOCK
	Lighting.Brightness = DAY_BRIGHTNESS
	Lighting.Ambient = DAY_AMBIENT
	Lighting.OutdoorAmbient = DAY_AMBIENT

	while true do
		-- DAY -> NIGHT
		setPhase(NIGHT_START_CLOCK, dayPart, false)
		task.wait(dayPart)

		-- NIGHT -> DAWN (needs wrap workaround)
		local toMidnight = nightPart * 0.5
		local toDawn = nightPart * 0.5

		setPhase(24, toMidnight, true)
		task.wait(toMidnight)

		-- wrap
		Lighting.ClockTime = 0
		setPhase(NIGHT_END_CLOCK, toDawn, true)
		task.wait(toDawn)

		-- New day
		currentDay += 1
		dayStartedEvent:FireAllClients(currentDay)

		-- Morning snap/tween
		setPhase(DAY_START_CLOCK, 0.35, false)
		task.wait(0.35)
	end
end

-- Fire Day 1 once on server start (UI shows immediately)
task.defer(function()
	dayStartedEvent:FireAllClients(currentDay)
end)

task.spawn(runLightingCycle)

Players.PlayerAdded:Connect(function(player)
	-- make sure late joiners get current day instantly
	task.defer(function()
		dayStartedEvent:FireClient(player, currentDay)
	end)
end)