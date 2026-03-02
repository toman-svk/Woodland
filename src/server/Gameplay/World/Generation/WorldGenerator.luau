--!strict
-- src/server/Gameplay/World/Generation/WorldGenerator.luau
-- Orchestrates world generation in a deterministic order.

local WorldGenerator = {}

export type WorldSave = {
	seed: number?, -- if nil, will be created and written back
}

export type BuildResult = {
	terrain: boolean,
	spawnHub: number?,
	caves: number,
	gems: number,
	trees: number,
	enemies: number,
}

local function mustModule(parent: Instance, name: string): ModuleScript
	local inst = parent:WaitForChild(name)
	if not inst:IsA("ModuleScript") then
		error(("Expected %s under %s to be ModuleScript, got %s"):format(name, parent:GetFullName(), inst.ClassName))
	end
	return inst
end

local function ensureFolder(parent: Instance, name: string): Folder
	local f = parent:FindFirstChild(name)
	if f and f:IsA("Folder") then
		return f
	end
	local nf = Instance.new("Folder")
	nf.Name = name
	nf.Parent = parent
	return nf
end

type BuildFn = (root: Folder, origin: Vector3, rng: Random, save: WorldSave) -> unknown
type BuildModule = { Build: BuildFn }

local function safeBuild(stepName: string, mod: unknown, root: Folder, origin: Vector3, rng: Random, save: WorldSave): unknown
	if type(mod) ~= "table" then
		warn(("[WorldGenerator] %s is not a table module. Skipping."):format(stepName))
		return nil
	end

	local m = mod :: any
	local build = m.Build
	if type(build) ~= "function" then
		warn(("[WorldGenerator] %s has no Build(root, origin, rng, save). Skipping."):format(stepName))
		return nil
	end

	local ok, result = pcall(function()
		return (build :: BuildFn)(root, origin, rng, save)
	end)

	if not ok then
		warn(("[WorldGenerator] Step %s failed: %s"):format(stepName, tostring(result)))
		return nil
	end

	return result
end

-- Require sibling modules by Instance (safe for Luau analyzer + Rojo)
local folder = script.Parent

local TerrainGenerator = require(mustModule(folder, "TerrainGenerator"))::any
local SpawnHubRuntime = require(mustModule(folder, "SpawnHubRuntime"))::any
local SpawnCaves = require(mustModule(folder, "SpawnCaves"))::any
local SpawnGems = require(mustModule(folder, "SpawnGems"))::any
local SpawnTrees = require(mustModule(folder, "SpawnTrees"))::any
local SpawnCaveSkeletons = require(mustModule(folder, "SpawnCaveSkeletons"))::any

function WorldGenerator.Build(root: Folder, origin: Vector3, rng: Random, save: WorldSave): BuildResult
	-- Ensure common folders exist (modules may also do it; harmless)
	ensureFolder(root, "Caves")
	ensureFolder(root, "Gems")
	ensureFolder(root, "Trees")
	ensureFolder(root, "Enemies")

	-- Stabilize seed if missing (important for determinism + saving)
	if save.seed == nil then
		save.seed = rng:NextInteger(1, 2_000_000_000)
	end

	local result: BuildResult = {
		terrain = false,
		spawnHub = nil,
		caves = 0,
		gems = 0,
		trees = 0,
		enemies = 0,
	}

	-- 1) Terrain
	do
		local r = safeBuild("Terrain", TerrainGenerator, root, origin, rng, save)
		result.terrain = (r ~= nil)
	end

	-- 2) SpawnHub Template (your hand-built stuff)
	do
		local r = safeBuild("SpawnHubRuntime", SpawnHubRuntime, root, origin, rng, save)
		if type(r) == "number" then
			result.spawnHub = r
		end
	end

	-- 3) Caves
	do
		local r = safeBuild("Caves", SpawnCaves, root, origin, rng, save)
		if type(r) == "number" then
			result.caves = r
		end
	end

	-- 4) Gems (depends on caves)
	do
		local r = safeBuild("Gems", SpawnGems, root, origin, rng, save)
		if type(r) == "number" then
			result.gems = r
		end
	end

	-- 5) Trees
	do
		local r = safeBuild("Trees", SpawnTrees, root, origin, rng, save)
		if type(r) == "number" then
			result.trees = r
		end
	end

	-- 6) Enemies (depends on caves)
	do
		local r = safeBuild("CaveSkeletons", SpawnCaveSkeletons, root, origin, rng, save)
		if type(r) == "number" then
			result.enemies = r
		end
	end

	return result
end

return WorldGenerator