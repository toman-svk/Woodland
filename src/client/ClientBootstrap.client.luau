--!strict
-- src/client/ClientBootstrap.client.luau
-- StarterPlayerScripts entrypoint: chooses Lobby vs World client modules by PlaceId.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- === CONFIG ===
local LOBBY_PLACE_ID = 131782889117139
local WORLD_PLACE_ID = 74640557554115

-- If true, Studio will still load modules based on which place you opened.
-- (Recommended: true)
local RUN_IN_STUDIO = true

-- =========================

type StartableModuleTable = {
	Init: (() -> ())?,
	Start: (() -> ())?,
}

local function startModuleFrom(folder: Folder, moduleName: string): boolean
	local inst = folder:FindFirstChild(moduleName)
	if not inst or not inst:IsA("ModuleScript") then
		warn(("[ClientBootstrap] Missing ModuleScript: %s/%s"):format(folder:GetFullName(), moduleName))
		return false
	end

	local okRequire, modOrFn = pcall(require, inst)
	if not okRequire then
		warn(("[ClientBootstrap] Require failed for %s: %s"):format(moduleName, tostring(modOrFn)))
		return false
	end

	-- Module can be:
	-- 1) function() ... end
	-- 2) { Init = function() end } or { Start = function() end }
	-- 3) { } (no-op)
	if type(modOrFn) == "function" then
		local okRun, err = pcall(function()
			(modOrFn :: any)()
		end)
		if not okRun then
			warn(("[ClientBootstrap] Run failed for %s: %s"):format(moduleName, tostring(err)))
			return false
		end
		return true
	end

	if type(modOrFn) == "table" then
		local t = modOrFn :: StartableModuleTable
		local fn = t.Init or t.Start
		if fn == nil then
			-- no-op module is ok
			return true
		end

		local okRun, err = pcall(function()
			(fn :: () -> ())()
		end)
		if not okRun then
			warn(("[ClientBootstrap] Init/Start failed for %s: %s"):format(moduleName, tostring(err)))
			return false
		end
		return true
	end

	warn(("[ClientBootstrap] %s returned unsupported type: %s"):format(moduleName, typeof(modOrFn)))
	return false
end

local function resolveContext(): "Lobby" | "World" | "Unknown"
	-- In live game, PlaceId is authoritative
	if game.PlaceId == LOBBY_PLACE_ID then
		return "Lobby"
	end
	if game.PlaceId == WORLD_PLACE_ID then
		return "World"
	end

	-- In Studio, allow running even if ids don't match (optional)
	if RUN_IN_STUDIO and RunService:IsStudio() then
		-- If you opened Lobby place in Studio, PlaceId should still match.
		-- But if it doesn't (some test modes), fall back to "Unknown" and do nothing.
		return "Unknown"
	end

	return "Unknown"
end

local Shared = ReplicatedStorage:WaitForChild("Shared")
local lobbyFolder = Shared:WaitForChild("LobbyClientModules") :: Folder
local worldFolder = Shared:WaitForChild("WorldClientModules") :: Folder

local ctx = resolveContext()

if ctx == "Unknown" then
	warn(("[ClientBootstrap] Unknown place context (PlaceId=%d). No client modules started."):format(game.PlaceId))
	return
end

local folderToUse: Folder
local order: {string}

if ctx == "Lobby" then
	folderToUse = lobbyFolder
	order = {
		-- Keep lobby minimal; add more later
		"WorldMenu",
	}
else
	folderToUse = worldFolder
	order = {
		"UIScaler",
		"Sprint",
		"Combat",
		"Spells",
		"Dialogue",
		"PickupFX",
		"AmbientAudio",
	}
end

local startedCount = 0
for _, name in ipairs(order) do
	if startModuleFrom(folderToUse, name) then
		startedCount += 1
	end
end

print(("[ClientBootstrap] Context=%s. Started %d/%d modules from %s"):format(
	ctx,
	startedCount,
	#order,
	folderToUse:GetFullName()
))