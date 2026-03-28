--!strict
-- src/server/Gameplay/World/Runtime/WorldService.luau

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local ConfigLocator = require(script.Parent.Parent:WaitForChild("Config"):WaitForChild("ConfigLocator"))
local WorldConfig = ConfigLocator.WorldConfig
local WorldHeight = ConfigLocator.WorldHeight

local RESET_WORLD_SAVE_IN_STUDIO = true
local GAMEPLAY_PLACE_ID = 74640557554115

if game.PlaceId ~= GAMEPLAY_PLACE_ID then
	return {}
end

local WorldIds = require(script.Parent:WaitForChild("WorldIds"))
local WorldGenerator = require(script.Parent.Parent:WaitForChild("Generation"):WaitForChild("WorldGenerator"))
local WorldPersistence = require(script.Parent.Parent.Parent:WaitForChild("Persistence"):WaitForChild("WorldPersistence"))

export type WorldDiffs = {
	choppedTrees: {[string]: boolean},
	minedGems: {[string]: boolean},
}

export type ItemMap = {[string]: number}
export type InventoriesMap = {[string]: ItemMap}

export type BaseStructureState = {
	level: number,
	isUpgrading: boolean,
	targetLevel: number?,
	upgradeEndsAt: number?,
}

export type PlacedStructureSave = {
	uid:          string,
	buildingType: string,
	px: number,
	py: number,
	pz: number,
	health:      number,
	buildEndsAt: number?,
}

export type StructuresState = {
	base:   BaseStructureState,
	placed: { PlacedStructureSave },
}

export type TimeState = {
	currentDay: number,
	currentPhase: "Day" | "Night",
}

export type WorldSave = {
	version: number,
	seed: number?,
	diffs: WorldDiffs,
	inventories: InventoriesMap,
	structures: StructuresState,
	time: TimeState,
	lastSavedAt: number,
}

export type WorldRuntime = {
	worldId: string,
	ownerUserId: number,
	save: WorldSave,
	root: Folder,
	generated: Folder,
	origin: Vector3,
	rng: Random,
	spawnCFrame: CFrame?,
}

local WorldService = {}

local worldsFolder = Workspace:FindFirstChild("Worlds")
if not (worldsFolder and worldsFolder:IsA("Folder")) then
	worldsFolder = Instance.new("Folder")
	worldsFolder.Name = "Worlds"
	worldsFolder.Parent = Workspace
end

local current: WorldRuntime? = nil
local dirty = false

local AUTOSAVE_PERIOD = 30
local lastSaveClock = 0.0

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

function WorldService.GetCurrentWorld(): WorldRuntime?
	return current
end

local function destroyCurrentWorld()
	if current then
		if current.root.Parent then
			current.root:Destroy()
		end
		current = nil
	end
end

local function createWorldFolders(worldId: string): (Folder, Folder)
	local root = getOrCreateFolder(worldsFolder :: Folder, worldId)
	for _, c in ipairs(root:GetChildren()) do
		c:Destroy()
	end

	local generated = Instance.new("Folder")
	generated.Name = "Generated"
	generated.Parent = root

	return root, generated
end

local function teleportPlayerToSpawn(player: Player, origin: Vector3, spawnCFrame: CFrame?)
	local spawnX = WorldConfig.SPAWN_CENTER_X or 0
	local spawnZ = WorldConfig.SPAWN_CENTER_Z or 0
	local baseY = WorldConfig.BASE_Y or 0

	-- How many studs above the spawn point to drop the player from.
	-- Tall enough to guarantee we're above terrain regardless of voxel snapping,
	-- small enough that the fall looks natural and not disorienting.
	local SPAWN_DROP_HEIGHT = 12

	local function place(char: Model)
		local hrp = char:FindFirstChild("HumanoidRootPart")
		if not (hrp and hrp:IsA("BasePart")) then
			return
		end

		if spawnCFrame ~= nil then
			-- Drop the player above the SpawnLocation so they always land on top
			-- of the hub rather than clipping through it.
			hrp.CFrame = spawnCFrame + Vector3.new(0, SPAWN_DROP_HEIGHT, 0)
			return
		end

		-- Fallback: no SpawnLocation found, calculate ground height manually.
		local h = WorldHeight.heightAt(origin.X + spawnX, origin.Z + spawnZ)
		local groundY = baseY + h
		hrp.CFrame = CFrame.new(origin.X + spawnX, groundY + SPAWN_DROP_HEIGHT, origin.Z + spawnZ)
	end

	if player.Character then
		place(player.Character)
	end
	player.CharacterAdded:Connect(place)
