-- ServerScriptService/WorldGeneneration/SpawnGems.server.lua

local ServerStorage = game:GetService("ServerStorage")

local WorldConfig = require(script.Parent.Parent.WorldModules:WaitForChild("WorldConfig"))
local WorldHeight = require(script.Parent.Parent.WorldModules:WaitForChild("WorldHeight"))

local crystalTemplate = ServerStorage
	:WaitForChild("Templates")
	:WaitForChild("Gems")
	:WaitForChild("Crystal")

local generatedFolder = workspace:FindFirstChild("Generated")
if not generatedFolder then
	generatedFolder = Instance.new("Folder")
	generatedFolder.Name = "Generated"
	generatedFolder.Parent = workspace
end

local gemsFolder = generatedFolder:FindFirstChild("Gems")
if not gemsFolder then
	gemsFolder = Instance.new("Folder")
	gemsFolder.Name = "Gems"
	gemsFolder.Parent = generatedFolder
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

-- GEM SETTINGS
local GEM_SPACING = 60
local GEM_JITTER = 20
local MAX_GEMS = 250

local AVOID_ROCK = true
local ROCK_MARGIN = 0
local OVERLAP_PADDING = Vector3.new(6, 10, 6)
local ATTEMPTS_PER_CELL = 3

local overlapParams = OverlapParams.new()
overlapParams.FilterType = Enum.RaycastFilterType.Include
overlapParams.FilterDescendantsInstances = { generatedFolder }

local function isSpotClear(cframe: CFrame, size: Vector3): boolean
	local checkSize = size + OVERLAP_PADDING
	local parts = workspace:GetPartBoundsInBox(cframe, checkSize, overlapParams)
	return #parts == 0
end

local function getModelSize(model: Model): Vector3
	local _, s = model:GetBoundingBox()
	return s
end

local crystalSize = getModelSize(crystalTemplate)

local half = WorldConfig.AREA_SIZE / 2
local gemCount = 0

for x = -half, half, GEM_SPACING do
	for z = -half, half, GEM_SPACING do
		if gemCount >= MAX_GEMS then break end

		for _ = 1, ATTEMPTS_PER_CELL do
			if gemCount >= MAX_GEMS then break end

			local ox = math.random(-GEM_JITTER, GEM_JITTER)
			local oz = math.random(-GEM_JITTER, GEM_JITTER)

			local hx = x + ox
			local hz = z + oz

			-- ✅ keep spawn hub clear
			if inSpawnHub(hx, hz) then
				continue
			end

			local h = WorldHeight.heightAt(hx, hz)

			if AVOID_ROCK and (h >= (WorldConfig.ROCK_START - ROCK_MARGIN)) then
				continue
			end

			local groundY = WorldConfig.BASE_Y + h
			local rotation = CFrame.Angles(0, math.rad(math.random(0, 360)), 0)
			local pivot = CFrame.new(hx, groundY + crystalSize.Y / 2, hz) * rotation

			if not isSpotClear(pivot, crystalSize) then
				continue
			end

			local crystal = crystalTemplate:Clone()
			crystal.Parent = gemsFolder
			crystal:PivotTo(pivot)
			anchorModel(crystal, true)

			gemCount += 1
			break
		end
	end
	if gemCount >= MAX_GEMS then break end
end

print("Spawned crystals:", gemCount)