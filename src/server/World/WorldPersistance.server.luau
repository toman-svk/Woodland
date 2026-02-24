--!strict
-- ServerScriptService/Server/World/WorldPersistence.server.luau
-- Per-player world persistence: seed + diffs (chopped/mined) + reset

local DataStoreService = game:GetService("DataStoreService")

export type WorldDiffs = {
	choppedTrees: {[string]: boolean},
	minedGems: {[string]: boolean},
}

export type WorldSave = {
	version: number,
	seed: number,
	diffs: WorldDiffs,
	lastSavedAt: number,
}

local WorldPersistence = {}

local STORE = DataStoreService:GetDataStore("World_v1")
local VERSION = 1

local function keyFor(userId: number): string
	return ("W_%d"):format(userId)
end

local function defaultSave(seed: number): WorldSave
	return {
		version = VERSION,
		seed = seed,
		diffs = {
			choppedTrees = {},
			minedGems = {},
		},
		lastSavedAt = os.time(),
	}
end

local function hashSeed(userId: number): number
	-- stable-ish seed initializer if no save exists
	-- You can swap to Random.new():NextInteger(...) if you want a brand new world per reset only.
	return (userId * 1103515245 + 12345) % 2147483647
end

function WorldPersistence.Load(userId: number): WorldSave
	local k = keyFor(userId)

	local ok, dataAny = pcall(function()
		return STORE:GetAsync(k)
	end)
	if not ok then
		warn("[WorldPersistence] Load failed for", userId, dataAny)
		return defaultSave(hashSeed(userId))
	end

	if typeof(dataAny) ~= "table" then
		return defaultSave(hashSeed(userId))
	end

	local data = dataAny :: any

	-- Versioning: if you change worldgen drastically, bump VERSION and force reset
	if data.version ~= VERSION then
		return defaultSave(hashSeed(userId))
	end

	-- Validate shape lightly
	local seed = (typeof(data.seed) == "number" and data.seed) or hashSeed(userId)
	local diffsAny = (typeof(data.diffs) == "table" and data.diffs) or {}

	local chopped = (typeof(diffsAny.choppedTrees) == "table" and diffsAny.choppedTrees) or {}
	local mined = (typeof(diffsAny.minedGems) == "table" and diffsAny.minedGems) or {}

	return {
		version = VERSION,
		seed = seed,
		diffs = {
			choppedTrees = chopped,
			minedGems = mined,
		},
		lastSavedAt = (typeof(data.lastSavedAt) == "number" and data.lastSavedAt) or os.time(),
	}
end

function WorldPersistence.Save(userId: number, save: WorldSave): boolean
	local k = keyFor(userId)
	save.lastSavedAt = os.time()

	local ok, err = pcall(function()
		-- UpdateAsync avoids stomping if you ever add multi-server per-player later
		STORE:UpdateAsync(k, function(_old)
			return save
		end)
	end)

	if not ok then
		warn("[WorldPersistence] Save failed for", userId, err)
		return false
	end
	return true
end

function WorldPersistence.Reset(userId: number): WorldSave
	-- New random seed on reset = fresh world
	local rng = Random.new()
	local newSeed = rng:NextInteger(1, 2147483647)
	local save = defaultSave(newSeed)
	WorldPersistence.Save(userId, save)
	return save
end

-- Helpers to mutate diffs
function WorldPersistence.MarkTreeChopped(save: WorldSave, treeId: string)
	save.diffs.choppedTrees[treeId] = true
end

function WorldPersistence.MarkGemMined(save: WorldSave, gemId: string)
	save.diffs.minedGems[gemId] = true
end

return WorldPersistence