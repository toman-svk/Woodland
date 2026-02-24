--!strict
-- ServerScriptService/Server/WorldGenerationModules/SpawnGems.luau

local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")
local ServerScriptService = game:GetService("ServerScriptService")

-- ✅ STATIC requires (kills 1012 warnings)
local WorldConfig = require(ServerScriptService.Server.WorldModules.WorldConfig)
local WorldHeight = require(ServerScriptService.Server.WorldModules.WorldHeight)

local SpawnGems = {}

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

-- Circular world bounds
local WORLD_R = WorldConfig.WORLD_RADIUS or ((WorldConfig.AREA_SIZE or 800) / 2)
local EDGE_MARGIN = WorldConfig.SPAWN_EDGE_MARGIN or 0
local WORLD_R2 = (WORLD_R - EDGE_MARGIN) * (WORLD_R - EDGE_MARGIN)

local function inWorld(x: number, z: number): boolean
	return (x * x + z * z) <= WORLD_R2
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

local function randomInRing(): number
	-- uniform area distribution in ring
	local t = math.random()
	local r2min = RING_MIN * RING_MIN
	local r2max = RING_MAX * RING_MAX
	return math.sqrt(r2min + (r2max - r2min) * t)
end

function SpawnGems.Run(): number
	local generatedFolder = getGenerated()

	local cavesFolderInst = generatedFolder:FindFirstChild("Caves")
	if not (cavesFolderInst and cavesFolderInst:IsA("Folder")) then
		warn("[SpawnGems] No Generated/Caves folder found. Make sure SpawnCaves runs before SpawnGems.")
		return 0
	end
	local cavesFolder: Folder = cavesFolderInst

	local gemsFolder = getOrCreateFolder(generatedFolder, "Gems")

	-- Template
	local crystalTemplate = ServerStorage
		:WaitForChild("Templates")
		:WaitForChild("Gems")
		:WaitForChild("Crystal") :: Model

	-- Overlap check against everything already in Generated
	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Include
	overlapParams.FilterDescendantsInstances = { generatedFolder }

	local function isSpotClear(cframe: CFrame, size: Vector3): boolean
		local checkSize = size + OVERLAP_PADDING
		local parts = Workspace:GetPartBoundsInBox(cframe, checkSize, overlapParams)
		return #parts == 0
	end

	local function trySpawnCrystalAt(hx: number, hz: number): boolean
		if not inWorld(hx, hz) then return false end
		if inSpawnHub(hx, hz) then return false end

		local h = WorldHeight.heightAt(hx, hz)
		local groundY = (WorldConfig.BASE_Y or 0) + h

		local crystal = crystalTemplate:Clone()

		-- scale first (size changes)
		local scale = SCALE_MIN + (SCALE_MAX - SCALE_MIN) * math.random()
		pcall(function()
			crystal:ScaleTo(scale)
		end)

		local size = getModelSize(crystal)
		local rotation = CFrame.Angles(0, math.rad(math.random(0, 360)), 0)
		local pivot = CFrame.new(hx, groundY + size.Y / 2, hz) * rotation

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

		local want = math.random(MIN_PER_CAVE, MAX_PER_CAVE)
		local spawned = 0
		local tries = 0
		local maxTries = want * 8

		while spawned < want and tries < maxTries do
			tries += 1

			local angle = math.random() * math.pi * 2
			local r = randomInRing()

			local hx = cpos.X + math.cos(angle) * r + math.random(-4, 4)
			local hz = cpos.Z + math.sin(angle) * r + math.random(-4, 4)

			if trySpawnCrystalAt(hx, hz) then
				spawned += 1
				total += 1
			end
		end
	end

	print("[SpawnGems] Spawned crystals (near caves):", total)
	return total
end

return SpawnGems