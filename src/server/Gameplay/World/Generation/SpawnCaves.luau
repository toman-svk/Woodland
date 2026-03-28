--!strict
-- src/server/Gameplay/World/Generation/SpawnCaves.luau

local ServerStorage = game:GetService("ServerStorage")

local ConfigLocator = require(script.Parent.Parent.Config.ConfigLocator)
local WorldConfig = ConfigLocator.WorldConfig
local WorldHeight = ConfigLocator.WorldHeight

local SpawnCaves = {}

local function anchorModel(model: Model, anchored: boolean)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = anchored
		end
	end
end

local function getOrCreateFolder(parent: Instance, name: string): Folder
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("Folder") then
		return existing
	end
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

local function getCaveTemplate(): Model?
	local templates = ServerStorage:FindFirstChild("Templates")
	if not templates then return nil end
	local caves = templates:FindFirstChild("Caves")
	if not caves then return nil end
	local cave = caves:FindFirstChild("Cave")
	if cave and cave:IsA("Model") then
		return cave
	end
	return nil
end

local function inWorld(localX: number, localZ: number): boolean
	local WORLD_R: number = (WorldConfig.WORLD_RADIUS :: number?) or ((WorldConfig.AREA_SIZE :: number) / 2)
	local EDGE_MARGIN: number = (WorldConfig.SPAWN_EDGE_MARGIN :: number?) or 0
	local r = (WORLD_R - EDGE_MARGIN)
	return (localX * localX + localZ * localZ) <= (r * r)
end

local function tooCloseToSpawn(localX: number, localZ: number): boolean
	local spawnX: number = (WorldConfig.SPAWN_CENTER_X :: number?) or 0
	local spawnZ: number = (WorldConfig.SPAWN_CENTER_Z :: number?) or 0

	local clearR: number = (WorldConfig.SPAWN_CLEAR_RADIUS :: number?) or 90
	local minCaveDist: number = (WorldConfig.CAVE_MIN_SPAWN_DISTANCE :: number?)
		or (WorldConfig.MOUNTAIN_SPAWN_BUFFER :: number?)
		or 180

	local minR = math.max(clearR, minCaveDist)
	local dx = localX - spawnX
	local dz = localZ - spawnZ
	return (dx * dx + dz * dz) <= (minR * minR)
end

type Candidate = { x: number, z: number }

function SpawnCaves.Build(root: Folder, origin: Vector3, rng: Random, _save: any): number
	local caveTemplate = getCaveTemplate()
	if not caveTemplate then
		warn("[SpawnCaves] Missing ServerStorage/Templates/Caves/Cave in this place. Skipping caves.")
		return 0
	end

	local cavesFolder = getOrCreateFolder(root, "Caves")

	local half: number = ((WorldConfig.AREA_SIZE :: number?) or 800) / 2
	local BASE_Y: number = (WorldConfig.BASE_Y :: number?) or 0

	local spacing: number = (WorldConfig.CAVE_SPACING :: number?) or 220
	local jitter: number = (WorldConfig.CAVE_JITTER :: number?) or 70
	local caveChance: number = (WorldConfig.CAVE_CHANCE :: number?) or 0.18
	local maxCaves: number = (WorldConfig.MAX_CAVES :: number?) or 10
	local minCaves: number = (WorldConfig.MIN_CAVES :: number?) or 2 -- ✅ guarantee at least 2 if possible

	-- 1) Build candidates WITHOUT chance
	local candidates: {Candidate} = {}

	for lx = -half, half, spacing do
		for lz = -half, half, spacing do
			local px = lx + rng:NextInteger(-jitter, jitter)
			local pz = lz + rng:NextInteger(-jitter, jitter)

			if not inWorld(px, pz) then
				continue
			end
			if tooCloseToSpawn(px, pz) then
				continue
			end

			table.insert(candidates, { x = px, z = pz })
		end
	end

	-- 2) Deterministic shuffle
	for i = #candidates, 2, -1 do
		local j = rng:NextInteger(1, i)
		candidates[i], candidates[j] = candidates[j], candidates[i]
	end

	-- 3) Spawn: first guarantee minCaves, then chance-based extras up to maxCaves
	local caveCount = 0

	local function spawnAt(px: number, pz: number, idx: number)
		local h = WorldHeight.heightAt(origin.X + px, origin.Z + pz)
		local groundY = BASE_Y + h

		local cave = caveTemplate:Clone()
		local _, size = cave:GetBoundingBox()
		local rot = CFrame.Angles(0, math.rad(rng:NextInteger(0, 359)), 0)

		cave.Parent = cavesFolder
		cave.Name = ("Cave_%d"):format(idx)
		cave:SetAttribute("WorldObjectType", "Cave")

		cave:PivotTo(CFrame.new(origin.X + px, groundY + size.Y / 2, origin.Z + pz) * rot)
		anchorModel(cave, true)

		caveCount += 1
	end

	-- Spawn one cave close to the base (between clear radius and normal min distance)
	local clearR: number = (WorldConfig.SPAWN_CLEAR_RADIUS :: number?) or 90
	local minCaveDist: number = (WorldConfig.CAVE_MIN_SPAWN_DISTANCE :: number?)
		or (WorldConfig.MOUNTAIN_SPAWN_BUFFER :: number?)
		or 180
	local nearAngle = rng:NextNumber() * math.pi * 2
	local nearDist = clearR + (minCaveDist - clearR) * 0.5  -- midpoint between clear zone and normal min
	local nearX = math.cos(nearAngle) * nearDist
	local nearZ = math.sin(nearAngle) * nearDist
	spawnAt(nearX, nearZ, 0)

	-- guarantee
	local guaranteed = math.min(minCaves, maxCaves, #candidates)
	for i = 1, guaranteed do
		local c = candidates[i]
		spawnAt(c.x, c.z, i)
	end

	-- extras
	for i = guaranteed + 1, math.min(#candidates, maxCaves) do
		if rng:NextNumber() > caveChance then
			continue
		end
		local c = candidates[i]
		spawnAt(c.x, c.z, i)
		if caveCount >= maxCaves then
			break
		end
	end

	print(("[SpawnCaves] Candidates=%d Spawned=%d (chance=%.2f spacing=%d minDistFromSpawn=%d)"):format(
		#candidates,
		caveCount,
		caveChance,
		spacing,
		(WorldConfig.CAVE_MIN_SPAWN_DISTANCE :: number?) or (WorldConfig.MOUNTAIN_SPAWN_BUFFER :: number?) or 180
	))

	return caveCount
end

return SpawnCaves