--!strict

local ServerStorage = game:GetService("ServerStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")

local gameplayRoot = ServerScriptService:WaitForChild("Server"):WaitForChild("Gameplay")
local worldFolder = gameplayRoot:WaitForChild("World")
local configFolder = worldFolder:WaitForChild("Config")
local configLocatorModule = configFolder:WaitForChild("ConfigLocator")

if not configLocatorModule:IsA("ModuleScript") then
	error("[BaseUpgradeService] ConfigLocator is not a ModuleScript")
end

local ConfigLocator = require(configLocatorModule)
local WorldConfig = ConfigLocator.WorldConfig

local WorldService = require(
	ServerScriptService
		:WaitForChild("Server")
		:WaitForChild("Gameplay")
		:WaitForChild("World")
		:WaitForChild("Runtime")
		:WaitForChild("WorldService")
)

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
	lastSavedAt: number,
}

type WorldServiceLike = {
	GetWorldId: (() -> string?)?,
	GetSave: (() -> WorldSave?)?,
	SetBaseLevel: ((level: number) -> ())?,
	MarkDirty: (() -> ())?,
}

local worldService: WorldServiceLike = WorldService :: WorldServiceLike

local BaseUpgradeService = {}

-- HOUSE
local HOUSE2_Y_OFFSET = 5
local HOUSE_RISE_DISTANCE = 8
local HOUSE_RISE_DURATION = 0.35
local HOUSE_RISE_STEPS = 6
local HOUSE_ROTATION_Y_DEGREES = 180

-- TIMED UPGRADE
local BASE_UPGRADE_DURATION_SECONDS = 60

-- SOUND
local BUILD_SOUND_ID = "rbxassetid://0"
local BUILD_SOUND_VOLUME = 0.9

-- FENCE
local FENCE_HALF_SIZE = 60
local FENCE_HEIGHT = 10
local FENCE_THICKNESS = 1.25
local FENCE_SINK_DEPTH = 4
local FENCE_COLOR = Color3.fromRGB(92, 62, 36)

local FENCE_CORNER_LOG_RADIUS = 2
local FENCE_CORNER_LOG_HEIGHT = 20
local FENCE_CORNER_LOG_COLOR = Color3.fromRGB(70, 46, 28)

local GATE_WIDTH = 8
local GATE_SIDE = "South" -- "South", "North", "West", "East"

-- GATE GLOW
local GATE_BARRIER_HEIGHT = 10
local GATE_BARRIER_THICKNESS = 1.5
local GATE_GLOW_COLOR = Color3.fromRGB(255, 210, 90)
local GATE_GLOW_BRIGHTNESS = 3
local GATE_GLOW_RANGE = 20

-- Fence offset
local FENCE_OFFSET = Vector3.new(0, 0, 15)
-- positive Z = south
-- negative Z = north
-- positive X = east
-- negative X = west

local scheduledUpgradeToken = 0

local function getWorldIdSafe(): string?
	local fn = worldService.GetWorldId
	if fn == nil then
		return nil
	end
	return fn()
end

local function getSaveSafe(): WorldSave?
	local fn = worldService.GetSave
	if fn == nil then
		return nil
	end
	return fn()
end

local function setBaseLevelSafe(level: number)
	local fn = worldService.SetBaseLevel
	if fn == nil then
		return
	end
	fn(level)
end

local function markDirtySafe()
	local fn = worldService.MarkDirty
	if fn == nil then
		return
	end
	fn()
end

local function ensureBaseState(save: WorldSave): BaseStructureState
	local base = save.structures.base

	if base.isUpgrading == nil then
		base.isUpgrading = false
	end

	return base
end

local function getGeneratedFolder(): Folder?
	local worldId = getWorldIdSafe()
	if not worldId then
		return nil
	end

	local worlds = Workspace:FindFirstChild("Worlds")
	if not (worlds and worlds:IsA("Folder")) then
		return nil
	end

	local root = worlds:FindFirstChild(worldId)
	if not (root and root:IsA("Folder")) then
		return nil
	end

	local generated = root:FindFirstChild("Generated")
	if generated and generated:IsA("Folder") then
		return generated
	end

	return nil
end

