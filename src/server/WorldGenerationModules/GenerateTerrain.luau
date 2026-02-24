--!strict
-- ServerScriptService/Server/WorldGenerationModules/GenerateTerrain.luau

local Workspace = game:GetService("Workspace")
local Terrain = Workspace.Terrain

local ServerScriptService = game:GetService("ServerScriptService")

local WorldConfig = require(ServerScriptService.Server.WorldModules.WorldConfig)
local WorldHeight = require(ServerScriptService.Server.WorldModules.WorldHeight)

export type WorldDiffs = {
	choppedTrees: {[string]: boolean},
	minedGems: {[string]: boolean},
}

export type WorldSave = {
	version: number,
	seed: number,
	diffs: WorldDiffs,
	lastSavedAt: number,
}

local GenerateTerrain = {}

local function smoothstep(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

local function fillColumn(origin: Vector3, step: number, baseY: number, wx: number, wz: number, height: number, mat: Enum.Material)
	if height <= 0 then
		return
	end
	local centerY = baseY + height / 2
	Terrain:FillBlock(
		CFrame.new(origin.X + wx, centerY, origin.Z + wz),
		Vector3.new(step, height, step),
		mat
	)
end

function GenerateTerrain.Build(_root: Folder, origin: Vector3, _rng: Random, _save: WorldSave?): ()
	-- NOTE:
	-- This generates terrain at the given origin. If you generate multiple per-player worlds in the SAME server,
	-- you are creating multiple terrain "islands" far apart. That's OK for small tests, but terrain fill is heavy.
	-- (Later we can optimize by generating only once per server, or switching to mesh islands.)

	local STEP: number = WorldConfig.STEP
	local half: number = (WorldConfig.AREA_SIZE :: number) / 2

	-- Treat AREA_SIZE as diameter => radius
	local WORLD_RADIUS: number = half

	local SEA_LEVEL: number = (WorldConfig.SEA_LEVEL :: number?) or 8
	local SEA_FLOOR: number = (WorldConfig.SEA_FLOOR :: number?) or -40
	local BEACH_WIDTH: number = (WorldConfig.BEACH_WIDTH :: number?) or 80
	local OCEAN_PADDING: number = (WorldConfig.OCEAN_PADDING :: number?) or 300

	local BASE_Y: number = (WorldConfig.BASE_Y :: number?) or 0

	-- Spawn hub flatten (local to this world)
	local SPAWN_X: number = (WorldConfig.SPAWN_CENTER_X :: number?) or 0
	local SPAWN_Z: number = (WorldConfig.SPAWN_CENTER_Z :: number?) or 0
	local FLAT_R: number = (WorldConfig.SPAWN_FLAT_RADIUS :: number?) or ((WorldConfig.SPAWN_CLEAR_RADIUS :: number?) or 70)
	local FLAT_R2: number = FLAT_R * FLAT_R

	-- plateau based on height at local spawn center (but sample heightAt in WORLD coords)
	local plateauH: number = WorldHeight.heightAt(origin.X + SPAWN_X, origin.Z + SPAWN_Z)

	local function flatBlendHeight(localX: number, localZ: number, rawH: number): number
		local dx = localX - SPAWN_X
		local dz = localZ - SPAWN_Z
		local d2 = dx * dx + dz * dz

		if d2 <= FLAT_R2 then
			return plateauH
		end

		local blendWidth = 30
		local outer = (FLAT_R + blendWidth)
		local outer2 = outer * outer

		if d2 >= outer2 then
			return rawH
		end

		local dist = math.sqrt(d2)
		local t = (dist - FLAT_R) / blendWidth
		t = smoothstep(t)

		return plateauH * (1 - t) + rawH * t
	end

	-- =========================
	-- 0) Fill ocean block for this world "island"
	-- =========================
	local oceanExtent = WORLD_RADIUS + BEACH_WIDTH + OCEAN_PADDING
	local oceanSize = Vector3.new(oceanExtent * 2, (SEA_LEVEL - SEA_FLOOR), oceanExtent * 2)
	local oceanCenterY = BASE_Y + (SEA_FLOOR + SEA_LEVEL) / 2

	Terrain:FillBlock(
		CFrame.new(origin.X, oceanCenterY, origin.Z),
		oceanSize,
		Enum.Material.Water
	)

	-- =========================
	-- 1) Generate land + beach
	-- =========================
	local minXZ = -oceanExtent
	local maxXZ = oceanExtent

	local ROCK_START: number = (WorldConfig.ROCK_START :: number?) or 60

	for lx = minXZ, maxXZ, STEP do
		for lz = minXZ, maxXZ, STEP do
			local dist = math.sqrt(lx * lx + lz * lz)

			-- Land
			if dist <= WORLD_RADIUS then
				local rawH = WorldHeight.heightAt(origin.X + lx, origin.Z + lz)
				local h = flatBlendHeight(lx, lz, rawH)

				local mat = Enum.Material.Grass
				if h > ROCK_START then
					mat = Enum.Material.Rock
				end

				fillColumn(origin, STEP, BASE_Y, lx, lz, h, mat)

			-- Beach ring
			elseif dist <= (WORLD_RADIUS + BEACH_WIDTH) then
				local t = (dist - WORLD_RADIUS) / BEACH_WIDTH
				t = smoothstep(t)

				-- sample land-edge height by projecting back to radius
				local projX = lx * (WORLD_RADIUS / dist)
				local projZ = lz * (WORLD_RADIUS / dist)

				local landEdgeH = WorldHeight.heightAt(origin.X + projX, origin.Z + projZ)
				landEdgeH = flatBlendHeight(projX, projZ, landEdgeH)

				local targetH = SEA_LEVEL - 2
				local beachH = landEdgeH * (1 - t) + targetH * t
				beachH = math.max(1, beachH)

				fillColumn(origin, STEP, BASE_Y, lx, lz, beachH, Enum.Material.Sand)
			end
		end
	end

	print(("[Terrain] Generated island at origin=(%.0f,%.0f) radius=%.0f beach=%d seaLevel=%d plateauH=%.1f flatR=%d"):format(
		origin.X, origin.Z,
		WORLD_RADIUS,
		BEACH_WIDTH,
		SEA_LEVEL,
		plateauH,
		FLAT_R
	))
end

return GenerateTerrain