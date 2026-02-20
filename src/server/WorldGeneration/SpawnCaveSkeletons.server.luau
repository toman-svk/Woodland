-- ServerScriptService/WorldGeneneration/SpawnCaveSkeletons.server.lua

local ServerStorage = game:GetService("ServerStorage")

local WorldConfig = require(script.Parent.Parent.WorldModules:WaitForChild("WorldConfig"))
local WorldHeight = require(script.Parent.Parent.WorldModules:WaitForChild("WorldHeight"))

local skeletonTemplate = ServerStorage
	:WaitForChild("Templates")
	:WaitForChild("Characters")
	:WaitForChild("Skeleton")

-- Where caves were placed by SpawnCaves
local cavesFolder = workspace:WaitForChild("Generated"):WaitForChild("Caves")

-- Optional: put spawned skeletons in their own folder
local enemiesFolder = workspace.Generated:FindFirstChild("Enemies") or Instance.new("Folder")
enemiesFolder.Name = "Enemies"
enemiesFolder.Parent = workspace.Generated

local function unanchorModel(model)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = false
		end
	end
end

local function anchorModel(model, anchored)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = anchored
		end
	end
end

local function getModelXZ(model)
	local cf = model:GetPivot()
	return Vector3.new(cf.Position.X, 0, cf.Position.Z)
end

-- Spawn settings
local SKELETONS_PER_CAVE = 3
local SPAWN_RADIUS_MIN = 18
local SPAWN_RADIUS_MAX = 35
local MAX_TRIES_PER_SKELETON = 12

local function spawnSkeletonAt(x, z)
	local h = WorldHeight.heightAt(x, z)
	local groundY = WorldConfig.BASE_Y + h

	local skel = skeletonTemplate:Clone()
	skel.Parent = enemiesFolder

	-- Place on ground using bounding box height
	local _, size = skel:GetBoundingBox()
	skel:PivotTo(CFrame.new(x, groundY + size.Y/2 + 1, z) * CFrame.Angles(0, math.rad(math.random(0, 360)), 0))

	-- Ensure it can move (your AI script will do this too, but safe)
	unanchorModel(skel)

	-- If you want them not to topple easily, you can optionally anchor accessories etc (usually not needed)

	return skel
end

local caves = cavesFolder:GetChildren()
if #caves == 0 then
	warn("No caves found in workspace/Generated/Caves. Did SpawnCaves run first?")
	return
end

local totalSpawned = 0

for _, cave in ipairs(caves) do
	if cave:IsA("Model") then
		local cavePos = cave:GetPivot().Position

		for i = 1, SKELETONS_PER_CAVE do
			local spawned = false

			for _ = 1, MAX_TRIES_PER_SKELETON do
				-- Pick a random point in an annulus around the cave
				local angle = math.random() * math.pi * 2
				local radius = math.random(SPAWN_RADIUS_MIN, SPAWN_RADIUS_MAX)
				local x = cavePos.X + math.cos(angle) * radius
				local z = cavePos.Z + math.sin(angle) * radius

				-- Optional: avoid spawning too far outside generated world
				local half = WorldConfig.AREA_SIZE / 2
				if x < -half or x > half or z < -half or z > half then
					continue
				end

				spawnSkeletonAt(x, z)
				totalSpawned += 1
				spawned = true
				break
			end

			if not spawned then
				warn("Could not find a good spawn point for a skeleton near cave:", cave.Name)
			end
		end
	end
end

print(("Spawned %d skeletons near %d caves."):format(totalSpawned, #caves))