local function getOrCreateBaseRuntimeFolder(generated: Folder): Folder
	local existing = generated:FindFirstChild("BaseRuntime")
	if existing and existing:IsA("Folder") then
		return existing
	end

	local folder = Instance.new("Folder")
	folder.Name = "BaseRuntime"
	folder.Parent = generated
	return folder
end

local function findSpawnHub(generated: Folder): Model?
	for _, inst in ipairs(generated:GetDescendants()) do
		if inst:IsA("Model") and inst.Name == "SpawnHub" then
			return inst
		end
	end
	return nil
end

local function getHouseUpgradeTemplate(): Model?
	local templates = ServerStorage:FindFirstChild("Templates")
	if not (templates and templates:IsA("Folder")) then
		return nil
	end

	local structures = templates:FindFirstChild("Structures")
	if not (structures and structures:IsA("Folder")) then
		return nil
	end

	local houseTemplate = structures:FindFirstChild("House1")
	if houseTemplate and houseTemplate:IsA("Model") then
		return houseTemplate
	end

	return nil
end

local function findAnyBasePart(root: Instance): BasePart?
	if root:IsA("BasePart") then
		return root
	end

	for _, inst in ipairs(root:GetDescendants()) do
		if inst:IsA("BasePart") then
			return inst
		end
	end

	return nil
end

local function disableBasePrompt(generated: Folder)
	for _, inst in ipairs(generated:GetDescendants()) do
		if inst:IsA("ProximityPrompt") then
			local npcId = inst:GetAttribute("NpcId")
			local dialogueId = inst:GetAttribute("DialogueId")

			if npcId == "Base" and dialogueId == "Base_Upgrade_Lv1" then
				inst.Enabled = false
			end
		end
	end
end

local function playBuildSound(parentInst: Instance)
	if BUILD_SOUND_ID == "rbxassetid://0" then
		return
	end

	local host = findAnyBasePart(parentInst)
	if host == nil then
		return
	end

	local sound = Instance.new("Sound")
	sound.Name = "BaseUpgradeBuildSound"
	sound.SoundId = BUILD_SOUND_ID
	sound.Volume = BUILD_SOUND_VOLUME
	sound.RollOffMaxDistance = 90
	sound.RollOffMinDistance = 8
	sound.Parent = host
	sound:Play()

	Debris:AddItem(sound, 5)
end

local function easeOutQuad(t: number): number
	return 1 - (1 - t) * (1 - t)
end

local function animateHouseRise(house: Model, targetPivot: CFrame)
	local stepDelay = HOUSE_RISE_DURATION / HOUSE_RISE_STEPS

	for i = 1, HOUSE_RISE_STEPS do
		local alpha = i / HOUSE_RISE_STEPS
		local eased = easeOutQuad(alpha)
		local yOffset = -HOUSE_RISE_DISTANCE * (1 - eased)
		house:PivotTo(targetPivot * CFrame.new(0, yOffset, 0))
		task.wait(stepDelay)
	end

	house:PivotTo(targetPivot)
end

local function raycastGroundY(x: number, z: number): number?
	local origin = Vector3.new(x, WorldConfig.BASE_Y + 300, z)
	local direction = Vector3.new(0, -1000, 0)

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude

	local generated = getGeneratedFolder()
	if generated then
		local runtime = generated:FindFirstChild("BaseRuntime")
		if runtime then
			params.FilterDescendantsInstances = {runtime}
		end
	end

	local result = Workspace:Raycast(origin, direction, params)
	if result then
		return result.Position.Y
	end

	return nil
end

local function createFencePart(
	parent: Instance,
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material?
): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = true
	part.CanQuery = true
	part.CanTouch = false
	part.Material = material or Enum.Material.WoodPlanks
	part.Color = color
	part.Size = size
	part.CFrame = cframe
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

local function createGroundedWall(
	parent: Instance,
	name: string,
	size: Vector3,
	x: number,
	z: number,
	color: Color3
): Part
	local groundY = raycastGroundY(x, z) or (WorldConfig.BASE_Y + 1)
	local bottomY = groundY - FENCE_SINK_DEPTH
	local centerY = bottomY + (size.Y / 2)

	return createFencePart(
		parent,
		name,
		size,
		CFrame.new(x, centerY, z),
		color,
		Enum.Material.WoodPlanks
	)
end

