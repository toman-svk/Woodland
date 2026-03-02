--!strict
-- src/server/Gameplay/World/Generation/SpawnGems.luau

local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local ConfigLocator = require(script.Parent.Parent.Config:WaitForChild("ConfigLocator"))
local WorldConfig = ConfigLocator.WorldConfig
local WorldHeight = ConfigLocator.WorldHeight

local SpawnGems = {}

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

local function anchorModel(model: Model, anchored: boolean)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = anchored
		end
	end
end

local function getModelSize(model: Model): Vector3
	local _, s = model:GetBoundingBox()
	return s
end

local function getModelPosition(model: Model): Vector3?
	local pp = model.PrimaryPart
	if pp then
		return pp.Position
	end
	local anyPart = model:FindFirstChildWhichIsA("BasePart", true)
	if anyPart then
		return anyPart.Position
	end
	return nil
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

-- ✅ Gem spawning around caves tuning
local MIN_PER_CAVE = 2
local MAX_PER_CAVE = 5

local RING_MIN = 18
local RING_MAX = 45

-- ✅ Make crystals smaller
local SCALE_MIN = 0.45
local SCALE_MAX = 0.70

local OVERLAP_PADDING = Vector3.new(4, 10, 4)

local function randomInRing(rng: Random): number
	-- uniform area distribution in ring
	local t = rng:NextNumber()
	local r2min = RING_MIN * RING_MIN
	local r2max = RING_MAX * RING_MAX
	return math.sqrt(r2min + (r2max - r2min) * t)
end

function SpawnGems.Build(root: Folder, origin: Vector3, rng: Random, _save: any): number
	local cavesFolderInst = root:FindFirstChild("Caves")
	if not (cavesFolderInst and cavesFolderInst:IsA("Folder")) then
		warn("[SpawnGems] No Caves folder under world root. Make sure SpawnCaves runs before SpawnGems.")
		return 0
	end
	local cavesFolder: Folder = cavesFolderInst

	local gemsFolder = getOrCreateFolder(root, "Gems")

	-- Template
	local templates = mustFolder(ServerStorage, "Templates")
	local gemsTemplates = mustFolder(templates, "Gems")
	local crystalTemplate = mustModel(gemsTemplates, "Crystal")

	-- Overlap check against this world root (NOT global)
	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Include
	overlapParams.FilterDescendantsInstances = { root }

	local function isSpotClear(cframe: CFrame, size: Vector3): boolean
		local checkSize = size + OVERLAP_PADDING
		local parts = Workspace:GetPartBoundsInBox(cframe, checkSize, overlapParams)
		return #parts == 0
	end

	local function trySpawnCrystalAt(localX: number, localZ: number): boolean
		if not inWorld(localX, localZ) then return false end
		if inSpawnHub(localX, localZ) then return false end

		local worldX = origin.X + localX
		local worldZ = origin.Z + localZ

		local h = WorldHeight.heightAt(worldX, worldZ)
		local baseY: number = (WorldConfig.BASE_Y :: number?) or 0
		local groundY = baseY + h

		local crystal = crystalTemplate:Clone()

		-- scale first (size changes)
		local scale = SCALE_MIN + (SCALE_MAX - SCALE_MIN) * rng:NextNumber()
		pcall(function()
			crystal:ScaleTo(scale)
		end)

		local size = getModelSize(crystal)
		local rotation = CFrame.Angles(0, math.rad(rng:NextInteger(0, 359)), 0)
		local pivot = CFrame.new(worldX, groundY + size.Y / 2, worldZ) * rotation

		if not isSpotClear(pivot, size) then
			crystal:Destroy()
			return false
		end

		crystal.Parent = gemsFolder
		crystal:PivotTo(pivot)
		anchorModel(crystal, true)

		return true
	end

	local total = 0

	for _, cave in ipairs(cavesFolder:GetChildren()) do
		if not cave:IsA("Model") then
			continue
		end

		local cpos = getModelPosition(cave)
		if not cpos then
			continue
		end

		-- Convert cave world pos -> local pos for this island/world
		local caveLocalX = cpos.X - origin.X
		local caveLocalZ = cpos.Z - origin.Z

		local want = rng:NextInteger(MIN_PER_CAVE, MAX_PER_CAVE)
		local spawned = 0
		local tries = 0
		local maxTries = want * 10

		while spawned < want and tries < maxTries do
			tries += 1

			local angle = rng:NextNumber() * math.pi * 2
			local r = randomInRing(rng)

			local localX = caveLocalX + math.cos(angle) * r + rng:NextInteger(-4, 4)
			local localZ = caveLocalZ + math.sin(angle) * r + rng:NextInteger(-4, 4)

			if trySpawnCrystalAt(localX, localZ) then
				spawned += 1
				total += 1
			end
		end
	end

	print("[SpawnGems] Spawned crystals (near caves):", total)
	return total
end

return SpawnGems