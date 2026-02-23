-- ServerScriptService/WorldGeneneration/SpawnTrees.server.lua

local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")

local WorldModules = script.Parent.Parent:WaitForChild("WorldModules")
local WorldConfig = require(WorldModules:WaitForChild("WorldConfig"))
local WorldHeight = require(WorldModules:WaitForChild("WorldHeight"))

local WORLD_R = WorldConfig.WORLD_RADIUS or (WorldConfig.AREA_SIZE / 2)
local EDGE_MARGIN = WorldConfig.SPAWN_EDGE_MARGIN or 0
local WORLD_R2 = (WORLD_R - EDGE_MARGIN) * (WORLD_R - EDGE_MARGIN)

local function inWorld(x: number, z: number): boolean
	return (x*x + z*z) <= WORLD_R2
end

-- =========================
-- Forest tuning
-- =========================
local GRID_STEP_MULT = 0.6

local CLUSTER_CHANCE = 0.9
local CLUSTER_MIN = 4
local CLUSTER_MAX = 11
local CLUSTER_RADIUS_MIN = 10
local CLUSTER_RADIUS_MAX = 30

-- =========================
-- Ground placement tuning (NEW)
-- =========================
local FOOTPRINT_MULT = 0.5
-- footprint radius ~ max(size.X, size.Z) * this
-- increase slightly if trees still float at edges

local SAMPLE_COUNT = 9
-- 9 samples = center + 8 around (corners/edges)

local MAX_SLOPE_DELTA = 18
-- if (maxH - minH) > this, we skip spawning there (too steep)
-- tweak depending on your terrain scale

-- =========================
-- Ensure Generated folder structure
-- =========================
local generatedFolder = Workspace:FindFirstChild("Generated")
if not generatedFolder then
	generatedFolder = Instance.new("Folder")
	generatedFolder.Name = "Generated"
	generatedFolder.Parent = Workspace
end

local treesFolderWorkspace = generatedFolder:FindFirstChild("Trees")
if not treesFolderWorkspace then
	treesFolderWorkspace = Instance.new("Folder")
	treesFolderWorkspace.Name = "Trees"
	treesFolderWorkspace.Parent = generatedFolder
end

-- =========================
-- Spawn hub avoidance
-- =========================
local SPAWN_X = WorldConfig.SPAWN_CENTER_X or 0
local SPAWN_Z = WorldConfig.SPAWN_CENTER_Z or 0
local SPAWN_R = WorldConfig.SPAWN_CLEAR_RADIUS or 90
local SPAWN_R2 = SPAWN_R * SPAWN_R

local function inSpawnHub(x: number, z: number): boolean
	local dx = x - SPAWN_X
	local dz = z - SPAWN_Z
	return (dx * dx + dz * dz) <= SPAWN_R2
end

-- =========================
-- Tree templates
-- =========================
local treesStorageFolder = ServerStorage
	:WaitForChild("Templates")
	:WaitForChild("Trees")

local treeTemplates: {Model} = {}
for _, child in ipairs(treesStorageFolder:GetChildren()) do
	if child:IsA("Model") then
		table.insert(treeTemplates, child)
	end
end

if #treeTemplates == 0 then
	warn("No tree models found in ServerStorage/Templates/Trees")
	return
end

-- =========================
-- Utilities
-- =========================
local function anchorModel(model: Model, anchored: boolean)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = anchored
		end
	end
end

local function scaleModel(model: Model, scale: number)
	local ok = pcall(function()
		model:ScaleTo(scale)
	end)
	if not ok then
		warn("ScaleTo not available for:", model.Name)
	end
end

-- Overlap check against everything already in Generated
local overlapParams = OverlapParams.new()
overlapParams.FilterType = Enum.RaycastFilterType.Include
overlapParams.FilterDescendantsInstances = { generatedFolder }

local function isSpotClear(cframe: CFrame, size: Vector3): boolean
	local padding = Vector3.new(4, 10, 4)
	local checkSize = size + padding
	local parts = Workspace:GetPartBoundsInBox(cframe, checkSize, overlapParams)
	return #parts == 0
end

local function randomScale(): number
	local minS = WorldConfig.TREE_SCALE_MIN or 1
	local baseMaxS = WorldConfig.TREE_SCALE_MAX or 1.5
	local maxS = baseMaxS * 1.5 -- bigger trees
	return minS + (maxS - minS) * math.random()
end