end

local function extractTeleportData(player: Player): ({[string]: any}?, string?)
	local joinData = player:GetJoinData()
	local tp = joinData.TeleportData
	if tp == nil then
		return nil, "TeleportData missing"
	end
	if type(tp) ~= "table" then
		return nil, "TeleportData not a table"
	end
	return tp :: {[string]: any}, nil
end

local function ensureSeed(save: WorldSave, tpSeed: number?): number
	if typeof(save.seed) == "number" then
		return save.seed :: number
	end

	if typeof(tpSeed) == "number" then
		save.seed = tpSeed
		return tpSeed
	end

	local newS = Random.new():NextInteger(1, 2_000_000_000)
	save.seed = newS
	return newS
end

local function updateRootAttributes()
	if current == nil then
		return
	end

	local base = current.save.structures.base
	local timeState = current.save.time

	current.root:SetAttribute("BaseLevel", base.level)
	current.root:SetAttribute("BaseIsUpgrading", base.isUpgrading)
	current.root:SetAttribute("BaseTargetLevel", base.targetLevel)
	current.root:SetAttribute("BaseUpgradeEndsAt", base.upgradeEndsAt)

	current.root:SetAttribute("CurrentDay", timeState.currentDay)
	current.root:SetAttribute("CurrentPhase", timeState.currentPhase)
end

local function bootstrapFromFirstPlayer(firstPlayer: Player)
	local tp, tpErr = extractTeleportData(firstPlayer)

	local worldId: string
	local ownerUserId: number

	if tp and type(tp.worldId) == "string" then
		worldId = tp.worldId
		ownerUserId = if type(tp.ownerUserId) == "number" then tp.ownerUserId else firstPlayer.UserId
	else
		worldId = WorldIds.Solo(firstPlayer.UserId)
		ownerUserId = firstPlayer.UserId
		warn(("[WorldService] Missing TeleportData.worldId. Falling back to %s"):format(worldId))
		if tpErr then
			warn("[WorldService] TeleportData issue:", tpErr)
		end
	end

	local tpSeed: number? = nil
	if tp and type((tp :: any).seed) == "number" then
		tpSeed = (tp :: any).seed :: number
	end

	local save: WorldSave
	if RunService:IsStudio() and RESET_WORLD_SAVE_IN_STUDIO then
		save = WorldPersistence.Reset(worldId) :: WorldSave
		print("[WorldService] Studio reset enabled. Reset world:", worldId)
	else
		save = WorldPersistence.Load(worldId) :: WorldSave
	end

	local seed = ensureSeed(save, tpSeed)

	if tpSeed ~= nil and save.seed == tpSeed then
		WorldPersistence.Save(worldId, save)
	end

	print("========== WORLD BOOTSTRAP ==========")
	print("[WorldService] Player:", firstPlayer.Name)
	print("[WorldService] WorldId:", worldId)
	print("[WorldService] OwnerUserId:", ownerUserId)
	print("[WorldService] Save.seed:", tostring(save.seed))
	print("[WorldService] TeleportData.seed:", tostring(tpSeed))
	print("[WorldService] Base level:", save.structures.base.level)
	print("[WorldService] Base isUpgrading:", save.structures.base.isUpgrading)
	print("[WorldService] Base targetLevel:", tostring(save.structures.base.targetLevel))
	print("[WorldService] Base upgradeEndsAt:", tostring(save.structures.base.upgradeEndsAt))
	print("[WorldService] Current day:", save.time.currentDay)
	print("[WorldService] Current phase:", save.time.currentPhase)
	print("[WorldService] Using seed:", seed)
	print("=====================================")

	destroyCurrentWorld()
	local root, generated = createWorldFolders(worldId)

	local origin = Vector3.new(0, 0, 0)
	local rng = Random.new(seed)

	root:SetAttribute("WorldId", worldId)
	root:SetAttribute("OwnerUserId", ownerUserId)
	root:SetAttribute("Seed", seed)

	WorldHeight.SetSeed(seed)

	print(("[WorldService] Generating worldId=%s seed=%d ..."):format(worldId, seed))
	local buildResult = WorldGenerator.Build(generated, origin, rng, save)

	local spawnCFrame: CFrame? = nil
	do
		local anyRes = buildResult :: any
		if typeof(anyRes.spawnCFrame) == "CFrame" then
			spawnCFrame = anyRes.spawnCFrame :: CFrame
		end
	end

	print("[WorldService] WorldGenerator result:", buildResult)

	current = {
		worldId = worldId,
		ownerUserId = ownerUserId,
		save = save,
		root = root,
		generated = generated,
		origin = origin,
		rng = rng,
		spawnCFrame = spawnCFrame,
	}

	updateRootAttributes()
	teleportPlayerToSpawn(firstPlayer, origin, spawnCFrame)
