--!strict
-- src/server/Gameplay/World/Config/WorldConfig.luau

local WorldConfig = {}

-- Spawn hub (stable area)
WorldConfig.SPAWN_CENTER_X = 0
WorldConfig.SPAWN_CENTER_Z = 0
WorldConfig.SPAWN_FLAT_RADIUS = 40      -- flatten terrain here

-- Spawn Hub (stable safe area)

WorldConfig.SPAWN_CLEAR_RADIUS = 90        -- no caves/gems/trees here
WorldConfig.MOUNTAIN_SPAWN_BUFFER = 180     -- mountains must be at least this far from spawn


-- Generated Area
WorldConfig.AREA_SIZE = 1600
WorldConfig.STEP = 8
WorldConfig.TERRAIN_STEP = 4

WorldConfig.BASE_Y = 0
WorldConfig.BASE_HEIGHT = 20
WorldConfig.HILL_HEIGHT = 55
WorldConfig.NOISE_SCALE = 0.015

WorldConfig.ROCK_START = 60

-- SpawnHub Area
WorldConfig.SPAWN_HUB_FIXED_GROUND_Y = nil -- e.g. 50 to force hub ground to Y=50
WorldConfig.SPAWN_HUB_RADIUS = 120     -- radius of spawn hub area (where we place the SpawnHubTemplate)
WorldConfig.SPAWN_HUB_BLEND_WIDTH = 40
WorldConfig.SPAWN_HUB_RADIUS_L2 = 160

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
WorldConfig.TREE_SPACING = 42          -- slightly larger logical spacing (we'll still place dense via grid+clusters)
WorldConfig.TREE_CHANCE = 0.50        -- base chance per cell (clusters handle density)
WorldConfig.MAX_TREES = 2600

WorldConfig.TREE_SCALE_MIN = 2.0
WorldConfig.TREE_SCALE_MAX = 5.0

-- Caves 
WorldConfig.CAVE_JITTER = 50
WorldConfig.CAVE_MIN_SPAWN_DISTANCE = 220   -- caves must be at least this far from spawn (studs)
WorldConfig.CAVE_SPACING = 220
WorldConfig.CAVE_CHANCE = 0.25
WorldConfig.MAX_CAVES = 5
WorldConfig.MIN_CAVES = 2

-- Gems
WorldConfig.GEMS_PER_CAVE_MIN = 3
WorldConfig.GEMS_PER_CAVE_MAX = 5
WorldConfig.GEM_SPAWN_RADIUS = 55           -- around each cave
WorldConfig.GEM_MIN_DISTANCE_FROM_CAVE = 18 -- avoid clipping into cave

return WorldConfig