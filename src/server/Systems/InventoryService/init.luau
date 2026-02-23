--!strict
-- ServerScriptService/Systems/InventoryService
-- Minimal server-side inventory stored on the Player (replicates to client).
-- Not leaderstats. No DataStore yet (you can add later).

local Players = game:GetService("Players")

local InventoryService = {}

local INVENTORY_FOLDER_NAME = "Inventory"

local function getOrCreateInventoryFolder(player: Player): Folder
	local existing = player:FindFirstChild(INVENTORY_FOLDER_NAME)
	if existing and existing:IsA("Folder") then
		return existing
	end

	local folder = Instance.new("Folder")
	folder.Name = INVENTORY_FOLDER_NAME
	folder.Parent = player
	return folder
end

local function getOrCreateStack(player: Player, itemName: string): IntValue
	local inv = getOrCreateInventoryFolder(player)
	local existing = inv:FindFirstChild(itemName)
	if existing and existing:IsA("IntValue") then
		return existing
	end

	local v = Instance.new("IntValue")
	v.Name = itemName
	v.Value = 0
	v.Parent = inv
	return v
end

function InventoryService.Add(player: Player, itemName: string, amount: number)
	if amount <= 0 then return end
	local stack = getOrCreateStack(player, itemName)
	stack.Value += amount
end

function InventoryService.Get(player: Player, itemName: string): number
	local inv = player:FindFirstChild(INVENTORY_FOLDER_NAME)
	if not inv then return 0 end
	local stack = inv:FindFirstChild(itemName)
	if stack and stack:IsA("IntValue") then
		return stack.Value
	end
	return 0
end

function InventoryService.InitPlayer(player: Player)
    print("[InventoryService] InitPlayer", player.Name)
	-- ensures folder exists early (optional)
	getOrCreateInventoryFolder(player)
	-- you can precreate items if you want:
	getOrCreateStack(player, "Wood")
    getOrCreateStack(player, "Gold")
    print("[InventoryService] Inventory children:", #getOrCreateInventoryFolder(player):GetChildren())
end

-- Auto-init
Players.PlayerAdded:Connect(function(player)
	InventoryService.InitPlayer(player)
end)


for _, p in ipairs(Players:GetPlayers()) do
	InventoryService.InitPlayer(p)
end

return InventoryService