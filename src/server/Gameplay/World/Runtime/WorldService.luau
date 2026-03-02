--!strict
-- src/server/Gameplay/World/Runtime/WorldService.luau
-- Gameplay-place WorldService:
-- - Reads TeleportData to know which worldId this server should host
-- - Loads world save by worldId
-- - Builds world via WorldGenerator
-- - Exposes API for other server systems to mark save dirty, read save, etc.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local WorldService = {}

--========================
-- Types
--========================
export type WorldSave = {
	seed: number,
	-- later:
	-- diffs: { choppedTrees: {[string]: boolean}, minedGems: {[string]: boolean} },
	version: number?,
	lastSavedAt: number?,
}

export type BuildResult = {
	terrain: boolean,
	spawnHub: any,
	caves: number,
	gems: number,
	trees: number,
	enemies: number,
}

--========================
-- Requires (static, analyzer-friendly)
--========================
local runtimeFolder = script.Parent
local generationFolder = runtimeFolder.Parent:WaitForChild("Generation")

local WorldIds = require(runtimeFolder:WaitForChild("WorldIds")) :: any
local WorldInstance = require(runtimeFolder:WaitForChild("WorldInstance")) :: any
local WorldGenerator = require(generationFolder:WaitForChild("WorldGenerator")) :: any

-- IMPORTANT:
-- Replace this require path with YOUR persistence module location.
-- I’m assuming you keep it here:
--   src/server/Gameplay/Persistence/WorldPersistence.luau
local persistenceFolder = runtimeFolder.Parent.Parent:WaitForChild("Persistence")
local WorldPersistence = require(persistenceFolder:WaitForChild("WorldPersistence")) :: any

--========================
-- Workspace folders
--========================
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

-- One server = one world root
local worldsFolder = getOrCreateFolder(Workspace, "Worlds")

--========================
-- Internal state (single world per server)
--========================
local currentWorld: any = nil -- WorldInstance
local buildResult: BuildResult? = nil

-- debounce autosaves
local dirty = false
local lastSaveClock = 0.0
local AUTOSAVE_PERIOD = 30.0

--========================
-- Helpers
--========================
local function getTeleportData(player: Player): any?
	local joinData = player:GetJoinData()
	if joinData and joinData.TeleportData then
		return joinData.TeleportData
	end
	return nil
end

local function resolveWorldIdFromPlayers(): string?
	-- In a reserved server, TeleportData may be present on the first player.
	-- We wait for at least 1 player, then read their joinData.
	local players = Players:GetPlayers()
	for _, p in ipairs(players) do
		local td = getTeleportData(p)
		if td and typeof(td.worldId) == "string" then
			return td.worldId
		end
	end
	return nil
end

local function destroyCurrentWorld()
	if currentWorld and currentWorld.Root and currentWorld.Root.Parent then
		currentWorld.Root:Destroy()
	end
	currentWorld = nil
	buildResult = nil
	dirty = false
end

local function createWorldFolders(worldId: string): (Folder, Folder)
	-- Root folder is named by worldId (helps debugging)
	local root = Instance.new("Folder")
	root.Name = worldId
	root.Parent = worldsFolder

	local generated = Instance.new("Folder")
	generated.Name = "Generated"
	generated.Parent = root

	return root, generated
end

--========================
-- Public API
--========================
function WorldService.GetWorld()
	return currentWorld
end

function WorldService.GetWorldId(): string?
	if currentWorld then
		return currentWorld.WorldId
	end
	return nil
end

function WorldService.GetSave(): WorldSave?
	if currentWorld then
		return currentWorld.Save
	end
	return nil
end

function WorldService.MarkDirty()
	dirty = true
	if currentWorld then
		currentWorld:MarkDirty()
	end
end

function WorldService.GetBuildResult(): BuildResult?
	return buildResult
end

--========================
-- Build pipeline
--========================
function WorldService.Bootstrap(): ()
	-- Wait for at least one player so we can read TeleportData
	while #Players:GetPlayers() == 0 do
		task.wait()
	end

	local worldId = resolveWorldIdFromPlayers()

	-- If someone joins gameplay place without going through lobby,
	-- fall back to a solo world for that first user (debug-friendly).
	if not worldId then
		local p = Players:GetPlayers()[1]
		worldId = WorldIds.Solo(p.UserId)
		warn("[WorldService] Missing TeleportData.worldId. Falling back to", worldId)
	end

	-- Load save
	local save: WorldSave = WorldPersistence.LoadWorld(worldId) :: WorldSave

	-- Ensure seed
	if save.seed == nil then
		-- Stable random seed
		save.seed = Random.new():NextInteger(1, 2_000_000_000)
	end

	-- Build world folders
	destroyCurrentWorld()
	if worldId == nil then
	error("[WorldService] worldId is nil after resolution.")
	end
	local root, generated = createWorldFolders(worldId)

	-- Metadata
	root:SetAttribute("WorldId", worldId)
	root:SetAttribute("Seed", save.seed)

	-- Origin for THIS architecture is always (0,0,0) because this server hosts only one world
	local origin = Vector3.new(0, 0, 0)
	local rng = Random.new(save.seed)

	-- Run deterministic generator order
	buildResult = WorldGenerator.Build(generated, origin, rng, save)

	-- Create runtime instance object
	currentWorld = WorldInstance.new(worldId, nil, root, generated, origin, save)

	-- Mark clean after a successful load/build
	dirty = false
	currentWorld:SetDirty(false)

	-- Save immediately once after ensuring seed exists (optional but good)
	WorldPersistence.SaveWorld(worldId, save)
	lastSaveClock = os.clock()

	print("[WorldService] Bootstrapped world:", worldId)
end

--========================
-- Autosave loop
--========================
task.spawn(function()
	while true do
		task.wait(2)

		if not currentWorld then
			continue
		end

		local now = os.clock()
		if dirty and (now - lastSaveClock) >= AUTOSAVE_PERIOD then
			dirty = false
			currentWorld:SetDirty(false)
			lastSaveClock = now

			local wid = currentWorld.WorldId
			local save = currentWorld.Save
			save.lastSavedAt = os.time()

			WorldPersistence.SaveWorld(wid, save)
			print("[WorldService] Autosaved:", wid)
		end
	end
end)

-- Save on shutdown
game:BindToClose(function()
	if currentWorld then
		local wid = currentWorld.WorldId
		local save = currentWorld.Save
		save.lastSavedAt = os.time()
		WorldPersistence.SaveWorld(wid, save)
	end
end)

return WorldService