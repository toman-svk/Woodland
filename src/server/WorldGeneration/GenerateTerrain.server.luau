-- ServerScriptService/WorldGeneneration/GenerateTerrain

local Terrain = workspace.Terrain

local WorldModules = script.Parent.Parent:WaitForChild("WorldModules")
local WorldConfig = require(WorldModules:WaitForChild("WorldConfig"))
local WorldHeight = require(WorldModules:WaitForChild("WorldHeight"))

-- OPTIONAL: clear terrain each run
Terrain:Clear()

local half = WorldConfig.AREA_SIZE / 2

-- Spawn hub flatten settings
local SPAWN_X = WorldConfig.SPAWN_CENTER_X or 0
local SPAWN_Z = WorldConfig.SPAWN_CENTER_Z or 0
local FLAT_R = WorldConfig.SPAWN_FLAT_RADIUS or (WorldConfig.SPAWN_CLEAR_RADIUS or 70)
local FLAT_R2 = FLAT_R * FLAT_R

-- Pick a stable plateau height (based on your terrain height at spawn center)
local plateauH = WorldHeight.heightAt(SPAWN_X, SPAWN_Z)

local function flatBlendHeight(x, z, rawH)
	-- Distance from spawn center in XZ
	local dx = x - SPAWN_X
	local dz = z - SPAWN_Z
	local d2 = dx*dx + dz*dz

	-- Fully flat in the inner radius
	if d2 <= FLAT_R2 then
		return plateauH
	end

	-- Optional: smooth blend ring so edge looks natural (no hard cliff)
	-- Blend from plateau -> raw over a ring thickness
	local blendWidth = 30 -- studs of smoothing outside FLAT_R
	local outer = (FLAT_R + blendWidth)
	local outer2 = outer * outer

	if d2 >= outer2 then
		return rawH
	end
	
	

	-- t goes 0 at FLAT_R, 1 at FLAT_R+blendWidth
	local dist = math.sqrt(d2)
	local t = math.clamp((dist - FLAT_R) / blendWidth, 0, 1)

	-- Smoothstep for nicer blend
	t = t * t * (3 - 2 * t)

	return plateauH * (1 - t) + rawH * t
end

for x = -half, half, WorldConfig.STEP do
	for z = -half, half, WorldConfig.STEP do
		local rawH = WorldHeight.heightAt(x, z)
		local h = flatBlendHeight(x, z, rawH)
		
		

		local centerY = WorldConfig.BASE_Y + h / 2

		local mat = Enum.Material.Grass
		
		
		
		
		if h > WorldConfig.ROCK_START then
			mat = Enum.Material.Rock
		end

		Terrain:FillBlock(
			CFrame.new(x, centerY, z),
			Vector3.new(WorldConfig.STEP, h, WorldConfig.STEP),
			mat
		)
	end
end

print(("[Terrain] Generated with spawn plateau at height=%.1f radius=%d"):format(plateauH, FLAT_R))