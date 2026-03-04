--!strict
-- src/server/Gameplay/World/Runtime/WorldService.luau
-- Owns the single world runtime inside the Gameplay place (private server).
-- Loads save by worldId (TeleportData), generates the world once, autosaves.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local ConfigLocator = require(script.Parent.Parent:WaitForChild("Config"):WaitForChild("ConfigLocator"))
local WorldConfig = ConfigLocator.WorldConfig
local WorldHeight = ConfigLocator.WorldHeight

local GAMEPLAY_PLACE_ID = 74640557554115

-- Only run in Gameplay place
if game.PlaceId ~= GAMEPLAY_PLACE_ID then
	-- Return a dummy module so requires don't explode if Rojo syncs it everywhere
	return {}
end

local WorldIds = require(script.Parent:WaitForChild("WorldIds"))
local WorldGenerator = require(script.Parent.Parent:WaitForChild("Generation"):WaitForChild("WorldGenerator"))
local WorldPersistence = require(script.Parent.Parent.Parent:WaitForChild("Persistence"):WaitForChild("WorldPersistence"))

export type WorldDiffs = {
	choppedTrees: {[string]: boolean},
	minedGems: {[string]: boolean},
}

export type WorldSave = {
	version: number,
	seed: number?, -- IMPORTANT: set by ensureSeed() before any save
	diffs: WorldDiffs,
	lastSavedAt: number,
}

export type WorldRuntime = {
	worldId: string,
	ownerUserId: number,
	save: WorldSave,
	root: Folder,
	generated: Folder,
	origin: Vector3,
	rng: Random,

	-- ✅ NEW: spawn point returned from SpawnHubRuntime (SpawnLocation in template)
	spawnCFrame: CFrame?,
}

local WorldService = {}

local worldsFolder = Workspace:FindFirstChild("Worlds")
if not (worldsFolder and worldsFolder:IsA("Folder")) then
	worldsFolder = Instance.new("Folder")
	worldsFolder.Name = "Worlds"
	worldsFolder.Parent = Workspace
end

local current: WorldRuntime? = nil
local dirty = false

local AUTOSAVE_PERIOD = 30 -- seconds
local lastSaveClock = 0.0

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

local function destroyCurrentWorld()
	if current then
		if current.root.Parent then
			current.root:Destroy()
		end
		current = nil
	end
end

local function createWorldFolders(worldId: string): (Folder, Folder)
	-- /Workspace/Worlds/<worldId>/Generated
	local root = getOrCreateFolder(worldsFolder :: Folder, worldId)
	-- clean rebuild each server start (this is fine; persistence is in DataStore)
	for _, c in ipairs(root:GetChildren()) do
		c:Destroy()
	end

	local generated = Instance.new("Folder")
	generated.Name = "Generated"
	generated.Parent = root

	return root, generated
end

-- ✅ Updated: prefer spawnCFrame returned from SpawnHubRuntime (SpawnLocation in template)
local function teleportPlayerToSpawn(player: Player, origin: Vector3, spawnCFrame: CFrame?)
	local spawnX = (WorldConfig.SPAWN_CENTER_X or 0)
	local spawnZ = (WorldConfig.SPAWN_CENTER_Z or 0)
	local baseY = (WorldConfig.BASE_Y or 0)

	local function place(char: Model)
		local hrp = char:FindFirstChild("HumanoidRootPart")
		if not (hrp and hrp:IsA("BasePart")) then
			return
		end

		-- ✅ Use SpawnLocation if we have it
		if spawnCFrame ~= nil then
			-- small lift so you don’t collide with the pad
			hrp.CFrame = spawnCFrame + Vector3.new(0, 5, 0)
			return
		end

		-- Fallback: sample heightAt in WORLD coords (origin offset + local spawn)
		local h = WorldHeight.heightAt(origin.X + spawnX, origin.Z + spawnZ)
		local groundY = baseY + h
		hrp.CFrame = CFrame.new(origin.X + spawnX, groundY + 6, origin.Z + spawnZ)
	end

	if player.Character then
		place(player.Character)
	end
	player.CharacterAdded:Connect(place)
end

local function extractTeleportData(player: Player): ({[string]: any}?, string?)
	local joinData = player:GetJoinData()
	local tp = joinData.TeleportData
	if tp == nil then
		return nil, "TeleportData missing"
	end
	if type(tp) ~= "table" then
		return nil, "TeleportData not a table"
	end
	return tp :: {[string]: any}, nil
end

local function ensureSeed(save: WorldSave): number
	if save.seed ~= nil then
		return save.seed
	end
	-- Stable enough: seed assigned once and then saved
	local newSeed = Random.new():NextInteger(1, 2_000_000_000)
	save.seed = newSeed
	return newSeed
end

