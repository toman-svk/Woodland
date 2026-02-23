-- ServerScriptService/WorldGeneneration/GenerateTerrain.server.lua

local Terrain = workspace.Terrain

local WorldModules = script.Parent.Parent:WaitForChild("WorldModules")
local WorldConfig = require(WorldModules:WaitForChild("WorldConfig"))
local WorldHeight = require(WorldModules:WaitForChild("WorldHeight"))

Terrain:Clear()

local STEP = WorldConfig.STEP
local half = WorldConfig.AREA_SIZE / 2

-- Treat AREA_SIZE as "diameter" of the playable world
local WORLD_RADIUS = half

local SEA_LEVEL = WorldConfig.SEA_LEVEL or 8
local SEA_FLOOR = WorldConfig.SEA_FLOOR or -40
local BEACH_WIDTH = WorldConfig.BEACH_WIDTH or 80
local OCEAN_PADDING = WorldConfig.OCEAN_PADDING or 300

-- Spawn hub flatten settings
local SPAWN_X = WorldConfig.SPAWN_CENTER_X or 0
local SPAWN_Z = WorldConfig.SPAWN_CENTER_Z or 0
local FLAT_R = WorldConfig.SPAWN_FLAT_RADIUS or (WorldConfig.SPAWN_CLEAR_RADIUS or 70)
local FLAT_R2 = FLAT_R * FLAT_R

-- Pick a stable plateau height (based on your terrain height at spawn center)
local plateauH = WorldHeight.heightAt(SPAWN_X, SPAWN_Z)

local function smoothstep(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

local function flatBlendHeight(x: number, z: number, rawH: number): number
	local dx = x - SPAWN_X
	local dz = z - SPAWN_Z
	local d2 = dx*dx + dz*dz

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
-- 0) Fill big ocean volume first
-- =========================
local oceanExtent = WORLD_RADIUS + BEACH_WIDTH + OCEAN_PADDING
local oceanSize = Vector3.new(oceanExtent * 2, (SEA_LEVEL - SEA_FLOOR), oceanExtent * 2)

-- center the water block between sea floor and sea level
local oceanCenterY = WorldConfig.BASE_Y + (SEA_FLOOR + SEA_LEVEL) / 2

Terrain:FillBlock(
	CFrame.new(0, oceanCenterY, 0),
	oceanSize,
	Enum.Material.Water
)

-- =========================
-- 1) Generate land + beach
-- =========================
local function fillColumn(x: number, z: number, height: number, mat: Enum.Material)
	-- height is "thickness" from base up (same as your existing logic)
	if height <= 0 then
		return
	end
	local centerY = WorldConfig.BASE_Y + height / 2
	Terrain:FillBlock(
		CFrame.new(x, centerY, z),
		Vector3.new(STEP, height, STEP),
		mat
	)
end

-- iterate a square that covers land + beach ring
local minXZ = -oceanExtent
local maxXZ = oceanExtent

for x = minXZ, maxXZ, STEP do
	for z = minXZ, maxXZ, STEP do
		local dist = math.sqrt(x*x + z*z)

		-- Inside the world radius => normal land
		if dist <= WORLD_RADIUS then
			local rawH = WorldHeight.heightAt(x, z)
			local h = flatBlendHeight(x, z, rawH)

			local mat = Enum.Material.Grass
			if h > WorldConfig.ROCK_START then
				mat = Enum.Material.Rock
			end

			fillColumn(x, z, h, mat)

		-- Beach ring: WORLD_RADIUS .. WORLD_RADIUS+BEACH_WIDTH
		elseif dist <= (WORLD_RADIUS + BEACH_WIDTH) then
			-- t=0 at inner edge, t=1 at ocean edge
			local t = (dist - WORLD_RADIUS) / BEACH_WIDTH
			t = smoothstep(t)

			-- Start from the land edge height and go down to sea level
			local landEdgeH = WorldHeight.heightAt(x * (WORLD_RADIUS / dist), z * (WORLD_RADIUS / dist))
			landEdgeH = flatBlendHeight(
				x * (WORLD_RADIUS / dist),
				z * (WORLD_RADIUS / dist),
				landEdgeH
			)

			-- target height at beach outer edge: just under sea level so water covers it slightly
			local targetH = SEA_LEVEL - 2

			-- beach height blends from landEdgeH -> targetH
			local beachH = landEdgeH * (1 - t) + targetH * t

			-- Clamp so you don't get weird negative columns
			beachH = math.max(1, beachH)

			fillColumn(x, z, beachH, Enum.Material.Sand)
		end
	end
end

print(("[Terrain] Generated land radius=%.0f, beach=%d, seaLevel=%d, plateauH=%.1f flatR=%d"):format(
	WORLD_RADIUS,
	BEACH_WIDTH,
	SEA_LEVEL,
	plateauH,
	FLAT_R
))