local function createGroundedCornerLog(
	parent: Instance,
	name: string,
	x: number,
	z: number
): Part
	local groundY = raycastGroundY(x, z) or (WorldConfig.BASE_Y + 1)
	local bottomY = groundY - FENCE_SINK_DEPTH
	local centerY = bottomY + (FENCE_CORNER_LOG_HEIGHT / 2)

	local part = Instance.new("Part")
	part.Name = name
	part.Shape = Enum.PartType.Cylinder
	part.Anchored = true
	part.CanCollide = true
	part.CanQuery = true
	part.CanTouch = false
	part.Material = Enum.Material.Wood
	part.Color = FENCE_CORNER_LOG_COLOR
	part.Size = Vector3.new(FENCE_CORNER_LOG_HEIGHT, FENCE_CORNER_LOG_RADIUS * 2, FENCE_CORNER_LOG_RADIUS * 2)
	part.CFrame = CFrame.new(x, centerY, z) * CFrame.Angles(0, 0, math.rad(90))
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

local function createFenceCornerLogs(parent: Instance, center: Vector3, halfSize: number)
	createGroundedCornerLog(parent, "FenceLog_NW", center.X - halfSize, center.Z - halfSize)
	createGroundedCornerLog(parent, "FenceLog_NE", center.X + halfSize, center.Z - halfSize)
	createGroundedCornerLog(parent, "FenceLog_SW", center.X - halfSize, center.Z + halfSize)
	createGroundedCornerLog(parent, "FenceLog_SE", center.X + halfSize, center.Z + halfSize)
end

local function createGateGlowBarrier(
	parent: Instance,
	center: Vector3,
	isHorizontal: boolean
)
	local groundY = raycastGroundY(center.X, center.Z) or (WorldConfig.BASE_Y + 1)
	local bottomY = groundY - 1
	local centerY = bottomY + (GATE_BARRIER_HEIGHT / 2)

	local size: Vector3
	if isHorizontal then
		size = Vector3.new(GATE_WIDTH, GATE_BARRIER_HEIGHT, GATE_BARRIER_THICKNESS)
	else
		size = Vector3.new(GATE_BARRIER_THICKNESS, GATE_BARRIER_HEIGHT, GATE_WIDTH)
	end

	local barrier = Instance.new("Part")
	barrier.Name = "GateGlowBarrier"
	barrier.Anchored = true
	barrier.CanCollide = false
	barrier.CanQuery = true
	barrier.CanTouch = false
	barrier.Material = Enum.Material.Neon
	barrier.Color = GATE_GLOW_COLOR
	barrier.Transparency = 0.35
	barrier.Size = size
	barrier.CFrame = CFrame.new(center.X, centerY, center.Z)
	barrier.Parent = parent

	local light = Instance.new("PointLight")
	light.Color = GATE_GLOW_COLOR
	light.Brightness = GATE_GLOW_BRIGHTNESS
	light.Range = GATE_GLOW_RANGE
	light.Parent = barrier

	local fire = Instance.new("Fire")
	fire.Name = "GateFire"
	fire.Color = Color3.fromRGB(255, 200, 80)
	fire.SecondaryColor = Color3.fromRGB(255, 120, 40)
	fire.Heat = 6
	fire.Size = 8
	fire.Parent = barrier
end

