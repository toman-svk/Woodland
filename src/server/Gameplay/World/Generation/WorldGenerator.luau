--!strict
-- src/server/Gameplay/World/Generation/WorldGenerator.luau
-- Orchestrates world generation in a deterministic order.

local WorldGenerator = {}

export type WorldSave = {
	seed: number?,
}

export type BuildResult = {
	terrain: boolean,
	spawnHub: number,
	spawnCFrame: CFrame?, -- ✅ exposed for teleport
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

local function safeBuild(stepName: string, mod: any, root: Folder, origin: Vector3, rng: Random, save: WorldSave): any
	if type(mod) ~= "table" or type(mod.Build) ~= "function" then
		warn(("[WorldGenerator] %s has no Build(root, origin, rng, save). Skipping."):format(stepName))
		return nil
	end

	local ok, result = pcall(function()
		return mod.Build(root, origin, rng, save)
	end)

	if not ok then
		warn(("[WorldGenerator] Step %s failed: %s"):format(stepName, tostring(result)))
		return nil
	end

	return result
end

local folder = script.Parent
local TerrainGenerator = require(mustModule(folder, "TerrainGenerator")) :: any
local SpawnCaves = require(mustModule(folder, "SpawnCaves")) :: any
local SpawnGems = require(mustModule(folder, "SpawnGems")) :: any
local SpawnTrees = require(mustModule(folder, "SpawnTrees")) :: any
local SpawnCaveSkeletons = require(mustModule(folder, "SpawnCaveSkeletons")) :: any
local SpawnHubRuntime = require(mustModule(folder, "SpawnHubRuntime")) :: any

function WorldGenerator.Build(root: Folder, origin: Vector3, rng: Random, save: WorldSave): BuildResult
	ensureFolder(root, "Caves")
	ensureFolder(root, "Gems")
	ensureFolder(root, "Trees")
	ensureFolder(root, "Enemies")

	if save.seed == nil then
		save.seed = rng:NextInteger(1, 2_000_000_000)
	end

	local result: BuildResult = {
		terrain = false,
		spawnHub = 0,
		spawnCFrame = nil,
		caves = 0,
		gems = 0,
		trees = 0,
		enemies = 0,
	}

	-- 1) Terrain
	safeBuild("Terrain", TerrainGenerator, root, origin, rng, save)
	result.terrain = true

	-- 2) Spawn hub (ONLY ONCE) + capture SpawnLocation
	do
		local hubRes = safeBuild("SpawnHubRuntime", SpawnHubRuntime, root, origin, rng, save)
		if type(hubRes) == "table" then
			local t = hubRes :: any
			if type(t.count) == "number" then
				result.spawnHub = t.count
			end
			if typeof(t.spawnCFrame) == "CFrame" then
				result.spawnCFrame = t.spawnCFrame
			end
		elseif type(hubRes) == "number" then
			result.spawnHub = hubRes
		end
	end

	-- 3) Caves
	do
		local cavesCount = safeBuild("Caves", SpawnCaves, root, origin, rng, save)
		if type(cavesCount) == "number" then
			result.caves = cavesCount
		end
	end

	-- 4) Gems
	do
		local gemsCount = safeBuild("Gems", SpawnGems, root, origin, rng, save)
		if type(gemsCount) == "number" then
			result.gems = gemsCount
		end
	end

	-- 5) Trees
	do
		local treesCount = safeBuild("Trees", SpawnTrees, root, origin, rng, save)
		if type(treesCount) == "number" then
			result.trees = treesCount
		end
	end

	-- 6) Enemies
	do
		local enemiesCount = safeBuild("CaveSkeletons", SpawnCaveSkeletons, root, origin, rng, save)
		if type(enemiesCount) == "number" then
			result.enemies = enemiesCount
		end
	end

	return result
end

return WorldGenerator