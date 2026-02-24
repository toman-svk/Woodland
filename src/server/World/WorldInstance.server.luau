--!strict
-- ServerScriptService/Server/World/WorldInstance.server.luau
-- Builds a private world per player inside the same server using an origin offset.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local WorldPersistence = require(script.Parent:WaitForChild("WorldPersistence")) :: any

-- Your worldgen scripts should be converted to ModuleScripts with functions.
-- We'll call: SpawnCaves.Build(root, origin, rng, save), SpawnGems.Build(...), SpawnTrees.Build(...)
local WorldGenFolder = Workspace:FindFirstChild("Generated") or Instance.new("Folder")
WorldGenFolder.Name = "Generated"
WorldGenFolder.Parent = Workspace

local perPlayerFolder = WorldGenFolder:FindFirstChild("PlayerWorlds") or Instance.new("Folder")
perPlayerFolder.Name = "PlayerWorlds"
perPlayerFolder.Parent = WorldGenFolder

-- Remotes for reset (optional button later)
local shared = ReplicatedStorage:FindFirstChild("Shared") or Instance.new("Folder")
shared.Name = "Shared"
shared.Parent = ReplicatedStorage

local resetWorldEvent = shared:FindFirstChild("ResetWorld")
if not (resetWorldEvent and resetWorldEvent:IsA("RemoteEvent")) then
	local ev = Instance.new("RemoteEvent")
	ev.Name = "ResetWorld"
	ev.Parent = shared
	resetWorldEvent = ev
end

-- ===== Origin offsets (keeps worlds far apart) =====
local WORLD_SPACING = 2500 -- studs
local function originForUser(userId: number): Vector3
	-- Spread on X axis; you can do grid if you want.
	return Vector3.new(userId * WORLD_SPACING, 0, 0)
end

local function destroyWorldFolder(userId: number)
	local f = perPlayerFolder:FindFirstChild(tostring(userId))
	if f then f:Destroy() end
end

local function createWorldFolder(userId: number): Folder
	destroyWorldFolder(userId)

	local f = Instance.new("Folder")
	f.Name = tostring(userId)
	f.Parent = perPlayerFolder
	return f
end

-- ===== TODO: Convert your worldgen scripts to modules =====
-- Example stubs; you will replace with your actual module requires after refactor.
local SpawnTrees = require(script.Parent.Parent:WaitForChild("WorldGenerationModules"):WaitForChild("SpawnTrees")) :: any
local SpawnCaves = require(script.Parent.Parent:WaitForChild("WorldGenerationModules"):WaitForChild("SpawnCaves")) :: any
local SpawnGems  = require(script.Parent.Parent:WaitForChild("WorldGenerationModules"):WaitForChild("SpawnGems"))  :: any

local function buildWorldForPlayer(player: Player, save: any)
	local uid = player.UserId
	local origin = originForUser(uid)
	local rng = Random.new(save.seed)

	local root = createWorldFolder(uid)

	-- Optional: store metadata so other systems can locate the correct world folder
	root:SetAttribute("WorldOwnerUserId", uid)
	root:SetAttribute("Seed", save.seed)

	-- Generate in deterministic order (important!)
	SpawnCaves.Build(root, origin, rng, save)
	SpawnGems.Build(root, origin, rng, save)
	SpawnTrees.Build(root, origin, rng, save)

	-- Teleport player to their world's spawn (simple)
	local char = player.Character
	if char then
		local hrp = char:FindFirstChild("HumanoidRootPart")
		if hrp and hrp:IsA("BasePart") then
			hrp.CFrame = CFrame.new(origin + Vector3.new(0, 25, 0))
		end
	end

	return root
end

-- Autosave debounce (avoid writing too often)
local dirty: {[number]: boolean} = {}
local saves: {[number]: any} = {}

local function markDirty(userId: number)
	dirty[userId] = true
end

task.spawn(function()
	while true do
		task.wait(30)
		for uid, isDirty in pairs(dirty) do
			if isDirty and saves[uid] ~= nil then
				dirty[uid] = false
				WorldPersistence.Save(uid, saves[uid])
			end
		end
	end
end)

Players.PlayerAdded:Connect(function(player)
	local save = WorldPersistence.Load(player.UserId)
	saves[player.UserId] = save

	buildWorldForPlayer(player, save)
end)

Players.PlayerRemoving:Connect(function(player)
	local uid = player.UserId
	if saves[uid] then
		WorldPersistence.Save(uid, saves[uid])
	end
	saves[uid] = nil
	dirty[uid] = nil
	destroyWorldFolder(uid)
end)

game:BindToClose(function()
	for uid, save in pairs(saves) do
		WorldPersistence.Save(uid, save)
	end
end)

resetWorldEvent.OnServerEvent:Connect(function(player)
	local uid = player.UserId
	local save = WorldPersistence.Reset(uid)
	saves[uid] = save
	markDirty(uid)

	buildWorldForPlayer(player, save)
end)

-- Expose a tiny API for other systems (ResourceSystem) via attributes + shared table
-- (Simplest: require this script as a module instead; but scripts can't be required.)
-- For now, ResourceSystem should require WorldPersistence and mutate saves[uid] through a shared module instead.