local function buildFence(generated: Folder, center: Vector3)
	local runtime = getOrCreateBaseRuntimeFolder(generated)

	local existing = runtime:FindFirstChild("BaseFence")
	if existing then
		existing:Destroy()
	end

	local fenceFolder = Instance.new("Folder")
	fenceFolder.Name = "BaseFence"
	fenceFolder.Parent = runtime

	local halfSize = FENCE_HALF_SIZE
	local fullLength = halfSize * 2
	local gateHalf = GATE_WIDTH / 2

	-- North
	if GATE_SIDE ~= "North" then
		createGroundedWall(
			fenceFolder,
			"FenceNorth",
			Vector3.new(fullLength, FENCE_HEIGHT, FENCE_THICKNESS),
			center.X,
			center.Z - halfSize,
			FENCE_COLOR
		)
	else
		local sideLen = halfSize - gateHalf

		createGroundedWall(
			fenceFolder,
			"FenceNorth_Left",
			Vector3.new(sideLen, FENCE_HEIGHT, FENCE_THICKNESS),
			center.X - ((halfSize + gateHalf) / 2),
			center.Z - halfSize,
			FENCE_COLOR
		)

		createGroundedWall(
			fenceFolder,
			"FenceNorth_Right",
			Vector3.new(sideLen, FENCE_HEIGHT, FENCE_THICKNESS),
			center.X + ((halfSize + gateHalf) / 2),
			center.Z - halfSize,
			FENCE_COLOR
		)

		createGateGlowBarrier(fenceFolder, Vector3.new(center.X, center.Y, center.Z - halfSize), true)
	end

	-- South
	if GATE_SIDE ~= "South" then
		createGroundedWall(
			fenceFolder,
			"FenceSouth",
			Vector3.new(fullLength, FENCE_HEIGHT, FENCE_THICKNESS),
			center.X,
			center.Z + halfSize,
			FENCE_COLOR
		)
	else
		local sideLen = halfSize - gateHalf

		createGroundedWall(
			fenceFolder,
			"FenceSouth_Left",
			Vector3.new(sideLen, FENCE_HEIGHT, FENCE_THICKNESS),
			center.X - ((halfSize + gateHalf) / 2),
			center.Z + halfSize,
			FENCE_COLOR
		)

		createGroundedWall(
			fenceFolder,
			"FenceSouth_Right",
			Vector3.new(sideLen, FENCE_HEIGHT, FENCE_THICKNESS),
			center.X + ((halfSize + gateHalf) / 2),
			center.Z + halfSize,
			FENCE_COLOR
		)

		createGateGlowBarrier(fenceFolder, Vector3.new(center.X, center.Y, center.Z + halfSize), true)
	end

	-- West
	if GATE_SIDE ~= "West" then
		createGroundedWall(
			fenceFolder,
			"FenceWest",
			Vector3.new(FENCE_THICKNESS, FENCE_HEIGHT, fullLength),
			center.X - halfSize,
			center.Z,
			FENCE_COLOR
		)
	else
		local sideLen = halfSize - gateHalf

		createGroundedWall(
			fenceFolder,
			"FenceWest_Top",
			Vector3.new(FENCE_THICKNESS, FENCE_HEIGHT, sideLen),
			center.X - halfSize,
			center.Z - ((halfSize + gateHalf) / 2),
			FENCE_COLOR
		)

		createGroundedWall(
			fenceFolder,
			"FenceWest_Bottom",
			Vector3.new(FENCE_THICKNESS, FENCE_HEIGHT, sideLen),
			center.X - halfSize,
			center.Z + ((halfSize + gateHalf) / 2),
			FENCE_COLOR
		)

		createGateGlowBarrier(fenceFolder, Vector3.new(center.X - halfSize, center.Y, center.Z), false)
	end

	-- East
	if GATE_SIDE ~= "East" then
		createGroundedWall(
			fenceFolder,
			"FenceEast",
			Vector3.new(FENCE_THICKNESS, FENCE_HEIGHT, fullLength),
			center.X + halfSize,
			center.Z,
			FENCE_COLOR
		)
	else
		local sideLen = halfSize - gateHalf

		createGroundedWall(
			fenceFolder,
			"FenceEast_Top",
			Vector3.new(FENCE_THICKNESS, FENCE_HEIGHT, sideLen),
			center.X + halfSize,
			center.Z - ((halfSize + gateHalf) / 2),
			FENCE_COLOR
		)

		createGroundedWall(
			fenceFolder,
			"FenceEast_Bottom",
			Vector3.new(FENCE_THICKNESS, FENCE_HEIGHT, sideLen),
			center.X + halfSize,
			center.Z + ((halfSize + gateHalf) / 2),
			FENCE_COLOR
		)

		createGateGlowBarrier(fenceFolder, Vector3.new(center.X + halfSize, center.Y, center.Z), false)
	end

	createFenceCornerLogs(fenceFolder, center, halfSize)
end

function BaseUpgradeService.GetLevel(): number
	local save = getSaveSafe()
	if not save then
		return 1
	end

	local base = ensureBaseState(save)
	return math.max(1, math.floor(base.level))
end

function BaseUpgradeService.IsUpgradeInProgress(): boolean
	local save = getSaveSafe()
	if not save then
		return false
	end

	local base = ensureBaseState(save)
	return base.isUpgrading == true
end

