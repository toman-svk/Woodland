-- ServerScriptService/WorldModules/WorldConfig.lua

local WorldConfig = {}

-- Spawn hub (stable area)
WorldConfig.SPAWN_CENTER_X = 0
WorldConfig.SPAWN_CENTER_Z = 0
WorldConfig.SPAWN_FLAT_RADIUS = 40      -- flatten terrain here

-- Spawn Hub (stable safe area)

WorldConfig.SPAWN_CLEAR_RADIUS = 90        -- no caves/gems/trees here
WorldConfig.MOUNTAIN_SPAWN_BUFFER = 180     -- mountains must be at least this far from spawn


-- Generated Area
WorldConfig.AREA_SIZE = 600
WorldConfig.STEP = 8

WorldConfig.BASE_Y = 0
WorldConfig.BASE_HEIGHT = 20
WorldConfig.HILL_HEIGHT = 55
WorldConfig.NOISE_SCALE = 0.015

WorldConfig.ROCK_START = 60

-- Mountains
WorldConfig.MOUNTAIN_RADIUS = 150   -- bigger = wider mountain
WorldConfig.MOUNTAIN_HEIGHT = 80   -- bigger = taller mountain

-- Trees
WorldConfig.TREE_SPACING = 24
WorldConfig.TREE_CHANCE = 0.6
WorldConfig.MAX_TREES = 700


	-- Tree size randomization
	WorldConfig.TREE_SCALE_MIN = 1
	WorldConfig.TREE_SCALE_MAX = 1.5

-- Caves
WorldConfig.CAVE_SPACING = 150
WorldConfig.CAVE_JITTER = 25
WorldConfig.MAX_CAVES = 9999

return WorldConfig