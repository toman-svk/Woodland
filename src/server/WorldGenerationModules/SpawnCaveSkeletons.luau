--!strict
-- ServerScriptService/Server/WorldGenerationModules/SpawnCaveSkeletons.luau

local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local ServerScriptService = game:GetService("ServerScriptService")

local WorldConfig = require(ServerScriptService.Server.WorldModules.WorldConfig)
local WorldHeight = require(ServerScriptService.Server.WorldModules.WorldHeight)

local SpawnCaveSkeletons = {}

local function mustModel(parent: Instance, name: string): Model
	local inst = parent:WaitForChild(name)
	if not inst:IsA("Model") then
		error(("Expected %s under %s to be Model, got %s"):format(name, parent:GetFullName(), inst.ClassName))
	end
	return inst
end

local templates = ServerStorage:WaitForChild("Templates")
local charactersFolder = mustModel(templates, "Characters")
local skeletonTemplate: Model = mustModel(charactersFolder, "Skeleton")

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

local function setAnchored(model: Model, anchored: boolean)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = anchored
		end
	end
end

local function getGenerated(): Folder
	local gen = Workspace:FindFirstChild("Generated")
	if gen and gen:IsA("Folder") then
		return gen
	end
	local nf = Instance.new("Folder")
	nf.Name = "Generated"
	nf.Parent = Workspace
	return nf
end

-- Spawn settings
local SKELETONS_PER_CAVE = 3
local SPAWN_RADIUS_MIN = 18
local SPAWN_RADIUS_MAX = 35
local MAX_TRIES_PER_SKELETON = 12

local function spawnSkeletonAt(x: number, z: number, enemiesFolder: Folder): Model
	local h = WorldHeight.heightAt(x, z)
	local groundY = (WorldConfig.BASE_Y or 0) + h

	local skel = skeletonTemplate:Clone()
	skel.Parent = enemiesFolder

	local _, size = skel:GetBoundingBox()
	local rot = CFrame.Angles(0, math.rad(math.random(0, 360)), 0)
	skel:PivotTo(CFrame.new(x, groundY + size.Y / 2 + 1, z) * rot)

	-- must be unanchored for humanoid movement
	setAnchored(skel, false)

	return skel
end

function SpawnCaveSkeletons.Run(): number
	local generated = getGenerated()

	local cavesFolder = generated:FindFirstChild("Caves")
	if not (cavesFolder and cavesFolder:IsA("Folder")) then
		warn("No caves found in workspace/Generated/Caves. Did SpawnCaves run first?")
		return 0
	end

	local caves = cavesFolder:GetChildren()
	if #caves == 0 then
		warn("No caves found in workspace/Generated/Caves. Did SpawnCaves run first?")
		return 0
	end

	local enemiesFolder = getOrCreateFolder(generated, "Enemies")

	local totalSpawned = 0
	local half = (WorldConfig.AREA_SIZE or 800) / 2

	for _, cave in ipairs(caves) do
		if not cave:IsA("Model") then
			continue
		end

		local cavePos = cave:GetPivot().Position

		for _ = 1, SKELETONS_PER_CAVE do
			local spawned = false

			for _ = 1, MAX_TRIES_PER_SKELETON do
				local angle = math.random() * math.pi * 2
				local radius = math.random(SPAWN_RADIUS_MIN, SPAWN_RADIUS_MAX)
				local x = cavePos.X + math.cos(angle) * radius
				local z = cavePos.Z + math.sin(angle) * radius

				-- keep inside square bounds
				if x < -half or x > half or z < -half or z > half then
					continue
				end

				spawnSkeletonAt(x, z, enemiesFolder)
				totalSpawned += 1
				spawned = true
				break
			end

			if not spawned then
				warn("Could not find a good spawn point for a skeleton near cave:", cave.Name)
			end
		end
	end

	print(("Spawned %d skeletons near %d caves."):format(totalSpawned, #caves))
	return totalSpawned
end

return SpawnCaveSkeletons