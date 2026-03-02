--!strict
-- src/server/TimeDayCycle.server.luau
-- Server-authoritative day counter + lighting day/night cycle + phase events + audio publishing
-- Robust state replication so clients ALWAYS show Day 1 even if they join late / UI loads late.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")
local ServerStorage = game:GetService("ServerStorage")

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

-- ========================
-- Shared folder + Remotes
-- ========================
local sharedFolder = ReplicatedStorage:FindFirstChild("Shared")
if not sharedFolder then
	local f = Instance.new("Folder")
	f.Name = "Shared"
	f.Parent = ReplicatedStorage
	sharedFolder = f
end
sharedFolder = sharedFolder :: Folder

local function getOrCreateRemote(name: string): RemoteEvent
	local found = sharedFolder:FindFirstChild(name)
	if found and found:IsA("RemoteEvent") then
		return found
	end
	local ev = Instance.new("RemoteEvent")
	ev.Name = name
	ev.Parent = sharedFolder
	return ev
end

local dayStartedEvent = getOrCreateRemote("DayStarted")
local phaseChangedEvent = getOrCreateRemote("PhaseChanged")

local function getOrCreateFolder(parent: Instance, name: string): Folder
	local f = parent:FindFirstChild(name)
	if f and f:IsA("Folder") then
		return f
	end
	local nf = Instance.new("Folder")
	nf.Name = name
	nf.Parent = parent
	return nf
end

-- ========================
-- Replicated state (IMPORTANT)
-- ========================
local stateFolder = getOrCreateFolder(sharedFolder, "State")

local function getOrCreateIntValue(parent: Instance, name: string, defaultValue: number): IntValue
	local v = parent:FindFirstChild(name)
	if v and v:IsA("IntValue") then
		return v
	end
	local nv = Instance.new("IntValue")
	nv.Name = name
	nv.Value = defaultValue
	nv.Parent = parent
	return nv
end

local function getOrCreateStringValue(parent: Instance, name: string, defaultValue: string): StringValue
	local v = parent:FindFirstChild(name)
	if v and v:IsA("StringValue") then
		return v
	end
	local nv = Instance.new("StringValue")
	nv.Name = name
	nv.Value = defaultValue
	nv.Parent = parent
	return nv
end

-- Day/phase state that clients can read immediately on startup
local currentDayValue = getOrCreateIntValue(stateFolder, "CurrentDay", 1)
local currentPhaseValue = getOrCreateStringValue(stateFolder, "CurrentPhase", "Day")

-- ========================
-- Publish audio assets to clients
-- ========================
local audioFolder = getOrCreateFolder(sharedFolder, "Audio")

-- These must exist in ServerStorage exactly as named in your screenshot
local SOUND_NAMES: {string} = {
	"Ambient_Forest_Sound_Day",
	"Ambient_Forest_Sound_Night",
	"Morning_Birds",
	"Rooster",
}

local function publishSounds()
	for _, soundName in ipairs(SOUND_NAMES) do
		local existing = audioFolder:FindFirstChild(soundName)
		if existing and existing:IsA("Sound") then
			continue
		end

		local src = ServerStorage:FindFirstChild(soundName)
		if not (src and src:IsA("Sound")) then
			warn("[TimeDayCycle] Missing Sound in ServerStorage:", soundName)
			continue
		end

		local clone = src:Clone()
		clone.Parent = audioFolder
	end
end

publishSounds()

-- ========================
-- Day state
-- ========================
local currentDay = 1
local currentPhase: "Day" | "Night" = "Day"

local function publishState()
	-- Replicated values (clients can read these even if they missed the RemoteEvent)
	currentDayValue.Value = currentDay
	currentPhaseValue.Value = currentPhase
end

local function fireStateToAll()
	dayStartedEvent:FireAllClients(currentDay)
	phaseChangedEvent:FireAllClients(currentPhase)
end

local function fireStateToPlayer(player: Player)
	dayStartedEvent:FireClient(player, currentDay)
	phaseChangedEvent:FireClient(player, currentPhase)
end

local function setPhaseState(newPhase: "Day" | "Night")
	if currentPhase == newPhase then
		return
	end
	currentPhase = newPhase
	publishState()
	phaseChangedEvent:FireAllClients(newPhase)
end

-- ========================
-- Lighting helpers
-- ========================
local function tweenLighting(props: {[string]: any}, duration: number)
	local info = TweenInfo.new(duration, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	local tween = TweenService:Create(Lighting, info, props)
	tween:Play()
	return tween
end

local function setLighting(clockTime: number, duration: number, isNight: boolean)
	local props: {[string]: any} = {
		ClockTime = clockTime,
		Brightness = isNight and NIGHT_BRIGHTNESS or DAY_BRIGHTNESS,
		Ambient = isNight and NIGHT_AMBIENT or DAY_AMBIENT,
		OutdoorAmbient = isNight and NIGHT_AMBIENT or DAY_AMBIENT,
	}
	tweenLighting(props, duration)
end

-- ========================
-- Main cycle
-- ========================
local function runLightingCycle()
	local dayPart = DAY_LENGTH_SECONDS * 0.6
	local nightPart = DAY_LENGTH_SECONDS * 0.4

	-- Initial day lighting
	Lighting.ClockTime = DAY_START_CLOCK
	Lighting.Brightness = DAY_BRIGHTNESS
	Lighting.Ambient = DAY_AMBIENT
	Lighting.OutdoorAmbient = DAY_AMBIENT

	currentDay = 1
	currentPhase = "Day"
	publishState()

	while true do
		-- DAY -> NIGHT
		setPhaseState("Day")
		setLighting(NIGHT_START_CLOCK, dayPart, false)
		task.wait(dayPart)

		-- NIGHT begins
		setPhaseState("Night")

		-- NIGHT -> DAWN (wrap workaround)
		local toMidnight = nightPart * 0.5
		local toDawn = nightPart * 0.5

		setLighting(24, toMidnight, true)
		task.wait(toMidnight)

		Lighting.ClockTime = 0
		setLighting(NIGHT_END_CLOCK, toDawn, true)
		task.wait(toDawn)

		-- New day
		currentDay += 1
		publishState()
		dayStartedEvent:FireAllClients(currentDay)

		-- Morning snap/tween + phase swap
		setPhaseState("Day")
		setLighting(DAY_START_CLOCK, 0.35, false)
		task.wait(0.35)
	end
end

-- ========================
-- Boot: publish Day 1 reliably
-- ========================
task.defer(function()
	publishState()
	fireStateToAll()

	-- Safety re-broadcast shortly after server start (covers “UI not connected yet” cases)
	task.delay(1.5, function()
		fireStateToAll()
	end)
end)

task.spawn(runLightingCycle)

Players.PlayerAdded:Connect(function(player)
	-- Send immediately…
	task.defer(function()
		fireStateToPlayer(player)
	end)

	-- …and again shortly after, to catch late-loading UI LocalScripts.
	task.delay(1.0, function()
		if player.Parent then
			fireStateToPlayer(player)
		end
	end)
end)