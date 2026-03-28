--!strict
-- src/server/Gameplay/Systems/Time/TimeDayCycleService.luau

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")
local ServerStorage = game:GetService("ServerStorage")
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

type TimePhase = "Day" | "Night"

type TimeState = {
	currentDay: number,
	currentPhase: TimePhase,
}

type BaseStructureState = {
	level: number,
	isUpgrading: boolean,
	targetLevel: number?,
	upgradeEndsAt: number?,
}

type StructuresState = {
	base: BaseStructureState,
}

type WorldDiffs = {
	choppedTrees: {[string]: boolean},
	minedGems: {[string]: boolean},
}

type ItemMap = {[string]: number}
type InventoriesMap = {[string]: ItemMap}

type WorldSave = {
	version: number,
	seed: number?,
	diffs: WorldDiffs,
	inventories: InventoriesMap,
	structures: StructuresState,
	time: TimeState,
	lastSavedAt: number,
}

type WorldServiceType = {
	GetSave: (() -> WorldSave?)?,
	SetTimeState: ((currentDay: number, currentPhase: TimePhase) -> ())?,
}

local WorldServiceRaw = require(
	ServerScriptService
		:WaitForChild("Server")
		:WaitForChild("Gameplay")
		:WaitForChild("World")
		:WaitForChild("Runtime")
		:WaitForChild("WorldService")
)

local WorldService: WorldServiceType = WorldServiceRaw :: WorldServiceType

local TimeDayCycleService = {}

local DAY_LENGTH_SECONDS = 180

local DAY_START_CLOCK = 6.5
local NIGHT_START_CLOCK = 18.5
local NIGHT_END_CLOCK = 5.5

local DAY_BRIGHTNESS = 2.2
local NIGHT_BRIGHTNESS = 0.7

local DAY_AMBIENT = Color3.fromRGB(140, 140, 140)
local NIGHT_AMBIENT = Color3.fromRGB(50, 60, 90)

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

local function getOrCreateRemote(parent: Instance, name: string): RemoteEvent
	local found = parent:FindFirstChild(name)
	if found and found:IsA("RemoteEvent") then
		return found
	end

	local ev = Instance.new("RemoteEvent")
	ev.Name = name
	ev.Parent = parent
	return ev
end

local sharedFolder = getOrCreateFolder(ReplicatedStorage, "Shared")
local remotesFolder = getOrCreateFolder(sharedFolder, "Remotes")
local stateFolder = getOrCreateFolder(sharedFolder, "State")
local audioFolder = getOrCreateFolder(sharedFolder, "Audio")

local dayStartedEvent = getOrCreateRemote(remotesFolder, "DayStarted")
local phaseChangedEvent = getOrCreateRemote(remotesFolder, "PhaseChanged")

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

local currentDayValue = getOrCreateIntValue(stateFolder, "CurrentDay", 1)
local currentPhaseValue = getOrCreateStringValue(stateFolder, "CurrentPhase", "Day")

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
		clone.Name = soundName
		clone.Parent = audioFolder
	end
end

publishSounds()

local currentDay = 1
local currentPhase: TimePhase = "Day"

local function setTimeStateSafe(day: number, phase: TimePhase)
	local fn = WorldService.SetTimeState
	if fn == nil then
		return
	end
	fn(day, phase)
end

local function getSaveSafe(): WorldSave?
	local fn = WorldService.GetSave
	if fn == nil then
		return nil
	end
	return fn()
end

local function publishState()
	currentDayValue.Value = currentDay
	currentPhaseValue.Value = currentPhase
	setTimeStateSafe(currentDay, currentPhase)
end

local function fireStateToAll()
	dayStartedEvent:FireAllClients(currentDay)
	phaseChangedEvent:FireAllClients(currentPhase)
end

local function fireStateToPlayer(player: Player)
	dayStartedEvent:FireClient(player, currentDay)
	phaseChangedEvent:FireClient(player, currentPhase)
end

local function setPhaseState(newPhase: TimePhase)
	if currentPhase == newPhase then
		return
	end

	currentPhase = newPhase
	publishState()
	phaseChangedEvent:FireAllClients(newPhase)
end

local function tweenLighting(props: {[string]: any}, duration: number)
	local info = TweenInfo.new(duration, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	local tween = TweenService:Create(Lighting, info, props)
	tween:Play()
	return tween
end

local function setLighting(clockTime: number, duration: number, isNight: boolean)
	local props: {[string]: any} = {
		ClockTime = clockTime,
		Brightness = if isNight then NIGHT_BRIGHTNESS else DAY_BRIGHTNESS,
		Ambient = if isNight then NIGHT_AMBIENT else DAY_AMBIENT,
		OutdoorAmbient = if isNight then NIGHT_AMBIENT else DAY_AMBIENT,
	}
	tweenLighting(props, duration)
end

local function applyStaticLightingForCurrentPhase()
	if currentPhase == "Night" then
		Lighting.ClockTime = NIGHT_START_CLOCK
		Lighting.Brightness = NIGHT_BRIGHTNESS
		Lighting.Ambient = NIGHT_AMBIENT
		Lighting.OutdoorAmbient = NIGHT_AMBIENT
	else
		Lighting.ClockTime = DAY_START_CLOCK
		Lighting.Brightness = DAY_BRIGHTNESS
		Lighting.Ambient = DAY_AMBIENT
		Lighting.OutdoorAmbient = DAY_AMBIENT
	end
end

local function initializeFromSave()
	local save = getSaveSafe()
	if save then
		currentDay = math.max(1, math.floor(save.time.currentDay))
		if save.time.currentPhase == "Night" then
			currentPhase = "Night"
		else
			currentPhase = "Day"
		end
	else
		currentDay = 1
		currentPhase = "Day"
	end

	applyStaticLightingForCurrentPhase()
	publishState()
end

local function runLightingCycle()
	local dayPart = DAY_LENGTH_SECONDS * 0.6
	local nightPart = DAY_LENGTH_SECONDS * 0.4

	initializeFromSave()

	while true do
		if currentPhase == "Day" then
			setPhaseState("Day")
			setLighting(NIGHT_START_CLOCK, dayPart, false)
			task.wait(dayPart)

			setPhaseState("Night")
			publishState()
		else
			setPhaseState("Night")
		end

		local toMidnight = nightPart * 0.5
		local toDawn = nightPart * 0.5

		setLighting(24, toMidnight, true)
		task.wait(toMidnight)

		Lighting.ClockTime = 0
		Lighting.Brightness = NIGHT_BRIGHTNESS
		Lighting.Ambient = NIGHT_AMBIENT
		Lighting.OutdoorAmbient = NIGHT_AMBIENT

		setLighting(NIGHT_END_CLOCK, toDawn, true)
		task.wait(toDawn)

		currentDay += 1
		currentPhase = "Day"
		publishState()
		dayStartedEvent:FireAllClients(currentDay)

		setPhaseState("Day")
		setLighting(DAY_START_CLOCK, 0.35, false)
		task.wait(0.35)
	end
end

task.defer(function()
	initializeFromSave()
	fireStateToAll()

	task.delay(1.5, function()
		fireStateToAll()
	end)
end)

task.spawn(runLightingCycle)

Players.PlayerAdded:Connect(function(player)
	task.defer(function()
		fireStateToPlayer(player)
	end)

	task.delay(1.0, function()
		if player.Parent then
			fireStateToPlayer(player)
		end
	end)
end)

return TimeDayCycleService