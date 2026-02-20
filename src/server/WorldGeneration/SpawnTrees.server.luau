-- ServerScriptService/WorldGeneneration/SpawnTrees.server.lua

local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")

local WorldModules = script.Parent.Parent:WaitForChild("WorldModules")
local WorldConfig = require(WorldModules:WaitForChild("WorldConfig"))
local WorldHeight = require(WorldModules:WaitForChild("WorldHeight"))

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

local function inSpawnHub(x, z)
	local dx = x - SPAWN_X
	local dz = z - SPAWN_Z
	return (dx*dx + dz*dz) <= SPAWN_R2
end

-- =========================
-- Tree templates
-- =========================
local treesStorageFolder = ServerStorage
	:WaitForChild("Templates")
	:WaitForChild("Trees")

local treeTemplates = {}
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
local function anchorModel(model, anchored)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = anchored
		end
	end
end

local function scaleModel(model, scale)
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

local function isSpotClear(cframe: CFrame, size: Vector3)
	local padding = Vector3.new(6, 12, 6)
	local checkSize = size + padding
	local parts = Workspace:GetPartBoundsInBox(cframe, checkSize, overlapParams)
	return #parts == 0
end

-- =========================
-- Spawn logic
-- =========================
local half = WorldConfig.AREA_SIZE / 2
local treeCount = 0

for x = -half, half, WorldConfig.TREE_SPACING do
	for z = -half, half, WorldConfig.TREE_SPACING do
		if treeCount >= WorldConfig.MAX_TREES then break end

		if math.random() < WorldConfig.TREE_CHANCE then

			-- Random offset so grid is not visible
			local offsetX = math.random(-8, 8)
			local offsetZ = math.random(-8, 8)

			local px = x + offsetX
			local pz = z + offsetZ

			-- ❌ Keep spawn hub clear
			if inSpawnHub(px, pz) then
				continue
			end

			local h = WorldHeight.heightAt(px, pz)

			-- ❌ Avoid rocky peaks
			if h >= WorldConfig.ROCK_START - 5 then
				continue
			end

			local template = treeTemplates[math.random(1, #treeTemplates)]
			local tree = template:Clone()

			tree.Parent = treesFolderWorkspace
			-- Tag + HP
			CollectionService:AddTag(tree, "Tree")
			tree:SetAttribute("MaxHP", 5)  -- tweak
			tree:SetAttribute("HP", 5)
			
			-- Anchor + scale
			anchorModel(tree, true)

			-- Random scaling
			local minS = WorldConfig.TREE_SCALE_MIN or 1
			local maxS = WorldConfig.TREE_SCALE_MAX or 1.5
			local scale = minS + (maxS - minS) * math.random()
			scaleModel(tree, scale)

			local _, size = tree:GetBoundingBox()
			local groundY = WorldConfig.BASE_Y + h

			local rotation = CFrame.Angles(0, math.rad(math.random(0, 360)), 0)
			local pivot = CFrame.new(px, groundY + size.Y/2, pz) * rotation

			-- ❌ Avoid overlapping caves/gems/trees
			if not isSpotClear(pivot, size) then
				tree:Destroy()
				continue
			end

			tree:PivotTo(pivot)
			treeCount += 1
		end
	end

	if treeCount >= WorldConfig.MAX_TREES then break end
end

print("Spawned trees:", treeCount)