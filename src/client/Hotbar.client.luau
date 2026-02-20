-- StarterPlayer/StarterPlayerScripts/Hotbar.client.lua
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer

-- UI
local playerGui = player:WaitForChild("PlayerGui")
local gui = playerGui:WaitForChild("HotbarGui")
local bar = gui:WaitForChild("Bar")

local SLOT_COUNT = 8
local slots = {}
for i = 1, SLOT_COUNT do
	slots[i] = bar:WaitForChild("Slot" .. i)
end

local function getBackpack(): Backpack
	return player.Backpack
end

local function listToolsIn(inst: Instance)
	local names = {}
	for _, c in ipairs(inst:GetChildren()) do
		if c:IsA("Tool") then
			table.insert(names, c.Name)
		end
	end
	return table.concat(names, ", ")
end

-- ✅ Correct signature: supports icon + count + name
local function setSlotVisual(i: number, iconId: string?, countText: string?, itemNameText: string?)
	local slot = slots[i]
	if not slot then return end

	local icon = slot:FindFirstChild("Icon")
	local count = slot:FindFirstChild("Count")
	local nameLabel = slot:FindFirstChild("ItemName")

	-- Reset
	if icon then icon.Visible = false end
	if count then count.Visible = false end
	if nameLabel then nameLabel.Visible = false end

	-- Icon
	if icon and iconId and iconId ~= "" then
		icon.Image = iconId
		icon.Visible = true
	end

	-- Text (AXE/WOOD)
	if nameLabel and itemNameText and itemNameText ~= "" then
		nameLabel.Text = itemNameText
		nameLabel.Visible = true
	end

	-- Count (wood amount)
	if count and countText and countText ~= "" then
		count.Text = countText
		count.Visible = true
	end
end

local function getCharacterTool(): Tool?
	local char = player.Character
	if not char then return nil end
	return char:FindFirstChildOfClass("Tool")
end

local function getToolInBackpack(): Tool?
	local bp = getBackpack()
	return bp and bp:FindFirstChildOfClass("Tool") or nil
end

local function refreshSlot1(reason: string?)
	local bp = getBackpack()
	local equipped = getCharacterTool()
	local inBag = getToolInBackpack()
	local tool = equipped or inBag

	local bpChildren = bp and #bp:GetChildren() or -1
	local bpTools = bp and listToolsIn(bp) or "no backpack"

	print(("[Hotbar] refreshSlot1 (%s) tool=%s | Backpack children=%d | tools=[%s] | bp=%s")
		:format(reason or "?", tool and tool.Name or "nil", bpChildren, bpTools, bp and bp:GetFullName() or "nil"))

	if tool then
		setSlotVisual(1, "", "", string.upper(tool.Name))
	else
		setSlotVisual(1, "", "", "")
	end
end

local function equipTool(tool: Tool?)
	if not tool then return end
	local char = player.Character
	if not char then return end
	tool.Parent = char
end

local function unequipAllTools()
	local char = player.Character
	if not char then return end
	local bp = getBackpack()
	for _, c in ipairs(char:GetChildren()) do
		if c:IsA("Tool") then
			c.Parent = bp
		end
	end
end

local function onHotkey1()
	print("[Hotbar] Key 1 pressed")

	local equipped = getCharacterTool()
	if equipped then
		unequipAllTools()
		refreshSlot1("unequip")
		return
	end

	local tool = getToolInBackpack()
	if not tool then
		warn("[Hotbar] No tool found in Backpack to equip.")
		refreshSlot1("equip_fail")
		return
	end

	equipTool(tool)
	refreshSlot1("equip_ok")
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
	if input.KeyCode == Enum.KeyCode.One then
		onHotkey1()
	end
end)

-- ✅ Resources: bind leaderstats.Wood to slot 2
local function bindResources()
	local leaderstats = player:WaitForChild("leaderstats", 10)
	if not leaderstats then
		warn("[Hotbar] No leaderstats found (Wood won't show).")
		return
	end

	local wood = leaderstats:WaitForChild("Wood", 10)
	if not wood then
		warn("[Hotbar] No leaderstats.Wood found (Wood won't show).")
		return
	end

	local function refreshWood()
		local v = wood.Value
		if v > 0 then
			setSlotVisual(2, "", tostring(v), "WOOD")
		else
			setSlotVisual(2, "", "", "")
		end
	end

	refreshWood()
	wood.Changed:Connect(refreshWood)

	print("[Hotbar] Bound Wood to slot 2.")
end

-- Rebind when character spawns
local function onCharacter(char: Model)
	task.spawn(function()
		for i = 1, 40 do
			refreshSlot1("startup_" .. i)
			if getToolInBackpack() or getCharacterTool() then break end
			task.wait(0.033)
		end
	end)

	char.ChildAdded:Connect(function(c)
		if c:IsA("Tool") then
			print("[Hotbar] Tool equipped:", c.Name)
			refreshSlot1("char_added")
		end
	end)

	char.ChildRemoved:Connect(function(c)
		if c:IsA("Tool") then
			print("[Hotbar] Tool unequipped:", c.Name)
			refreshSlot1("char_removed")
		end
	end)
end

player.CharacterAdded:Connect(onCharacter)
if player.Character then onCharacter(player.Character) end

task.spawn(function()
	task.wait(0.5)
	local bp = getBackpack()

	bp.ChildAdded:Connect(function(c)
		if c:IsA("Tool") then
			print("[Hotbar] Tool added to Backpack:", c.Name)
			refreshSlot1("bp_added")
		end
	end)

	bp.ChildRemoved:Connect(function(c)
		if c:IsA("Tool") then
			print("[Hotbar] Tool removed from Backpack:", c.Name)
			refreshSlot1("bp_removed")
		end
	end)

	refreshSlot1("bp_watch_ready")
end)

print("[Hotbar] Script running.")
task.spawn(bindResources)