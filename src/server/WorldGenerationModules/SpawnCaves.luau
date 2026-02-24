--!strict
-- ServerScriptService/Server/WorldGenerationModules/SpawnCaves.luau


local ServerStorage = game:GetService("ServerStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local WorldConfig = require(ServerScriptService.Server.WorldModules.WorldConfig)
local WorldHeight = require(ServerScriptService.Server.WorldModules.WorldHeight)

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

local SpawnCaves = {}

local caveTemplate = ServerStorage
	:WaitForChild("Templates")
	:WaitForChild("Caves")
	:WaitForChild("Cave") :: Model

local function anchorModel(model: Model, anchored: boolean)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = anchored
		end
	end
end

local function getOrCreateFolder(parent: Instance, name: string): Folder
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("Folder") then
		return existing
	end
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

local function inSpawnHub(localX: number, localZ: number): boolean
	local SPAWN_X: number = (WorldConfig.SPAWN_CENTER_X :: number?) or 0
	local SPAWN_Z: number = (WorldConfig.SPAWN_CENTER_Z :: number?) or 0
	local SPAWN_R: number = (WorldConfig.SPAWN_CLEAR_RADIUS :: number?) or 90
	local dx = localX - SPAWN_X
	local dz = localZ - SPAWN_Z
	return (dx * dx + dz * dz) <= (SPAWN_R * SPAWN_R)
end

local function inWorld(localX: number, localZ: number): boolean
	local WORLD_R: number = (WorldConfig.WORLD_RADIUS :: number?) or ((WorldConfig.AREA_SIZE :: number) / 2)
	local EDGE_MARGIN: number = (WorldConfig.SPAWN_EDGE_MARGIN :: number?) or 0
	local r = (WORLD_R - EDGE_MARGIN)
	return (localX * localX + localZ * localZ) <= (r * r)
end

function SpawnCaves.Build(root: Folder, origin: Vector3, rng: Random, _save: WorldSave?): number
	local cavesFolder = getOrCreateFolder(root, "Caves")

	local half: number = ((WorldConfig.AREA_SIZE :: number?) or 800) / 2
	local BASE_Y: number = (WorldConfig.BASE_Y :: number?) or 0

	local spacing: number = (WorldConfig.CAVE_SPACING :: number?) or 240
	local jitter: number = (WorldConfig.CAVE_JITTER :: number?) or 50
	local caveChance: number = (WorldConfig.CAVE_CHANCE :: number?) or 0.25
	local maxCaves: number = (WorldConfig.MAX_CAVES :: number?) or 18

	local caveCount = 0

	for lx = -half, half, spacing do
		for lz = -half, half, spacing do
			if caveCount >= maxCaves then
				break
			end

			if rng:NextNumber() > caveChance then
				continue
			end

			local px = lx + rng:NextInteger(-jitter, jitter)
			local pz = lz + rng:NextInteger(-jitter, jitter)

			if not inWorld(px, pz) then
				continue
			end
			if inSpawnHub(px, pz) then
				continue
			end

			local h = WorldHeight.heightAt(origin.X + px, origin.Z + pz)
			local groundY = BASE_Y + h

			local cave = caveTemplate:Clone()
			local _, size = cave:GetBoundingBox()
			local rot = CFrame.Angles(0, math.rad(rng:NextInteger(0, 359)), 0)

			cave.Parent = cavesFolder
			cave:PivotTo(CFrame.new(origin.X + px, groundY + size.Y / 2, origin.Z + pz) * rot)
			anchorModel(cave, true)

			caveCount += 1
		end

		if caveCount >= maxCaves then
			break
		end
	end

	print("[SpawnCaves] Spawned caves:", caveCount, "in", root:GetFullName())
	return caveCount
end

return SpawnCaves