function BaseUpgradeService.GetUpgradeEndTime(): number?
	local save = getSaveSafe()
	if not save then
		return nil
	end

	local base = ensureBaseState(save)
	return base.upgradeEndsAt
end

local function setUpgradeAttributes(spawnHub: Model, isActive: boolean, endTime: number?, duration: number?, targetLevel: number?)
	spawnHub:SetAttribute("BaseUpgradeActive", isActive)
	spawnHub:SetAttribute("BaseUpgradeEndTime", endTime)
	spawnHub:SetAttribute("BaseUpgradeDuration", duration)
	spawnHub:SetAttribute("BaseUpgradeTargetLevel", targetLevel)
end

local function darkenHouse(house: Model)
	if house:GetAttribute("ConstructionDarkened") == true then
		return
	end

	house:SetAttribute("ConstructionDarkened", true)

	for _, inst in ipairs(house:GetDescendants()) do
		if inst:IsA("BasePart") then
			inst.Color = inst.Color:Lerp(Color3.fromRGB(45, 45, 45), 0.55)
			inst.Material = Enum.Material.Slate
		end
	end
end

local function clearCelebration(folder: Folder)
	local existing = folder:FindFirstChild("BaseCelebration")
	if existing then
		existing:Destroy()
	end
end

local function spawnCelebrationEffect(parent: Instance)
	local part = findAnyBasePart(parent)
	if not part then
		return
	end

	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "BaseCelebration"
	emitter.Texture = "rbxassetid://243660364"
	emitter.Lifetime = NumberRange.new(1.2, 1.8)
	emitter.Speed = NumberRange.new(8, 14)
	emitter.Rate = 0
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = NumberRange.new(-120, 120)
	emitter.SpreadAngle = Vector2.new(50, 50)
	emitter.Parent = part

	emitter:Emit(40)
	Debris:AddItem(emitter, 3)
end

local function replaceHouseWithLevel2(animate: boolean): boolean
	local generated = getGeneratedFolder()
	if not generated then
		warn("[BaseUpgradeService] Missing Generated folder.")
		return false
	end

	local spawnHub = findSpawnHub(generated)
	if not spawnHub then
		warn("[BaseUpgradeService] SpawnHub not found.")
		return false
	end

	local oldHouse = spawnHub:FindFirstChild("House")
	if not (oldHouse and oldHouse:IsA("Model")) then
		warn("[BaseUpgradeService] House not found under SpawnHub.")
		return false
	end

	local template = getHouseUpgradeTemplate()
	if not template then
		warn("[BaseUpgradeService] Templates/Structures/House1 not found.")
		return false
	end

	local oldPivot = oldHouse:GetPivot()
	local targetPivot = oldPivot
		* CFrame.new(0, HOUSE2_Y_OFFSET, 0)
		* CFrame.Angles(0, math.rad(HOUSE_ROTATION_Y_DEGREES), 0)

	oldHouse:Destroy()

	local newHouse = template:Clone()
	newHouse.Name = "House"
	newHouse.Parent = spawnHub

	if animate then
		newHouse:PivotTo(targetPivot * CFrame.new(0, -HOUSE_RISE_DISTANCE, 0))
	else
		newHouse:PivotTo(targetPivot)
	end

	local fenceCenter = spawnHub:GetPivot().Position + FENCE_OFFSET
	buildFence(generated, fenceCenter)
	disableBasePrompt(generated)

	if animate then
		playBuildSound(newHouse)
		animateHouseRise(newHouse, targetPivot)
	end

	clearCelebration(generated)
	spawnCelebrationEffect(newHouse)

	return true
end

local function scheduleCompletion(endTime: number)
	scheduledUpgradeToken += 1
	local token = scheduledUpgradeToken

	local delaySeconds = math.max(0, endTime - os.time())
	task.delay(delaySeconds, function()
		if token ~= scheduledUpgradeToken then
			return
		end

		BaseUpgradeService.CompleteUpgradeIfReady()
	end)
end

