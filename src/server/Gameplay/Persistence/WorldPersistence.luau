--!strict
-- src/server/Gameplay/Persistence/WorldPersistence.luau
-- DataStore-backed persistence by worldId (string).
-- Minimal schema for now: seed + diffs (chopped trees / mined gems).

local DataStoreService = game:GetService("DataStoreService")

local WorldPersistence = {}

export type WorldDiffs = {
	choppedTrees: { [string]: boolean },
	minedGems: { [string]: boolean },
}

export type WorldSave = {
	version: number,
	seed: number?,
	diffs: WorldDiffs,
	lastSavedAt: number,
}

local STORE_NAME = "WorldSaves_v1"
local store = DataStoreService:GetDataStore(STORE_NAME)


-- src/server/Gameplay/Persistence/WorldPersistence.luau

local function newSave(seedOverride: number?): WorldSave
	-- Force a non-nil number for strict typing
	local seed: number
	if seedOverride ~= nil then
		seed = seedOverride
	else
		seed = Random.new():NextInteger(1, 2_000_000_000)
	end

	-- Also explicitly type diffs so Luau doesn't infer overly-wide types
	local diffs: WorldDiffs = {
		choppedTrees = {} :: {[string]: boolean},
		minedGems = {} :: {[string]: boolean},
	}

	local save: WorldSave = {
		version = 1,
		seed = seed,
		diffs = diffs,
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
        -- ✅ return a blank save WITHOUT choosing a seed here
        return {
            version = 1,
            seed = nil,
            diffs = {
                choppedTrees = {} :: {[string]: boolean},
                minedGems = {} :: {[string]: boolean},
            },
            lastSavedAt = 0,
        }
    end



	local t = data :: { [any]: any }

	local seed = t.seed
	if type(seed) ~= "number" then
		return newSave(nil)
	end

    print("[WorldPersistence] Loaded world:", worldId, "seed:", seed)

	local diffsAny = t.diffs
	local diffs: WorldDiffs = {
		choppedTrees = {},
		minedGems = {},
	}

	if type(diffsAny) == "table" then
		local ct = diffsAny.choppedTrees
		local mg = diffsAny.minedGems
		if type(ct) == "table" then
			diffs.choppedTrees = ct :: { [string]: boolean }
		end
		if type(mg) == "table" then
			diffs.minedGems = mg :: { [string]: boolean }
		end
	end

	local version = if type(t.version) == "number" then t.version else 1
	local lastSavedAt = if type(t.lastSavedAt) == "number" then t.lastSavedAt else os.time()

        

	return {
		version = version,
		seed = seed,
		diffs = diffs,
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