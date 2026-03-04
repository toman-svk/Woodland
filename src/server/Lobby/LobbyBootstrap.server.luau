--!strict
-- src/server/Lobby/LobbyBootstrap.server.luau
-- Lobby place server bootstrap:
-- - ensures LobbyUI remotes exist
-- - implements GetWorlds / CreateWorld / DeleteWorld RemoteFunctions
-- - DOES NOT auto-teleport (portal/menu will drive that later)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

-- >>> YOUR PLACE IDS <<<
local LOBBY_PLACE_ID = 131782889117139

-- Only run in Lobby
if game.PlaceId ~= LOBBY_PLACE_ID then
	return
end

local function newSeed(): number
	-- stable random seed per world (stored in datastore)
	return Random.new():NextInteger(1, 2_000_000_000)
end

-- =========================
-- Remotes (LobbyUI folder)
-- =========================

local function getOrCreateFolder(parent: Instance, name: string): Folder
	local f = parent:FindFirstChild(name)
	if f and f:IsA("Folder") then
		return f
	end
	local nf = Instance.new("Folder")
	nf.Name = name
	nf.Parent = parent
	return nf
end

local function getOrCreateRemoteEvent(parent: Instance, name: string): RemoteEvent
	local r = parent:FindFirstChild(name)
	if r and r:IsA("RemoteEvent") then
		return r
	end
	local nr = Instance.new("RemoteEvent")
	nr.Name = name
	nr.Parent = parent
	return nr
end

local function getOrCreateRemoteFunction(parent: Instance, name: string): RemoteFunction
	local r = parent:FindFirstChild(name)
	if r and r:IsA("RemoteFunction") then
		return r
	end
	local nr = Instance.new("RemoteFunction")
	nr.Name = name
	nr.Parent = parent
	return nr
end

local shared = getOrCreateFolder(ReplicatedStorage, "Shared")
local remotesRoot = getOrCreateFolder(shared, "Remotes")
local lobbyUI = getOrCreateFolder(remotesRoot, "LobbyUI")

-- You already have OpenWorldMenu here:
local _openWorldMenu = getOrCreateRemoteEvent(lobbyUI, "OpenWorldMenu")

-- New RFs used by the UI:
local getWorldsRF = getOrCreateRemoteFunction(lobbyUI, "GetWorlds")
local createWorldRF = getOrCreateRemoteFunction(lobbyUI, "CreateWorld")
local deleteWorldRF = getOrCreateRemoteFunction(lobbyUI, "DeleteWorld")

-- =========================
-- Data model
-- =========================

export type WorldInfo = {
	id: string,
	name: string,
	createdAt: number,
    seed: number,
}

type WorldsBlob = {
	version: number,
	worlds: {WorldInfo},
}

local WORLDS_VERSION = 1

local function defaultBlob(): WorldsBlob
	return {
		version = WORLDS_VERSION,
		worlds = {},
	}
end

-- =========================
-- Storage
-- =========================

-- Use DataStore in live; in Studio, allow in-memory fallback.
local WORLDS_STORE = DataStoreService:GetDataStore("LobbyWorlds_v1")
local mem: {[number]: WorldsBlob} = {}

local function keyForUser(userId: number): string
	return ("u_%d_worlds"):format(userId)
end

local function loadWorlds(userId: number): WorldsBlob
	-- Studio fallback
	if RunService:IsStudio() then
		if mem[userId] == nil then
			mem[userId] = defaultBlob()
		end
		return mem[userId]
	end

	local key = keyForUser(userId)
	local ok, data = pcall(function()
		return WORLDS_STORE:GetAsync(key)
	end)

	if not ok then
		warn("[LobbyBootstrap] GetAsync failed:", data)
		return defaultBlob()
	end

	if type(data) ~= "table" then
		return defaultBlob()
	end

	local t = data :: any
	if type(t.worlds) ~= "table" then
		return defaultBlob()
	end

	return t :: WorldsBlob
end

local function saveWorlds(userId: number, blob: WorldsBlob): boolean
	-- Studio fallback
	if RunService:IsStudio() then
		mem[userId] = blob
		return true
	end

	local key = keyForUser(userId)
	local ok, err = pcall(function()
		WORLDS_STORE:SetAsync(key, blob)
	end)

	if not ok then
		warn("[LobbyBootstrap] SetAsync failed:", err)
		return false
	end

	return true
end

-- =========================
-- Validation helpers
-- =========================

local function sanitizeName(name: any): (string?, string?)
	if type(name) ~= "string" then
		return nil, "Name must be a string."
	end

	-- trim
	name = name:gsub("^%s+", ""):gsub("%s+$", "")
	if #name < 2 then
		return nil, "Name too short (min 2 chars)."
	end
	if #name > 24 then
		return nil, "Name too long (max 24 chars)."
	end

	-- basic “safe” characters (you can relax later)
	if name:match("[\r\n\t]") then
		return nil, "Invalid characters in name."
	end

	return name, nil
