-- StarterPlayer/StarterPlayerScripts/HotbarSetup.client.lua

local Players = game:GetService("Players")
local player = Players.LocalPlayer

-- Create ScreenGui
local gui = Instance.new("ScreenGui")
gui.Name = "HotbarGui"
gui.ResetOnSpawn = false
gui.Parent = player:WaitForChild("PlayerGui")

-- Main bar container
local bar = Instance.new("Frame")
bar.Name = "Bar"
bar.Size = UDim2.new(0, 620, 0, 76)
bar.Position = UDim2.new(0.5, 0, 1, -10) -- closer to bottom
bar.AnchorPoint = Vector2.new(0.5, 1)
bar.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
bar.BackgroundTransparency = 0.2
bar.BorderSizePixel = 0
bar.Parent = gui

-- Rounded corners
local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 16)
corner.Parent = bar

-- Padding
local padding = Instance.new("UIPadding")
padding.PaddingLeft = UDim.new(0, 12)
padding.PaddingRight = UDim.new(0, 12)
padding.PaddingTop = UDim.new(0, 10)
padding.PaddingBottom = UDim.new(0, 10)
padding.Parent = bar

-- Layout
local layout = Instance.new("UIListLayout")
layout.FillDirection = Enum.FillDirection.Horizontal
layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
layout.VerticalAlignment = Enum.VerticalAlignment.Center
layout.Padding = UDim.new(0, 12)
layout.Parent = bar

-- Create slots
local SLOT_COUNT = 8
local SLOT_SIZE = 60

for i = 1, SLOT_COUNT do
	local slot = Instance.new("Frame")
	slot.Name = "Slot" .. i
	slot.Size = UDim2.fromOffset(SLOT_SIZE, SLOT_SIZE)
	slot.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
	slot.BorderSizePixel = 0
	slot.Parent = bar

	local slotCorner = Instance.new("UICorner")
	slotCorner.CornerRadius = UDim.new(0, 12)
	slotCorner.Parent = slot

	-- Icon placeholder (IMPORTANT: invisible by default + zindex)
	local icon = Instance.new("ImageLabel")
	icon.Name = "Icon"
	icon.Size = UDim2.fromScale(1, 1)
	icon.BackgroundTransparency = 1
	icon.Image = ""
	icon.Visible = false         -- ✅ important
	icon.ZIndex = 2
	icon.Parent = slot

	-- Item name text (AXE) (zindex above icon)
	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "ItemName"
	nameLabel.Size = UDim2.fromScale(1, 1)
	nameLabel.BackgroundTransparency = 1
	nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	nameLabel.TextScaled = true
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.Text = ""
	nameLabel.Visible = false
	nameLabel.ZIndex = 3
	nameLabel.Parent = slot

	-- Count label (invisible by default + higher zindex)
	local count = Instance.new("TextLabel")
	count.Name = "Count"
	count.Size = UDim2.new(1, -6, 0, 18)
	count.Position = UDim2.new(0, 3, 1, -20)
	count.BackgroundTransparency = 1
	count.TextColor3 = Color3.fromRGB(255, 255, 255)
	count.TextScaled = true
	count.Font = Enum.Font.GothamBold
	count.Text = ""
	count.Visible = false        -- ✅ important
	count.ZIndex = 4
	count.Parent = slot

	-- Key label (1–8) (always on top)
	local key = Instance.new("TextLabel")
	key.Name = "Key"
	key.Size = UDim2.new(0, 18, 0, 18)
	key.Position = UDim2.new(0, 4, 0, 4)
	key.BackgroundTransparency = 1
	key.TextColor3 = Color3.fromRGB(200, 200, 200)
	key.TextScaled = true
	key.Font = Enum.Font.Gotham
	key.Text = tostring(i)
	key.ZIndex = 5
	key.Parent = slot
end