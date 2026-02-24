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
WorldConfig.AREA_SIZE = 800
WorldConfig.STEP = 8

WorldConfig.BASE_Y = 0
WorldConfig.BASE_HEIGHT = 20
WorldConfig.HILL_HEIGHT = 55
WorldConfig.NOISE_SCALE = 0.015

WorldConfig.ROCK_START = 60

-- Water / Beach
WorldConfig.SEA_LEVEL = 8            -- Y height of ocean surface (in studs, relative to BASE_Y)
WorldConfig.SEA_FLOOR = -40          -- how deep ocean goes (relative to BASE_Y)
WorldConfig.BEACH_WIDTH = 80         -- thickness of sand ring at the edge
WorldConfig.OCEAN_PADDING = 1000      -- extra ocean distance beyond land+beach

-- Spawn bounds for circular world (match GenerateTerrain)
WorldConfig.WORLD_RADIUS = WorldConfig.AREA_SIZE / 2   -- land radius
WorldConfig.SPAWN_EDGE_MARGIN = 70                     -- keep spawns away from shoreline/beach

-- Mountains
WorldConfig.MOUNTAIN_RADIUS = 150   -- bigger = wider mountain
WorldConfig.MOUNTAIN_HEIGHT = 80   -- bigger = taller mountain



	-- Trees
WorldConfig.TREE_SPACING = 5          -- slightly larger logical spacing (we'll still place dense via grid+clusters)
WorldConfig.TREE_CHANCE = 0.65        -- base chance per cell (clusters handle density)
WorldConfig.MAX_TREES = 2600

WorldConfig.TREE_SCALE_MIN = 2.0
WorldConfig.TREE_SCALE_MAX = 5.0

-- Caves (make rarer)
WorldConfig.CAVE_SPACING = 240        -- bigger spacing = fewer
WorldConfig.CAVE_JITTER = 50
WorldConfig.CAVE_CHANCE = 0.25        -- NEW: chance per grid cell
WorldConfig.MAX_CAVES = 18            -- NEW: cap

return WorldConfig