end

local function findWorldIndex(worlds: {WorldInfo}, id: string): number?
	for i, w in ipairs(worlds) do
		if w.id == id then
			return i
		end
	end
	return nil
end

-- =========================
-- RemoteFunctions for UI
-- =========================

getWorldsRF.OnServerInvoke = function(player: Player)
	local blob = loadWorlds(player.UserId)

	-- ✅ Migration: ensure every world has a seed
	local changed = false
	for _, w in ipairs(blob.worlds) do
		if typeof((w :: any).seed) ~= "number" then
			(w :: any).seed = newSeed()
			changed = true
		end
	end
	if changed then
		saveWorlds(player.UserId, blob)
	end

	return {
		ok = true,
		worlds = blob.worlds,
	}
end

createWorldRF.OnServerInvoke = function(player: Player, nameArg: any)
	local name, err = sanitizeName(nameArg)
	if not name then
		return { ok = false, error = err }
	end

	local blob = loadWorlds(player.UserId)

	-- optional cap
	if #blob.worlds >= 20 then
		return { ok = false, error = "World limit reached (20)." }
	end

    local newWorld: WorldInfo = {
        id = HttpService:GenerateGUID(false),
        name = name,
        createdAt = os.time(),
        seed = newSeed(), -- ✅ NEW
    }

	table.insert(blob.worlds, newWorld)

	if not saveWorlds(player.UserId, blob) then
		return { ok = false, error = "Failed to save world list." }
	end

	return { ok = true, world = newWorld }
end

deleteWorldRF.OnServerInvoke = function(player: Player, worldIdArg: any)
	if type(worldIdArg) ~= "string" then
		return { ok = false, error = "worldId must be a string." }
	end

	local blob = loadWorlds(player.UserId)
	local idx = findWorldIndex(blob.worlds, worldIdArg)
	if not idx then
		return { ok = false, error = "World not found." }
	end

	table.remove(blob.worlds, idx)

	if not saveWorlds(player.UserId, blob) then
		return { ok = false, error = "Failed to save world list." }
	end

	return { ok = true }
end

-- JoinWorld (RemoteFunction)
local TeleportService = game:GetService("TeleportService")

-- make sure these IDs match your real place ids
local GAMEPLAY_PLACE_ID = 74640557554115

local function ownsWorld(userId: number, worldId: string): boolean
	local blob = loadWorlds(userId)
	return findWorldIndex(blob.worlds, worldId) ~= nil
end

local joinWorldRF = lobbyUI:WaitForChild("JoinWorld") :: RemoteFunction

joinWorldRF.OnServerInvoke = function(player: Player, worldId: string)
	-- basic validation
	if typeof(worldId) ~= "string" or #worldId < 3 then
		return { ok = false, error = "Invalid world id." }
	end

	-- IMPORTANT: verify the world belongs to this player
	-- Use the same data source you use for GetWorlds (your datastore schema)
	if not ownsWorld(player.UserId, worldId) then
		return { ok = false, error = "You don't own this world." }
	end

	-- Reserve a fresh private server for Gameplay
	local okReserve, reserveCodeOrErr = pcall(function()
		return TeleportService:ReserveServer(GAMEPLAY_PLACE_ID)
	end)
	if not okReserve then
		return { ok = false, error = "ReserveServer failed: " .. tostring(reserveCodeOrErr) }
	end
	local reserveCode = reserveCodeOrErr :: string

    

	-- Teleport with TeleportData so Gameplay place loads correct worldId
	local function getWorldById(userId: number, worldId: string): WorldInfo?
		local blob = loadWorlds(userId)
		for _, w in ipairs(blob.worlds) do
			if w.id == worldId then
				return w
			end
		end
		return nil
	end

	local w = getWorldById(player.UserId, worldId)
	if not w then
		return { ok = false, error = "You don't own this world." }
	end

    print("[LobbyBootstrap] Teleporting to world:", worldId, "seed:", w.seed)

	local options = Instance.new("TeleportOptions")
	options:SetTeleportData({
		worldId = worldId,
		ownerUserId = player.UserId,
		kind = "World",
		seed = w.seed, -- ✅ NEW
	})

	local okTp, tpErr = pcall(function()
		TeleportService:TeleportToPrivateServer(GAMEPLAY_PLACE_ID, reserveCode, { player }, options)
	end)
	if not okTp then
		return { ok = false, error = "Teleport failed: " .. tostring(tpErr) }
	end

	return { ok = true }
end

-- Optional: warm up cache in Studio
Players.PlayerAdded:Connect(function(player)
	if RunService:IsStudio() then
		loadWorlds(player.UserId)
	end
end)

print("[LobbyBootstrap] Lobby UI remotes + world list handlers ready.")