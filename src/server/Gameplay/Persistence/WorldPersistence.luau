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

export type WorldSave = {
	version: number,
	seed: number?,
	diffs: WorldDiffs,
	inventories: InventoriesMap,
	lastSavedAt: number,
}

local STORE_NAME = "WorldSaves_v1"
local store = DataStoreService:GetDataStore(STORE_NAME)

local function newSave(seedOverride: number?): WorldSave
	local diffs: WorldDiffs = {
		choppedTrees = {} :: {[string]: boolean},
		minedGems = {} :: {[string]: boolean},
	}

	local inventories: InventoriesMap = {} :: InventoriesMap

	local save: WorldSave = {
		version = 1,
		seed = seedOverride,
		diffs = diffs,
		inventories = inventories,
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

	local version = if type(t.version) == "number" then t.version else 1
	local lastSavedAt = if type(t.lastSavedAt) == "number" then t.lastSavedAt else os.time()
	local seed = if type(t.seed) == "number" then t.seed else nil

	print("[WorldPersistence] Loaded world:", worldId, "seed:", seed)

	return {
		version = version,
		seed = seed,
		diffs = diffs,
		inventories = inventories,
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

	print("[WorldPersistence] Saving world:", worldId, "seed:", save.seed)
end

function WorldPersistence.Reset(worldId: string): WorldSave
	local save = newSave(nil)
	WorldPersistence.Save(worldId, save)
	return save
end

return WorldPersistence