local function clearTreeAttributes(tree: Instance)
	tree:SetAttribute("HP", nil)
	tree:SetAttribute("MaxHP", nil)
	tree:SetAttribute("Broken", nil)
	tree:SetAttribute("Wiggling", nil)
end

-- =========================
-- NEW: Lowest-ground sampling for better slope placement
-- =========================
local function getLowestGroundY(px: number, pz: number, footprintRadius: number): (number, number, number)
	-- returns: minH, maxH, centerH (all are "heightAt" values, NOT including BASE_Y)
	local centerH = WorldHeight.heightAt(px, pz)
	local minH = centerH
	local maxH = centerH

	if footprintRadius <= 0 then
		return minH, maxH, centerH
	end

	-- 8 surrounding points + center (SAMPLE_COUNT=9)
	local r = footprintRadius
	local offsets = {
		Vector2.new( r,  0),
		Vector2.new(-r,  0),
		Vector2.new( 0,  r),
		Vector2.new( 0, -r),

		Vector2.new( r,  r),
		Vector2.new( r, -r),
		Vector2.new(-r,  r),
		Vector2.new(-r, -r),
	}

	for _, off in ipairs(offsets) do
		local h = WorldHeight.heightAt(px + off.X, pz + off.Y)
		if h < minH then minH = h end
		if h > maxH then maxH = h end
	end

	return minH, maxH, centerH
end

local function trySpawnTreeAt(px: number, pz: number): boolean

	if not inWorld(px, pz) then
		return false
	end

	if inSpawnHub(px, pz) then
		return false
	end

	-- quick reject: center height too rocky
	local centerH = WorldHeight.heightAt(px, pz)
	if centerH >= (WorldConfig.ROCK_START - 5) then
		return false
	end

	local template = treeTemplates[math.random(1, #treeTemplates)]
	local tree = template:Clone()
	tree.Parent = treesFolderWorkspace

	CollectionService:AddTag(tree, "Tree")
	clearTreeAttributes(tree)

	anchorModel(tree, true)

	local scale = randomScale()
	scaleModel(tree, scale)

	local _, size = tree:GetBoundingBox()

	-- compute footprint from size
	local footprintRadius = math.max(size.X, size.Z) * FOOTPRINT_MULT

	-- sample terrain: use LOWEST so trunk doesn't float
	local minH, maxH, _ = getLowestGroundY(px, pz, footprintRadius)

	-- reject too-steep slopes so trees don't look ridiculous
	if (maxH - minH) > MAX_SLOPE_DELTA then
		tree:Destroy()
		return false
	end

	local groundY = (WorldConfig.BASE_Y + minH)

	local rotation = CFrame.Angles(0, math.rad(math.random(0, 360)), 0)
	local pivot = CFrame.new(px, groundY + size.Y / 2, pz) * rotation

	if not isSpotClear(pivot, size) then
		tree:Destroy()
		return false
	end

	tree:PivotTo(pivot)
	return true
end

-- =========================
-- Spawn logic (grid + clusters)
-- =========================
local half = WorldConfig.AREA_SIZE / 2
local treeCount = 0

local baseSpacing = WorldConfig.TREE_SPACING
local step = math.max(4, math.floor(baseSpacing * GRID_STEP_MULT))

for x = -half, half, step do
	for z = -half, half, step do
		if treeCount >= WorldConfig.MAX_TREES then break end

		if math.random() < WorldConfig.TREE_CHANCE then
			local px = x + math.random(-8, 8)
			local pz = z + math.random(-8, 8)

			if trySpawnTreeAt(px, pz) then
				treeCount += 1
				if treeCount >= WorldConfig.MAX_TREES then break end

				if math.random() < CLUSTER_CHANCE then
					local extras = math.random(CLUSTER_MIN, CLUSTER_MAX)
					local radius = math.random(CLUSTER_RADIUS_MIN, CLUSTER_RADIUS_MAX)

					for _ = 1, extras do
						if treeCount >= WorldConfig.MAX_TREES then break end

						local angle = math.random() * math.pi * 2
						local r = radius * math.sqrt(math.random())
						local cx = px + math.cos(angle) * r + math.random(-4, 4)
						local cz = pz + math.sin(angle) * r + math.random(-4, 4)

						if trySpawnTreeAt(cx, cz) then
							treeCount += 1
						end
					end
				end
			end
		end
	end

	if treeCount >= WorldConfig.MAX_TREES then break end
end

print("Spawned trees:", treeCount)