local function applyConstructionVisuals(): boolean
	local generated = getGeneratedFolder()
	if not generated then
		return false
	end

	local spawnHub = findSpawnHub(generated)
	if not spawnHub then
		return false
	end

	local house = spawnHub:FindFirstChild("House")
	if house and house:IsA("Model") then
		darkenHouse(house)
	end

	local save = getSaveSafe()
	if not save then
		return false
	end

	local base = ensureBaseState(save)
	setUpgradeAttributes(
		spawnHub,
		true,
		base.upgradeEndsAt,
		BASE_UPGRADE_DURATION_SECONDS,
		base.targetLevel
	)

	disableBasePrompt(generated)
	return true
end

function BaseUpgradeService.StartTimedUpgrade(targetLevel: number, durationSeconds: number?): boolean
	local save = getSaveSafe()
	if not save then
		return false
	end

	local base = ensureBaseState(save)

	if base.level >= targetLevel then
		return false
	end

	if base.isUpgrading then
		return false
	end

	local finalDuration = if durationSeconds ~= nil then math.max(1, math.floor(durationSeconds)) else BASE_UPGRADE_DURATION_SECONDS
	local endTime = os.time() + finalDuration

	-- Apply visuals first, before committing save state.
	local generated = getGeneratedFolder()
	if not generated then
		return false
	end

	local spawnHub = findSpawnHub(generated)
	if not spawnHub then
		return false
	end

	local house = spawnHub:FindFirstChild("House")
	if house and house:IsA("Model") then
		darkenHouse(house)
	end

	base.isUpgrading = true
	base.targetLevel = targetLevel
	base.upgradeEndsAt = endTime

	setUpgradeAttributes(
		spawnHub,
		true,
		endTime,
		finalDuration,
		targetLevel
	)

	disableBasePrompt(generated)
	markDirtySafe()
	scheduleCompletion(endTime)

	return true
end

function BaseUpgradeService.CompleteUpgradeIfReady(): boolean
	local save = getSaveSafe()
	if not save then
		return false
	end

	local base = ensureBaseState(save)
	if not base.isUpgrading then
		return false
	end

	local endTime = base.upgradeEndsAt
	if type(endTime) ~= "number" then
		return false
	end

	if os.time() < endTime then
		return false
	end

	local targetLevel = if type(base.targetLevel) == "number" then base.targetLevel else 2
	local ok = false

	if targetLevel == 2 then
		ok = replaceHouseWithLevel2(true)
	else
		warn("[BaseUpgradeService] Unsupported target level on completion:", targetLevel)
		return false
	end

	if not ok then
		return false
	end

	base.level = targetLevel
	base.isUpgrading = false
	base.targetLevel = nil
	base.upgradeEndsAt = nil

	setBaseLevelSafe(targetLevel)
	markDirtySafe()

	local generated = getGeneratedFolder()
	if generated then
		local spawnHub = findSpawnHub(generated)
		if spawnHub then
			setUpgradeAttributes(spawnHub, false, nil, nil, nil)
		end
	end

	return true
end

function BaseUpgradeService.ApplyLevel(level: number): boolean
	local save = getSaveSafe()
	if not save then
		return level <= 1
	end

	local base = ensureBaseState(save)

	-- Upgrade in progress has priority over current level visuals.
	if base.isUpgrading then
		local endTime = base.upgradeEndsAt
		if type(endTime) == "number" and os.time() >= endTime then
			return BaseUpgradeService.CompleteUpgradeIfReady()
		end

		local ok = applyConstructionVisuals()
		if type(endTime) == "number" then
			scheduleCompletion(endTime)
		end
		return ok
	end

	local safeLevel = math.max(1, math.floor(level))

	if safeLevel <= 1 then
		return true
	end

	if safeLevel == 2 then
		return replaceHouseWithLevel2(false)
	end

	warn("[BaseUpgradeService] Unsupported base level:", safeLevel)
	return false
end

function BaseUpgradeService.UpgradeTo(level: number): boolean
	local safeLevel = math.max(1, math.floor(level))

	if safeLevel ~= 2 then
		warn("[BaseUpgradeService] Unsupported upgrade target:", safeLevel)
		return false
	end

	local ok = replaceHouseWithLevel2(true)
	if not ok then
		return false
	end

	local save = getSaveSafe()
	if save then
		local base = ensureBaseState(save)
		base.level = safeLevel
		base.isUpgrading = false
		base.targetLevel = nil
		base.upgradeEndsAt = nil
	end

	setBaseLevelSafe(safeLevel)
	markDirtySafe()

	return true
end

return BaseUpgradeService