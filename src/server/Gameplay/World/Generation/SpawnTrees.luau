--!strict
-- src/server/Gameplay/World/Generation/SpawnTrees.luau

local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")

local ConfigLocator = require(script.Parent.Parent.Config:WaitForChild("ConfigLocator"))
local WorldConfig = ConfigLocator.WorldConfig
local WorldHeight = ConfigLocator.WorldHeight

local SpawnTrees = {}

local function mustFolder(parent: Instance, name: string): Folder
	local inst = parent:WaitForChild(name)
	if not inst:IsA("Folder") then
		error(("Expected %s under %s to be Folder, got %s"):format(name, parent:GetFullName(), inst.ClassName))
	end
	return inst
end

local function mustModel(parent: Instance, name: string): Model
	local inst = parent:WaitForChild(name)
	if not inst:IsA("Model") then
		error(("Expected %s under %s to be Model, got %s"):format(name, parent:GetFullName(), inst.ClassName))
	end
	return inst
end

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

-- Spawn hub avoidance (LOCAL coords)
local function inSpawnHub(localX: number, localZ: number): boolean
	local SPAWN_X: number = (WorldConfig.SPAWN_CENTER_X :: number?) or 0
	local SPAWN_Z: number = (WorldConfig.SPAWN_CENTER_Z :: number?) or 0
	local SPAWN_R: number = (WorldConfig.SPAWN_CLEAR_RADIUS :: number?) or 90
	local dx = localX - SPAWN_X
	local dz = localZ - SPAWN_Z
	return (dx * dx + dz * dz) <= (SPAWN_R * SPAWN_R)
end

local function inWorld(localX: number, localZ: number): boolean
	local areaSize: number = (WorldConfig.AREA_SIZE :: number?) or 800
	local WORLD_R: number = (WorldConfig.WORLD_RADIUS :: number?) or (areaSize / 2)
	local EDGE_MARGIN: number = (WorldConfig.SPAWN_EDGE_MARGIN :: number?) or 0
	local r = WORLD_R - EDGE_MARGIN
	return (localX * localX + localZ * localZ) <= (r * r)
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
local treesStorageFolder = mustFolder(mustFolder(ServerStorage, "Templates"), "Trees")

local weightedTrees = {
	{ model = mustModel(treesStorageFolder, "Tree1"), weight = 60 },
	{ model = mustModel(treesStorageFolder, "Tree2"), weight = 20 },
	{ model = mustModel(treesStorageFolder, "Tree3"), weight = 10 },
	{ model = mustModel(treesStorageFolder, "Tree4"), weight = 10 },
}

local totalWeight = 0
for _, entry in ipairs(weightedTrees) do
	totalWeight += entry.weight
end

local function pickTreeTemplate(rng: Random): Model
	local r = rng:NextInteger(1, totalWeight)
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

local function randomScale(rng: Random): number
	local minS: number = (WorldConfig.TREE_SCALE_MIN :: number?) or 1
	local baseMaxS: number = (WorldConfig.TREE_SCALE_MAX :: number?) or 1.5
	local maxS = baseMaxS * 1.5
	return minS + (maxS - minS) * rng:NextNumber()
end

local function clearTreeAttributes(tree: Instance)
	tree:SetAttribute("HP", nil)
	tree:SetAttribute("MaxHP", nil)
	tree:SetAttribute("Broken", nil)
	tree:SetAttribute("Wiggling", nil)
end

local function getLowestGroundY(worldX: number, worldZ: number, footprintRadius: number): (number, number)
	local centerH = WorldHeight.heightAt(worldX, worldZ)
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
			local h = WorldHeight.heightAt(worldX + off.X, worldZ + off.Y)
			if h < minH then minH = h end
			if h > maxH then maxH = h end
		end
	end

	return minH, maxH
end

function SpawnTrees.Build(root: Folder, origin: Vector3, rng: Random, _save: any): number
	local treesFolder = getOrCreateFolder(root, "Trees")

	-- Overlap check against this world root (NOT global)
	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Include
	overlapParams.FilterDescendantsInstances = { root }

	local function isSpotClear(cframe: CFrame, size: Vector3): boolean
		local padding = Vector3.new(1.5, 10, 1.5)
		local checkSize = size + padding
		local parts = Workspace:GetPartBoundsInBox(cframe, checkSize, overlapParams)
		return #parts == 0
	end

	local function trySpawnTreeAt(localX: number, localZ: number): boolean
		if not inWorld(localX, localZ) then return false end
		if inSpawnHub(localX, localZ) then return false end

		local worldX = origin.X + localX
		local worldZ = origin.Z + localZ

		-- avoid rocky heights
		local centerH = WorldHeight.heightAt(worldX, worldZ)
		local rockStart: number = (WorldConfig.ROCK_START :: number?) or 60
		if centerH >= (rockStart - 5) then
			return false
		end

		local template = pickTreeTemplate(rng)
		local tree = template:Clone()
		tree.Parent = treesFolder

		CollectionService:AddTag(tree, "Tree")
		clearTreeAttributes(tree)
		anchorModel(tree, true)

		local scale = randomScale(rng)
		scaleModel(tree, scale)

		local _, size = tree:GetBoundingBox()
		local footprintRadius = math.max(size.X, size.Z) * FOOTPRINT_MULT

		local minH, maxH = getLowestGroundY(worldX, worldZ, footprintRadius)
		if (maxH - minH) > MAX_SLOPE_DELTA then
			tree:Destroy()
			return false
		end

		local baseY: number = (WorldConfig.BASE_Y :: number?) or 0
		local groundY = baseY + minH

		local rot = CFrame.Angles(0, math.rad(rng:NextInteger(0, 359)), 0)
		local pivot = CFrame.new(worldX, groundY + size.Y / 2, worldZ) * rot

		if not isSpotClear(pivot, size) then
			tree:Destroy()
			return false
		end

		tree:PivotTo(pivot)
		return true
	end

	-- Spawn loop (LOCAL coords)
	local half = (((WorldConfig.AREA_SIZE :: number?) or 800) / 2)
	local treeCount = 0
	local maxTrees: number = (WorldConfig.MAX_TREES :: number?) or 2000

	local baseSpacing: number = (WorldConfig.TREE_SPACING :: number?) or 6
	local step = math.max(2, math.floor(baseSpacing * GRID_STEP_MULT))
	local chance: number = (WorldConfig.TREE_CHANCE :: number?) or 0.6

	for x = -half, half, step do
		for z = -half, half, step do
			if treeCount >= maxTrees then break end

			if rng:NextNumber() < chance then
				local localX = x + rng:NextInteger(-8, 8)
				local localZ = z + rng:NextInteger(-8, 8)

				if trySpawnTreeAt(localX, localZ) then
					treeCount += 1
					if treeCount >= maxTrees then break end

					if rng:NextNumber() < CLUSTER_CHANCE then
						local extras = rng:NextInteger(CLUSTER_MIN, CLUSTER_MAX)
						local radius = rng:NextInteger(CLUSTER_RADIUS_MIN, CLUSTER_RADIUS_MAX)

						for _ = 1, extras do
							if treeCount >= maxTrees then break end

							local angle = rng:NextNumber() * math.pi * 2
							local r = radius * math.sqrt(rng:NextNumber())

							local cx = localX + math.cos(angle) * r + rng:NextInteger(-4, 4)
							local cz = localZ + math.sin(angle) * r + rng:NextInteger(-4, 4)

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