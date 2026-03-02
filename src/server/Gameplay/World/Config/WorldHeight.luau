--!strict
-- src/server/Gameplay/World/Config/WorldHeight.luau

local WorldConfig = require(script.Parent.WorldConfig)

type WorldConfigT = {
	AREA_SIZE: number,
	BASE_HEIGHT: number,
	HILL_HEIGHT: number,
	NOISE_SCALE: number,

	SPAWN_CENTER_X: number?,
	SPAWN_CENTER_Z: number?,
	MOUNTAIN_SPAWN_BUFFER: number?,
	MOUNTAIN_RADIUS: number?,
	MOUNTAIN_HEIGHT: number?,
}

local Config: WorldConfigT = WorldConfig

local WorldHeight = {}

local function getSeed(): number
	local seed = workspace:GetAttribute("WorldSeed")
	if typeof(seed) ~= "number" then
		seed = math.random(1, 999_999)
		workspace:SetAttribute("WorldSeed", seed)
	end
	return seed
end



WorldHeight.getSeed = getSeed

-- Two mountain centers per world (deterministic from seed)
local mountainCenters: { Vector2 }? = nil

local function initMountains()
	if mountainCenters then
		return
	end

	local seed = getSeed()
	local half = Config.AREA_SIZE / 2
	local rng = Random.new(seed)

	local margin = 120 -- keep peaks away from edges

	-- Spawn hub position (XZ)
	local spawnX = Config.SPAWN_CENTER_X or 0
	local spawnZ = Config.SPAWN_CENTER_Z or 0
	local minDist = Config.MOUNTAIN_SPAWN_BUFFER or 180
	local minDist2 = minDist * minDist

	local function farFromSpawn(cx: number, cz: number): boolean
		local dx = cx - spawnX
		local dz = cz - spawnZ
		return (dx * dx + dz * dz) >= minDist2
	end

	local function randCenter(): Vector2
		return Vector2.new(
			rng:NextNumber(-half + margin, half - margin),
			rng:NextNumber(-half + margin, half - margin)
		)
	end

	local function pickOne(): Vector2
		-- try a bunch of times to find a good spot away from spawn
		for _ = 1, 80 do
			local c = randCenter()
			if farFromSpawn(c.X, c.Y) then
				return c
			end
		end
		-- fallback (still deterministic, just not guaranteed far)
		return randCenter()
	end

	mountainCenters = { pickOne(), pickOne() }
end

local function mountainBoost(x: number, z: number): number
	initMountains()

	local centers = mountainCenters :: { Vector2 }

	local radius = Config.MOUNTAIN_RADIUS or 150
	local height = Config.MOUNTAIN_HEIGHT or 80

	local boost = 0

	for _, c in ipairs(centers) do
		local dx = x - c.X
		local dz = z - c.Y
		local dist = math.sqrt(dx * dx + dz * dz)

		if dist < radius then
			local t = 1 - (dist / radius) -- 1 at center -> 0 at edge
			boost += (t * t) * height
		end
	end

	return boost
end

function WorldHeight.heightAt(x: number, z: number): number
	local seed = getSeed()

	local scale = Config.NOISE_SCALE
	local n1 = math.noise((x + seed) * scale, (z + seed) * scale)
	local n2 = math.noise((x + seed) * scale * 2, (z + seed) * scale * 2) * 0.5

	local t = ((n1 + n2) + 1) / 2
	local base = Config.BASE_HEIGHT + t * Config.HILL_HEIGHT

	return base + mountainBoost(x, z)
end

WorldHeight.reset = function()
	mountainCenters = nil
end

return WorldHeight