local function bootstrapFromFirstPlayer(firstPlayer: Player)
	local tp, tpErr = extractTeleportData(firstPlayer)

	local worldId: string
	local ownerUserId: number
	local RunService = game:GetService("RunService")

	if tp and type(tp.worldId) == "string" then
		worldId = tp.worldId
		ownerUserId = if type(tp.ownerUserId) == "number" then tp.ownerUserId else firstPlayer.UserId
	else
		worldId = WorldIds.Solo(firstPlayer.UserId)
		ownerUserId = firstPlayer.UserId
		warn(("[WorldService] Missing TeleportData.worldId. Falling back to %s"):format(worldId))
		if tpErr then
			warn("[WorldService] TeleportData issue:", tpErr)
		end
	end

	-- Load save (by worldId)
	local save = WorldPersistence.Load(worldId) :: WorldSave

		-- If Lobby provided a seed and the save is new/seedless, adopt it
	if tp and typeof((tp :: any).seed) == "number" then
		local tpSeed = (tp :: any).seed :: number
		if save.seed == nil or typeof(save.seed) ~= "number" then
			save.seed = tpSeed
		end
	end

	-- Ensure seed
	local adoptedSeed = false

	if tp and typeof((tp :: any).seed) == "number" then
		local tpSeed = (tp :: any).seed :: number
		if save.seed == nil then
			save.seed = tpSeed
			adoptedSeed = true
		end
	end

	local seed = ensureSeed(save)
	
	print("========== WORLD BOOTSTRAP ==========")
	print("[WorldService] Player:", firstPlayer.Name)
	print("[WorldService] WorldId:", worldId)
	print("[WorldService] OwnerUserId:", ownerUserId)
	print("[WorldService] Seed:", seed)
	if tp then
		print("[WorldService] TeleportData.seed:", tp.seed)
	end
	print("=====================================")

	if adoptedSeed then
		WorldPersistence.Save(worldId, save :: any)
	end

	-- Create folders
	destroyCurrentWorld()
	local root, generated = createWorldFolders(worldId)

	-- This server has ONE world at origin (0,0,0)
	local origin = Vector3.new(0, 0, 0)
	local rng = Random.new(seed)



	root:SetAttribute("WorldId", worldId)
	root:SetAttribute("OwnerUserId", ownerUserId)
	root:SetAttribute("Seed", seed)

	WorldHeight.SetSeed(seed)

	-- Generate
	print(("[WorldService] Generating worldId=%s seed=%d ..."):format(worldId, seed))
	local buildResult = WorldGenerator.Build(generated, origin, rng, save)

	-- ✅ Pull spawnCFrame out of buildResult if present
	local spawnCFrame: CFrame? = nil
	do
		local anyRes = buildResult :: any
		if typeof(anyRes.spawnCFrame) == "CFrame" then
			spawnCFrame = anyRes.spawnCFrame :: CFrame
		end
	end

	print("[WorldService] WorldGenerator result:", buildResult)

	current = {
		worldId = worldId,
		ownerUserId = ownerUserId,
		save = save,
		root = root,
		generated = generated,
		origin = origin,
		rng = rng,
		spawnCFrame = spawnCFrame,
	}

	-- Teleport player in
	teleportPlayerToSpawn(firstPlayer, origin, spawnCFrame)
end

-- Public API for other systems
function WorldService.GetWorldId(): string?
	return if current then current.worldId else nil
end

function WorldService.GetSave(): WorldSave?
	return if current then current.save else nil
end

function WorldService.MarkDirty()
	dirty = true
end

-- Bootstrap entrypoint (called by GameplayBootstrap.server.luau)
function WorldService.Bootstrap()
	-- Wait for first player to arrive so we can read TeleportData
	local booted = false

	Players.PlayerAdded:Connect(function(player)
		if not booted then
			booted = true
			bootstrapFromFirstPlayer(player)
		else
			-- Server already has a world; place player at the stored spawn
			if current then
				teleportPlayerToSpawn(player, current.origin, current.spawnCFrame)
			end
		end
	end)

	-- Autosave loop
	task.spawn(function()
		while true do
			task.wait(2)

			if not current then
				continue
			end

			local now = os.clock()
			if dirty and (now - lastSaveClock) >= AUTOSAVE_PERIOD then
				dirty = false
				lastSaveClock = now

				current.save.lastSavedAt = os.time()
				WorldPersistence.Save(current.worldId, current.save)
				print("[WorldService] Autosaved:", current.worldId)
			end
		end
	end)

	game:BindToClose(function()
		if current then
			current.save.lastSavedAt = os.time()
			WorldPersistence.Save(current.worldId, current.save)
		end
	end)

	print("[WorldService] Bootstrapping (waiting for first player)...")
end

return WorldService