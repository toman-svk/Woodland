--!strict
-- ServerScriptService/Server/World/WorldService.luau
-- Shared API: builds per-player worlds, exposes save + dirty flags to other systems.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

type SaveData = {
	seed: number,
	removedTrees: {[string]: true}?,
	removedGems: {[string]: true}?,
	-- add more later
}

type WorldRoot = Folder

local WorldService = {}

-- ===== Folders in workspace =====
local worldsFolder = Workspace:FindFirstChild("Worlds")
if not (worldsFolder and worldsFolder:IsA("Folder")) then
	worldsFolder = Instance.new("Folder")
	worldsFolder.Name = "Worlds"
	worldsFolder.Parent = Workspace
end
WorldService.WorldsFolder = worldsFolder :: Folder

-- ===== Remotes (optional reset) =====
local shared = ReplicatedStorage:FindFirstChild("Shared")
if not (shared and shared:IsA("Folder")) then
	shared = Instance.new("Folder")
	shared.Name = "Shared"
	shared.Parent = ReplicatedStorage
end

local resetWorldEvent = shared:FindFirstChild("ResetWorld")
if not (resetWorldEvent and resetWorldEvent:IsA("RemoteEvent")) then
	local ev = Instance.new("RemoteEvent")
	ev.Name = "ResetWorld"
	ev.Parent = shared
	resetWorldEvent = ev
end
WorldService.ResetWorldEvent = resetWorldEvent :: RemoteEvent

-- ===== Persistence module (static require path!) =====
local WorldPersistence = require(script.Parent:WaitForChild("WorldPersistence")) :: any

-- ===== Worldgen modules (static require path!) =====
-- Put your ModuleScripts under: ServerScriptService/Server/WorldGenerationModules
local WorldGenerationModules = script.Parent.Parent:WaitForChild("WorldGenerationModules")

local SpawnCaves = require(WorldGenerationModules:WaitForChild("SpawnCaves")) :: any
local SpawnGems  = require(WorldGenerationModules:WaitForChild("SpawnGems"))  :: any
local SpawnTrees = require(WorldGenerationModules:WaitForChild("SpawnTrees")) :: any
-- Later: GenerateTerrain, SpawnCaveSkeletons, etc.

-- ===== Origin offsets =====
local WORLD_SPACING = 2500

local function originForUser(userId: number): Vector3
	return Vector3.new(userId * WORLD_SPACING, 0, 0)
end

-- ===== State in-memory =====
local saves: {[number]: SaveData} = {}
local dirty: {[number]: boolean} = {}
local roots: {[number]: WorldRoot} = {}

function WorldService.GetSave(userId: number): SaveData?
	return saves[userId]
end

function WorldService.MarkDirty(userId: number)
	dirty[userId] = true
end

function WorldService.GetWorldRoot(userId: number): WorldRoot?
	return roots[userId]
end

function WorldService.GetWorldRootForPlayer(player: Player): WorldRoot?
	return roots[player.UserId]
end

local function destroyWorldFolder(userId: number)
	local existing = worldsFolder:FindFirstChild(tostring(userId))
	if existing then
		existing:Destroy()
	end
	roots[userId] = nil
end

local function createWorldFolder(userId: number): WorldRoot
	destroyWorldFolder(userId)

	local f = Instance.new("Folder")
	f.Name = tostring(userId)
	f.Parent = worldsFolder
	return f
end

-- Teleport after character exists (reliable)
local function teleportPlayerToOrigin(player: Player, origin: Vector3)
	local function place(char: Model)
		local hrp = char:FindFirstChild("HumanoidRootPart")
		if hrp and hrp:IsA("BasePart") then
			hrp.CFrame = CFrame.new(origin + Vector3.new(0, 25, 0))
		end
	end

	if player.Character then
		place(player.Character)
	end

	player.CharacterAdded:Connect(place)
end

function WorldService.BuildWorldForPlayer(player: Player): WorldRoot
	local uid = player.UserId

	local save: SaveData = saves[uid]
	if not save then
		save = WorldPersistence.Load(uid) :: SaveData
		saves[uid] = save
	end

	local origin = originForUser(uid)
	local rng = Random.new(save.seed)

	local root = createWorldFolder(uid)
	roots[uid] = root

	root:SetAttribute("WorldOwnerUserId", uid)
	root:SetAttribute("Seed", save.seed)

	-- If you want everything under a Generated subfolder:
	local generated = Instance.new("Folder")
	generated.Name = "Generated"
	generated.Parent = root

	-- IMPORTANT: make your worldgen modules spawn under `generated`
	SpawnCaves.Build(generated, origin, rng, save)
	SpawnGems.Build(generated, origin, rng, save)
	SpawnTrees.Build(generated, origin, rng, save)

	teleportPlayerToOrigin(player, origin)

	return root
end

function WorldService.LoadPlayer(player: Player)
	local uid = player.UserId
	local save = WorldPersistence.Load(uid) :: SaveData
	saves[uid] = save
	dirty[uid] = false
	WorldService.BuildWorldForPlayer(player)
end

function WorldService.UnloadPlayer(player: Player)
	local uid = player.UserId
	local save = saves[uid]
	if save then
		WorldPersistence.Save(uid, save)
	end
	saves[uid] = nil
	dirty[uid] = nil
	destroyWorldFolder(uid)
end

function WorldService.ResetPlayerWorld(player: Player)
	local uid = player.UserId
	local save = WorldPersistence.Reset(uid) :: SaveData
	saves[uid] = save
	dirty[uid] = true
	WorldService.BuildWorldForPlayer(player)
end

-- Autosave loop
task.spawn(function()
	while true do
		task.wait(30)
		for uid, isDirty in pairs(dirty) do
			if isDirty then
				local save = saves[uid]
				if save then
					dirty[uid] = false
					WorldPersistence.Save(uid, save)
				end
			end
		end
	end
end)

return WorldService