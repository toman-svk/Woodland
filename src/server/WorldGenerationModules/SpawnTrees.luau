--!strict
-- ServerScriptService/Server/WorldGenerationModules/SpawnTrees.luau

local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")
local ServerScriptService = game:GetService("ServerScriptService")

-- ✅ STATIC requires (kills 1012 warnings)
local WorldConfig = require(ServerScriptService.Server.WorldModules.WorldConfig)
local WorldHeight = require(ServerScriptService.Server.WorldModules.WorldHeight)

local SpawnTrees = {}

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

local function getGenerated(): Folder
	return getOrCreateFolder(Workspace, "Generated")
end

-- Circular world bounds
local WORLD_R = WorldConfig.WORLD_RADIUS or ((WorldConfig.AREA_SIZE or 800) / 2)
local EDGE_MARGIN = WorldConfig.SPAWN_EDGE_MARGIN or 0
local WORLD_R2 = (WORLD_R - EDGE_MARGIN) * (WORLD_R - EDGE_MARGIN)

local function inWorld(x: number, z: number): boolean
	return (x * x + z * z) <= WORLD_R2
end

-- Spawn hub avoidance
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
-- Forest tuning (dense)
-- =========================
local GRID_STEP_MULT = 0.38

local CLUSTER_CHANCE = 0.95
local CLUSTER_MIN = 6
local CLUSTER_MAX = 16
local CLUSTER_RADIUS_MIN = 8
local CLUSTER_RADIUS_MAX = 22

-- =========================
-- Placement tuning
-- =========================
local FOOTPRINT_MULT = 0.35
local MAX_SLOPE_DELTA = 18

-- =========================
-- Templates (weighted)
-- =========================
local treesStorageFolder = ServerStorage
	:WaitForChild("Templates")
	:WaitForChild("Trees")

local function mustModel(name: string): Model
	local inst = treesStorageFolder:WaitForChild(name)
	if not inst:IsA("Model") then
		error(("Template %s is not a Model (got %s)"):format(name, inst.ClassName))
	end
	return inst
end

local weightedTrees = {
	{ model = mustModel("Tree1"), weight = 60 },
	{ model = mustModel("Tree2"), weight = 20 },
	{ model = mustModel("Tree3"), weight = 10 },
	{ model = mustModel("Tree4"), weight = 10 },
}

local totalWeight = 0
for _, entry in ipairs(weightedTrees) do
	totalWeight += entry.weight
end

local function pickTreeTemplate(): Model
	local r = math.random(1, totalWeight)
	local acc = 0
	for _, entry in ipairs(weightedTrees) do
		acc += entry.weight
		if r <= acc then
			return entry.model
		end
	end
	return weightedTrees[#weightedTrees].model
end

local function anchorModel(model: Model, anchored: boolean)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = anchored
		end
	end
end

local function scaleModel(model: Model, scale: number)
	pcall(function()
		model:ScaleTo(scale)
	end)
end

local function randomScale(): number
	local minS = WorldConfig.TREE_SCALE_MIN or 1
	local baseMaxS = WorldConfig.TREE_SCALE_MAX or 1.5
	local maxS = baseMaxS * 1.5
	return minS + (maxS - minS) * math.random()
end

local function clearTreeAttributes(tree: Instance)
	tree:SetAttribute("HP", nil)
	tree:SetAttribute("MaxHP", nil)
	tree:SetAttribute("Broken", nil)
	tree:SetAttribute("Wiggling", nil)
end

local function getLowestGroundY(px: number, pz: number, footprintRadius: number): (number, number)
	local centerH = WorldHeight.heightAt(px, pz)
	local minH = centerH
	local maxH = centerH

	if footprintRadius > 0 then
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
	end

	return minH, maxH
end

function SpawnTrees.Run(): number
	local generatedFolder = getGenerated()
	local treesFolder = getOrCreateFolder(generatedFolder, "Trees")

	-- Overlap check against everything already in Generated
	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Include
	overlapParams.FilterDescendantsInstances = { generatedFolder }

	local function isSpotClear(cframe: CFrame, size: Vector3): boolean
		local padding = Vector3.new(1.5, 10, 1.5)
		local checkSize = size + padding
		local parts = Workspace:GetPartBoundsInBox(cframe, checkSize, overlapParams)
		return #parts == 0
	end

	local function trySpawnTreeAt(px: number, pz: number): boolean
		if not inWorld(px, pz) then return false end
		if inSpawnHub(px, pz) then return false end

		-- avoid rocky heights
		local centerH = WorldHeight.heightAt(px, pz)
		if centerH >= ((WorldConfig.ROCK_START or 60) - 5) then
			return false
		end

		local template = pickTreeTemplate()
		local tree = template:Clone()
		tree.Parent = treesFolder

		CollectionService:AddTag(tree, "Tree")
		clearTreeAttributes(tree)
		anchorModel(tree, true)

		local scale = randomScale()
		scaleModel(tree, scale)

		local _, size = tree:GetBoundingBox()
		local footprintRadius = math.max(size.X, size.Z) * FOOTPRINT_MULT

		local minH, maxH = getLowestGroundY(px, pz, footprintRadius)
		if (maxH - minH) > MAX_SLOPE_DELTA then
			tree:Destroy()
			return false
		end

		local groundY = (WorldConfig.BASE_Y or 0) + minH
		local rot = CFrame.Angles(0, math.rad(math.random(0, 360)), 0)
		local pivot = CFrame.new(px, groundY + size.Y / 2, pz) * rot

		if not isSpotClear(pivot, size) then
			tree:Destroy()
			return false
		end

		tree:PivotTo(pivot)
		return true
	end

	-- Spawn loop
	local half = (WorldConfig.AREA_SIZE or 800) / 2
	local treeCount = 0
	local maxTrees = WorldConfig.MAX_TREES or 2000

	local baseSpacing = WorldConfig.TREE_SPACING or 6
	local step = math.max(2, math.floor(baseSpacing * GRID_STEP_MULT))
	local chance = WorldConfig.TREE_CHANCE or 0.6

	for x = -half, half, step do
		for z = -half, half, step do
			if treeCount >= maxTrees then break end

			if math.random() < chance then
				local px = x + math.random(-8, 8)
				local pz = z + math.random(-8, 8)

				if trySpawnTreeAt(px, pz) then
					treeCount += 1
					if treeCount >= maxTrees then break end

					if math.random() < CLUSTER_CHANCE then
						local extras = math.random(CLUSTER_MIN, CLUSTER_MAX)
						local radius = math.random(CLUSTER_RADIUS_MIN, CLUSTER_RADIUS_MAX)

						for _ = 1, extras do
							if treeCount >= maxTrees then break end

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
		if treeCount >= maxTrees then break end
	end

	print("[SpawnTrees] Spawned trees:", treeCount)
	return treeCount
end

return SpawnTrees