end

function WorldService.GetWorldId(): string?
	return if current then current.worldId else nil
end

function WorldService.GetSave(): WorldSave?
	return if current then current.save else nil
end

function WorldService.GetBaseLevel(): number
	if current == nil then
		return 1
	end
	return current.save.structures.base.level
end

function WorldService.SetBaseLevel(level: number)
	if current == nil then
		return
	end

	local safeLevel = math.max(1, math.floor(level))
	current.save.structures.base.level = safeLevel
	updateRootAttributes()
	WorldService.MarkDirty()
end

function WorldService.SetBaseUpgradeState(state: {
	isUpgrading: boolean,
	targetLevel: number?,
	upgradeEndsAt: number?,
}?)
	if current == nil then
		return
	end

	local base = current.save.structures.base

	if state == nil then
		base.isUpgrading = false
		base.targetLevel = nil
		base.upgradeEndsAt = nil
	else
		base.isUpgrading = state.isUpgrading
		base.targetLevel = state.targetLevel
		base.upgradeEndsAt = state.upgradeEndsAt
	end

	updateRootAttributes()
	WorldService.MarkDirty()
end

function WorldService.GetCurrentDay(): number
	if current == nil then
		return 1
	end
	return current.save.time.currentDay
end

function WorldService.GetCurrentPhase(): "Day" | "Night"
	if current == nil then
		return "Day"
	end
	return current.save.time.currentPhase
end

function WorldService.SetTimeState(currentDay: number, currentPhase: "Day" | "Night")
	if current == nil then
		return
	end

	local safeDay = math.max(1, math.floor(currentDay))
	local safePhase: "Day" | "Night" = if currentPhase == "Night" then "Night" else "Day"

	current.save.time.currentDay = safeDay
	current.save.time.currentPhase = safePhase

	updateRootAttributes()
	WorldService.MarkDirty()
end

function WorldService.MarkDirty()
	dirty = true
end

function WorldService.Bootstrap()
	local booted = false

	Players.PlayerAdded:Connect(function(player)
		if not booted then
			booted = true
			bootstrapFromFirstPlayer(player)
		else
			if current then
				teleportPlayerToSpawn(player, current.origin, current.spawnCFrame)
			end
		end
	end)

	task.spawn(function()
		while true do
			task.wait(2)

			if not current then
				continue
			end

			local now = os.clock()
			if dirty and (now - lastSaveClock) >= AUTOSAVE_PERIOD then
				dirty = false
				lastSaveClock = now

				current.save.lastSavedAt = os.time()
				WorldPersistence.Save(current.worldId, current.save)
				print("[WorldService] Autosaved:", current.worldId)
			end
		end
	end)

	game:BindToClose(function()
		if current then
			current.save.lastSavedAt = os.time()
			WorldPersistence.Save(current.worldId, current.save)
		end
	end)

	print("[WorldService] Bootstrapping (waiting for first player)...")
end

return WorldService