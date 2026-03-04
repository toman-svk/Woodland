--!strict
-- src/server/Gameplay/World/Generation/TerrainGenerator.luau

local Workspace = game:GetService("Workspace")
local Terrain = Workspace.Terrain

local ConfigLocator = require(script.Parent.Parent.Config:WaitForChild("ConfigLocator"))
local WorldConfig = ConfigLocator.WorldConfig
local WorldHeight = ConfigLocator.WorldHeight

local TerrainGenerator = {}

local function smoothstep(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

local function fillColumn(origin: Vector3, step: number, baseY: number, localX: number, localZ: number, height: number, mat: Enum.Material)
	if height <= 0 then
		return
	end
	local centerY = baseY + height / 2
	Terrain:FillBlock(
		CFrame.new(origin.X + localX, centerY, origin.Z + localZ),
		Vector3.new(step, height, step),
		mat
	)
end

function TerrainGenerator.Build(_root: Folder, origin: Vector3, _rng: Random, _save: any): ()
	-- Use a smaller voxel step for smoother slopes
	local STEP: number = (WorldConfig.TERRAIN_STEP :: number?) or 4
	STEP = math.clamp(STEP, 2, 8)

	local areaSize: number = (WorldConfig.AREA_SIZE :: number?) or 800
	local half: number = areaSize / 2
	local WORLD_RADIUS: number = half

	local SEA_LEVEL: number = (WorldConfig.SEA_LEVEL :: number?) or 8
	local SEA_FLOOR: number = (WorldConfig.SEA_FLOOR :: number?) or -40
	local BEACH_WIDTH: number = (WorldConfig.BEACH_WIDTH :: number?) or 80
	local OCEAN_PADDING: number = (WorldConfig.OCEAN_PADDING :: number?) or 300

	local BASE_Y: number = (WorldConfig.BASE_Y :: number?) or 0

	local SPAWN_X: number = (WorldConfig.SPAWN_CENTER_X :: number?) or 0
	local SPAWN_Z: number = (WorldConfig.SPAWN_CENTER_Z :: number?) or 0

	-- ✅ NEW: dedicated hub radius (flat grass)
	local HUB_R: number =
		(WorldConfig.SPAWN_HUB_RADIUS :: number?)
		or (WorldConfig.SPAWN_FLAT_RADIUS :: number?)
		or ((WorldConfig.SPAWN_CLEAR_RADIUS :: number?) or 70)

	local HUB_R2: number = HUB_R * HUB_R

	-- Slope blending ring outside hub so it doesn't become a hard cliff
	local HUB_BLEND: number = (WorldConfig.SPAWN_HUB_BLEND_WIDTH :: number?) or 40
	local HUB_OUTER: number = HUB_R + HUB_BLEND
	local HUB_OUTER2: number = HUB_OUTER * HUB_OUTER

	-- plateau height sampled in WORLD coords at spawn center
	local plateauH: number
do
	local fixed = WorldConfig.SPAWN_HUB_FIXED_GROUND_Y
	if typeof(fixed) == "number" then
		plateauH = (fixed :: number) - BASE_Y -- convert absolute Y to "height above BASE_Y"
	else
		plateauH = WorldHeight.heightAt(origin.X + SPAWN_X, origin.Z + SPAWN_Z)
	end
end

	local function hubBlendHeight(localX: number, localZ: number, rawH: number): number
		local dx = localX - SPAWN_X
		local dz = localZ - SPAWN_Z
		local d2 = dx * dx + dz * dz

		-- ✅ perfect flat inside hub
		if d2 <= HUB_R2 then
			return plateauH
		end

		-- outside blend ring: normal terrain
		if d2 >= HUB_OUTER2 then
			return rawH
		end

		-- between: smooth blend from flat -> raw
		local dist = math.sqrt(d2)
		local t = smoothstep((dist - HUB_R) / HUB_BLEND)
		return plateauH * (1 - t) + rawH * t
	end

	-- 0) Ocean
	local oceanExtent = WORLD_RADIUS + BEACH_WIDTH + OCEAN_PADDING
	local oceanSize = Vector3.new(oceanExtent * 2, (SEA_LEVEL - SEA_FLOOR), oceanExtent * 2)
	local oceanCenterY = BASE_Y + (SEA_FLOOR + SEA_LEVEL) / 2

	Terrain:FillBlock(
		CFrame.new(origin.X, oceanCenterY, origin.Z),
		oceanSize,
		Enum.Material.Water
	)

	-- 1) Land + beach
	local minXZ = -oceanExtent
	local maxXZ = oceanExtent

	local rockStart: number = (WorldConfig.ROCK_START :: number?) or 60

	for lx = minXZ, maxXZ, STEP do
		for lz = minXZ, maxXZ, STEP do
			local dist = math.sqrt(lx * lx + lz * lz)

			if dist <= WORLD_RADIUS then
				local rawH = WorldHeight.heightAt(origin.X + lx, origin.Z + lz)
				local h = hubBlendHeight(lx, lz, rawH)

				-- ✅ micro jitter only OUTSIDE the hub (keeps hub perfectly flat)
				do
					local dx = lx - SPAWN_X
					local dz = lz - SPAWN_Z
					local d2 = dx * dx + dz * dz
					if d2 > HUB_R2 then
						local micro = math.noise((origin.X + lx) * 0.08, (origin.Z + lz) * 0.08) * 1.5
						h += micro
					end
				end

				-- ✅ force hub area material to grass
				local mat = Enum.Material.Grass
				do
					local dx = lx - SPAWN_X
					local dz = lz - SPAWN_Z
					local d2 = dx * dx + dz * dz
					if d2 > HUB_R2 then
						if h > rockStart then
							mat = Enum.Material.Rock
						end
					end
				end

				fillColumn(origin, STEP, BASE_Y, lx, lz, h, mat)

			elseif dist <= (WORLD_RADIUS + BEACH_WIDTH) then
				local t = smoothstep((dist - WORLD_RADIUS) / BEACH_WIDTH)

				local projX = lx * (WORLD_RADIUS / dist)
				local projZ = lz * (WORLD_RADIUS / dist)

				local landEdgeH = WorldHeight.heightAt(origin.X + projX, origin.Z + projZ)
				landEdgeH = hubBlendHeight(projX, projZ, landEdgeH)

				local targetH = SEA_LEVEL - 2
				local beachH = landEdgeH * (1 - t) + targetH * t
				beachH = math.max(1, beachH)

				fillColumn(origin, STEP, BASE_Y, lx, lz, beachH, Enum.Material.Sand)
			end
		end
	end

	print(("[Terrain] Generated island STEP=%d origin=(%.0f,%.0f) r=%.0f beach=%d sea=%d plateauH=%.1f hubR=%d hubBlend=%d"):format(
		STEP, origin.X, origin.Z, WORLD_RADIUS, BEACH_WIDTH, SEA_LEVEL, plateauH, HUB_R, HUB_BLEND
	))
end

return TerrainGenerator