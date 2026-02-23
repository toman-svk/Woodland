-- src/client/Dialogue.client.luau
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = Shared:WaitForChild("Remotes")
local openDialogue = Remotes:WaitForChild("OpenDialogue")

local player = Players.LocalPlayer

-- Create UI
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "DialogueGui"
screenGui.ResetOnSpawn = false
screenGui.Parent = player:WaitForChild("PlayerGui")

local frame = Instance.new("Frame")
frame.Parent = screenGui
frame.AnchorPoint = Vector2.new(0.5, 0.5)
frame.Position = UDim2.fromScale(0.5, 0.75)
frame.Size = UDim2.fromOffset(520, 140)
frame.Visible = false
frame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
frame.BackgroundTransparency = 0.35
frame.BorderSizePixel = 0

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 14)
corner.Parent = frame

local padding = Instance.new("UIPadding")
padding.PaddingTop = UDim.new(0, 14)
padding.PaddingBottom = UDim.new(0, 14)
padding.PaddingLeft = UDim.new(0, 16)
padding.PaddingRight = UDim.new(0, 16)
padding.Parent = frame

local textLabel = Instance.new("TextLabel")
textLabel.Parent = frame
textLabel.Size = UDim2.fromScale(1, 1)
textLabel.BackgroundTransparency = 1
textLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
textLabel.TextWrapped = true
textLabel.TextXAlignment = Enum.TextXAlignment.Left
textLabel.TextYAlignment = Enum.TextYAlignment.Top
textLabel.TextSize = 22
textLabel.Font = Enum.Font.GothamMedium
textLabel.Text = ""

local function setDialogue(state: any)
	-- Fallback first (so you never see default "Label")
	local msg = ("[Unknown state: %s]"):format(tostring(state))

	if state == "QuestNotDone" then
		msg = "Collect 10 Wood and come back."
	elseif state == "QuestComplete" then
		msg = "Well done! Here is your Better Axe."
	elseif state == "AlreadyDone" then
		msg = "You already have the better axe!"
	elseif state == "NoWoodStat" then
		msg = "I can't see your Wood stat yet."
	end

	textLabel.Text = msg
end

openDialogue.OnClientEvent:Connect(function(state)
	print("[Dialogue] state=", state)

	frame.Visible = true
	setDialogue(state)

	task.delay(4, function()
		frame.Visible = false
	end)
end)