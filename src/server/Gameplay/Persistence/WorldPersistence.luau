--!strict
-- src/server/Gameplay/Persistence/WorldPersistence.luau

local DataStoreService = game:GetService("DataStoreService")

local WorldPersistence = {}

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

-- Represents one placed building (Trebuchet, future buildings, etc.)
-- Stored as a flat table so DataStore can serialize it without issues.
-- Position is split into px/py/pz because Vector3 cannot be saved to DataStore.
export type PlacedStructureSave = {
	uid:          string,   -- unique ID per instance, e.g. "Trebuchet_1711234567_123456"
	buildingType: string,   -- key into BuildingService's BUILDING_CONFIGS, e.g. "Trebuchet"
	px: number,             -- world X
	py: number,             -- world Y (ground level)
	pz: number,             -- world Z
	health:       number,   -- 0–100 (100 = full health)
	buildEndsAt:  number?,  -- os.time() when construction finishes; nil = already complete
}

export type StructuresState = {
	base:   BaseStructureState,
	placed: { PlacedStructureSave },  -- every building the player has placed
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

local STORE_NAME = "WorldSaves_v1"
local store = DataStoreService:GetDataStore(STORE_NAME)

local function sanitizeBaseLevel(value: any): number
	if type(value) == "number" then
		local n = math.floor(value)
		if n < 1 then
			return 1
		end
		return n
	end
	return 1
end

local function sanitizeOptionalNumber(value: any): number?
	if type(value) == "number" then
		return value
	end
	return nil
end

local function sanitizeOptionalTargetLevel(value: any): number?
	if type(value) == "number" then
		local n = math.floor(value)
		if n < 1 then
			return nil
		end
		return n
	end
	return nil
end

local function sanitizeCurrentDay(value: any): number
	if type(value) == "number" then
		local n = math.floor(value)
		if n < 1 then
			return 1
		end
		return n
	end
	return 1
end

local function sanitizeCurrentPhase(value: any): "Day" | "Night"
	if value == "Night" then
		return "Night"
	end
	return "Day"
end

local function newSave(seedOverride: number?): WorldSave
	local diffs: WorldDiffs = {
		choppedTrees = {} :: {[string]: boolean},
		minedGems = {} :: {[string]: boolean},
	}

	local inventories: InventoriesMap = {} :: InventoriesMap

	local structures: StructuresState = {
		base = {
			level = 1,
			isUpgrading = false,
			targetLevel = nil,
			upgradeEndsAt = nil,
		},
		placed = {},  -- no buildings placed yet
	}

	local timeState: TimeState = {
		currentDay = 1,
		currentPhase = "Day",
	}

	local save: WorldSave = {
		version = 3,
		seed = seedOverride,
		diffs = diffs,
		inventories = inventories,
		structures = structures,
		time = timeState,
		lastSavedAt = os.time(),
	}

	return save
end

function WorldPersistence.Load(worldId: string): WorldSave
	local ok, data = pcall(function()
		return store:GetAsync(worldId)
	end)

	if not ok then
		warn("[WorldPersistence] Load failed, creating new save. worldId=", worldId, "err=", data)
		return newSave(nil)
	end

	if type(data) ~= "table" then
		return newSave(nil)
	end

	local t = data :: {[any]: any}

	local diffs: WorldDiffs = {
		choppedTrees = {} :: {[string]: boolean},
		minedGems = {} :: {[string]: boolean},
	}

	local diffsAny = t.diffs
	if type(diffsAny) == "table" then
		if type(diffsAny.choppedTrees) == "table" then
			diffs.choppedTrees = diffsAny.choppedTrees :: {[string]: boolean}
		end
		if type(diffsAny.minedGems) == "table" then
			diffs.minedGems = diffsAny.minedGems :: {[string]: boolean}
		end
	end

	local inventories: InventoriesMap = {} :: InventoriesMap
	local invAny = t.inventories
	if type(invAny) == "table" then
		for userKey, itemMapAny in pairs(invAny) do
			if type(userKey) == "string" and type(itemMapAny) == "table" then
				local itemMap: ItemMap = {} :: ItemMap
				for itemName, value in pairs(itemMapAny) do
					if type(itemName) == "string" and type(value) == "number" then
						itemMap[itemName] = value
					end
				end
				inventories[userKey] = itemMap
			end
		end
	end

	local baseLevel = 1
	local baseIsUpgrading = false
	local baseTargetLevel: number? = nil
	local baseUpgradeEndsAt: number? = nil

	local structuresAny = t.structures
	if type(structuresAny) == "table" then
		local baseAny = structuresAny.base
		if type(baseAny) == "table" then
			baseLevel = sanitizeBaseLevel(baseAny.level)
			baseIsUpgrading = if type(baseAny.isUpgrading) == "boolean" then baseAny.isUpgrading else false
			baseTargetLevel = sanitizeOptionalTargetLevel(baseAny.targetLevel)
			baseUpgradeEndsAt = sanitizeOptionalNumber(baseAny.upgradeEndsAt)
		end
	end

	if baseIsUpgrading then
		if baseTargetLevel == nil or baseUpgradeEndsAt == nil then
			baseIsUpgrading = false
			baseTargetLevel = nil
			baseUpgradeEndsAt = nil
		end
	end

	-- ── Deserialize placed buildings ─────────────────────────────────────────
	-- For each saved entry, validate every field before including it.
	-- Corrupt or missing entries are silently skipped so a bad save
	-- doesn't prevent the world from loading.
	local placed: { PlacedStructureSave } = {}
	local placedAny = structuresAny and (structuresAny :: any).placed
	if type(placedAny) == "table" then
		for _, entry in ipairs(placedAny) do
			if type(entry) == "table"
				and type(entry.uid)          == "string"
				and type(entry.buildingType) == "string"
				and type(entry.px)           == "number"
				and type(entry.py)           == "number"
				and type(entry.pz)           == "number"
				and type(entry.health)       == "number"
			then
				table.insert(placed, {
					uid          = entry.uid,
					buildingType = entry.buildingType,
					px           = entry.px,
					py           = entry.py,
					pz           = entry.pz,
					health       = math.clamp(entry.health, 0, 100),
					buildEndsAt  = if type(entry.buildEndsAt) == "number" then entry.buildEndsAt else nil,
				})
			end
		end
	end

	local structures: StructuresState = {
		base = {
			level = baseLevel,
			isUpgrading = baseIsUpgrading,
			targetLevel = baseTargetLevel,
			upgradeEndsAt = baseUpgradeEndsAt,
		},
		placed = placed,
	}

	local currentDay = 1
	local currentPhase: "Day" | "Night" = "Day"

	local timeAny = t.time
	if type(timeAny) == "table" then
		currentDay = sanitizeCurrentDay(timeAny.currentDay)
		currentPhase = sanitizeCurrentPhase(timeAny.currentPhase)
	end

	local timeState: TimeState = {
		currentDay = currentDay,
		currentPhase = currentPhase,
	}

	local version = if type(t.version) == "number" then t.version else 1
	local lastSavedAt = if type(t.lastSavedAt) == "number" then t.lastSavedAt else os.time()
	local seed = if type(t.seed) == "number" then t.seed else nil

	print(
		"[WorldPersistence] Loaded world:",
		worldId,
		"seed:",
		seed,
		"baseLevel:",
		structures.base.level,
		"isUpgrading:",
		structures.base.isUpgrading,
		"targetLevel:",
		structures.base.targetLevel,
		"upgradeEndsAt:",
		structures.base.upgradeEndsAt,
		"currentDay:",
		timeState.currentDay,
		"currentPhase:",
		timeState.currentPhase
	)

	return {
		version = version,
		seed = seed,
		diffs = diffs,
		inventories = inventories,
		structures = structures,
		time = timeState,
		lastSavedAt = lastSavedAt,
	}
end

function WorldPersistence.Save(worldId: string, save: WorldSave)
	save.lastSavedAt = os.time()

	local ok, err = pcall(function()
		store:SetAsync(worldId, save)
	end)

	if not ok then
		warn("[WorldPersistence] Save failed. worldId=", worldId, "err=", err)
	end

	print(
		"[WorldPersistence] Saving world:",
		worldId,
		"seed:",
		save.seed,
		"baseLevel:",
		save.structures.base.level,
		"isUpgrading:",
		save.structures.base.isUpgrading,
		"targetLevel:",
		save.structures.base.targetLevel,
		"upgradeEndsAt:",
		save.structures.base.upgradeEndsAt,
		"currentDay:",
		save.time.currentDay,
		"currentPhase:",
		save.time.currentPhase
	)
end

function WorldPersistence.Reset(worldId: string): WorldSave
	local save = newSave(nil)
	WorldPersistence.Save(worldId, save)
	return save
end

return WorldPersistence