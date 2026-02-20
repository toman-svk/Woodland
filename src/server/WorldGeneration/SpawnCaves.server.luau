-- ServerScriptService/WorldGeneneration/SpawnCaves.server.lua

local ServerStorage = game:GetService("ServerStorage")

local WorldConfig = require(script.Parent.Parent.WorldModules:WaitForChild("WorldConfig"))
local WorldHeight = require(script.Parent.Parent.WorldModules:WaitForChild("WorldHeight"))

local caveTemplate = ServerStorage
	:WaitForChild("Templates")
	:WaitForChild("Caves")
	:WaitForChild("Cave")

local generatedFolder = workspace:FindFirstChild("Generated")
if not generatedFolder then
	generatedFolder = Instance.new("Folder")
	generatedFolder.Name = "Generated"
	generatedFolder.Parent = workspace
end

local cavesFolder = generatedFolder:FindFirstChild("Caves")
if not cavesFolder then
	cavesFolder = Instance.new("Folder")
	cavesFolder.Name = "Caves"
	cavesFolder.Parent = generatedFolder
end

local function anchorModel(model, anchored)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = anchored
		end
	end
end

-- Spawn hub avoidance
local SPAWN_X = WorldConfig.SPAWN_CENTER_X or 0
local SPAWN_Z = WorldConfig.SPAWN_CENTER_Z or 0
local SPAWN_R = WorldConfig.SPAWN_CLEAR_RADIUS or 90
local SPAWN_R2 = SPAWN_R * SPAWN_R

local function inSpawnHub(x, z)
	local dx = x - SPAWN_X
	local dz = z - SPAWN_Z
	return (dx*dx + dz*dz) <= SPAWN_R2
end

local half = WorldConfig.AREA_SIZE / 2
local caveCount = 0
local maxCaves = WorldConfig.MAX_CAVES or math.huge

for x = -half, half, WorldConfig.CAVE_SPACING do
	for z = -half, half, WorldConfig.CAVE_SPACING do
		if caveCount >= maxCaves then break end

		local ox = math.random(-WorldConfig.CAVE_JITTER, WorldConfig.CAVE_JITTER)
		local oz = math.random(-WorldConfig.CAVE_JITTER, WorldConfig.CAVE_JITTER)

		local px = x + ox
		local pz = z + oz

		-- ✅ keep spawn hub clear
		if inSpawnHub(px, pz) then
			continue
		end

		local h = WorldHeight.heightAt(px, pz)
		local groundY = WorldConfig.BASE_Y + h

		local cave = caveTemplate:Clone()
		local _, size = cave:GetBoundingBox()
		local rotation = CFrame.Angles(0, math.rad(math.random(0, 360)), 0)

		cave.Parent = cavesFolder
		cave:PivotTo(CFrame.new(px, groundY + size.Y/2, pz) * rotation)
		anchorModel(cave, true)

		caveCount += 1
	end
	if caveCount >= maxCaves then break end
end

print("Spawned caves:", caveCount)