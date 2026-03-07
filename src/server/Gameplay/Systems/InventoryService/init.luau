--!strict
-- src/server/Gameplay/Systems/InventoryService/init.luau

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local WorldService = require(
	ServerScriptService
		:WaitForChild("Server")
		:WaitForChild("Gameplay")
		:WaitForChild("World")
		:WaitForChild("Runtime")
		:WaitForChild("WorldService")
)

local InventoryService = {}

local DEBUG = true
local function log(...)
	if DEBUG then
		print("[InventoryService]", ...)
	end
end

type ItemMap = {[string]: number}
type InventoriesMap = {[string]: ItemMap}

local DEFAULT_ITEMS = {
	Wood = 0,
	Gold = 0,
}

local function ensureInventoryFolder(player: Player): Folder
	local existing = player:FindFirstChild("Inventory")
	if existing and existing:IsA("Folder") then
		return existing
	end

	local folder = Instance.new("Folder")
	folder.Name = "Inventory"
	folder.Parent = player
	return folder
end

local function ensureIntValue(parent: Folder, itemName: string, value: number): IntValue
	local existing = parent:FindFirstChild(itemName)
	if existing and existing:IsA("IntValue") then
		return existing
	end

	local iv = Instance.new("IntValue")
	iv.Name = itemName
	iv.Value = value
	iv.Parent = parent
	return iv
end

local function getWorldSave()
	if WorldService.GetSave then
		return WorldService.GetSave()
	else
		return nil
	end
end

local function ensureInventoriesTable(save: any): InventoriesMap
	if save.inventories == nil then
		save.inventories = {} :: InventoriesMap
	end
	return save.inventories :: InventoriesMap
end

local function getPlayerInventoryTable(save: any, userId: number): ItemMap
	local inventories = ensureInventoriesTable(save)
	local userKey = tostring(userId)

	local inv = inventories[userKey]
	if inv == nil then
		inv = {} :: ItemMap
		inventories[userKey] = inv
	end

	return inv
end

local function persistPlayerFolderToSave(player: Player)
	local save = getWorldSave()
	if not save then
		warn("[InventoryService] No world save available; cannot persist inventory for", player.Name)
		return
	end

	local folder = player:FindFirstChild("Inventory")
	if not (folder and folder:IsA("Folder")) then
		return
	end

	local inv = getPlayerInventoryTable(save, player.UserId)

	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("IntValue") then
			inv[child.Name] = child.Value
		end
	end

	if WorldService.MarkDirty then
		WorldService.MarkDirty()
	end
	log("Persisted inventory for", player.Name, inv)
end

local function loadSaveToPlayerFolder(player: Player)
	local folder = ensureInventoryFolder(player)
	local save = getWorldSave()

	-- Always ensure defaults exist in UI/player folder
	for itemName, defaultValue in pairs(DEFAULT_ITEMS) do
		ensureIntValue(folder, itemName, defaultValue)
	end

	if not save then
		log("No world save yet; using default inventory for", player.Name)
		return
	end

	local inv = getPlayerInventoryTable(save, player.UserId)

	-- Ensure defaults also exist in save
	for itemName, defaultValue in pairs(DEFAULT_ITEMS) do
		if type(inv[itemName]) ~= "number" then
			inv[itemName] = defaultValue
		end
	end

	-- Push save values into player folder
	for itemName, value in pairs(inv) do
		ensureIntValue(folder, itemName, value).Value = value
	end

	if WorldService.MarkDirty then
		WorldService.MarkDirty()
	end
	log("Loaded inventory for", player.Name, inv)
end

function InventoryService.InitPlayer(player: Player)
	log("InitPlayer", player.Name)

	local folder = ensureInventoryFolder(player)
	loadSaveToPlayerFolder(player)

	-- Persist whenever any IntValue changes
	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("IntValue") then
			child.Changed:Connect(function()
				persistPlayerFolderToSave(player)
			end)
		end
	end

	-- Persist newly-added item values too
	folder.ChildAdded:Connect(function(child)
		if child:IsA("IntValue") then
			child.Changed:Connect(function()
				persistPlayerFolderToSave(player)
			end)
			persistPlayerFolderToSave(player)
		end
	end)

	log("Inventory children:", #folder:GetChildren())
end

function InventoryService.Get(player: Player, itemName: string): number
	local folder = player:FindFirstChild("Inventory")
	if not (folder and folder:IsA("Folder")) then
		return 0
	end

	local item = folder:FindFirstChild(itemName)
	if item and item:IsA("IntValue") then
		return item.Value
	end

	return 0
end

function InventoryService.Set(player: Player, itemName: string, value: number)
	local folder = ensureInventoryFolder(player)
	local item = ensureIntValue(folder, itemName, 0)
	item.Value = math.max(0, math.floor(value))
	persistPlayerFolderToSave(player)
end

function InventoryService.Add(player: Player, itemName: string, amount: number)
	local current = InventoryService.Get(player, itemName)
	InventoryService.Set(player, itemName, current + amount)
end

function InventoryService.Remove(player: Player, itemName: string, amount: number): boolean
	local current = InventoryService.Get(player, itemName)
	if current < amount then
		return false
	end

	InventoryService.Set(player, itemName, current - amount)
	return true
end

return InventoryService