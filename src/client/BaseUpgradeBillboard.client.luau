--!strict
-- src/client/BaseUpgradeBillboard.client.luau

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer

local GUI_NAME = "BaseUpgradeBillboard"
local UPDATE_INTERVAL = 0.1

local BILLBOARD_SIZE = UDim2.fromOffset(220, 70)
local BILLBOARD_STUDS_OFFSET = Vector3.new(0, 18, 0)
local MAX_DISTANCE = 150

local function formatTime(secondsLeft: number): string
	local safe = math.max(0, math.floor(secondsLeft))
	local minutes = math.floor(safe / 60)
	local seconds = safe % 60
	return string.format("%02d:%02d", minutes, seconds)
end

local function findCurrentGeneratedFolder(): Folder?
	local worlds = Workspace:FindFirstChild("Worlds")
	if not (worlds and worlds:IsA("Folder")) then
		return nil
	end

	for _, world in ipairs(worlds:GetChildren()) do
		if world:IsA("Folder") then
			local generated = world:FindFirstChild("Generated")
			if generated and generated:IsA("Folder") then
				return generated
			end
		end
	end

	return nil
end

local function findSpawnHub(): Model?
	local generated = findCurrentGeneratedFolder()
	if not generated then
		return nil
	end

	for _, inst in ipairs(generated:GetDescendants()) do
		if inst:IsA("Model") and inst.Name == "SpawnHub" then
			return inst
		end
	end

	return nil
end

local function findAdorneePart(spawnHub: Model): BasePart?
	local house = spawnHub:FindFirstChild("House")
	if house and house:IsA("Model") then
		local primary = house.PrimaryPart
		if primary then
			return primary
		end

		for _, inst in ipairs(house:GetDescendants()) do
			if inst:IsA("BasePart") then
				return inst
			end
		end
	end

	for _, inst in ipairs(spawnHub:GetDescendants()) do
		if inst:IsA("BasePart") then
			return inst
		end
	end

	return nil
end

local function createGui(parent: PlayerGui): BillboardGui
	local existing = parent:FindFirstChild(GUI_NAME)
	if existing and existing:IsA("BillboardGui") then
		return existing
	end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = GUI_NAME
	billboard.Size = BILLBOARD_SIZE
	billboard.StudsOffset = BILLBOARD_STUDS_OFFSET
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = MAX_DISTANCE
	billboard.Enabled = false
	billboard.Parent = parent

	local root = Instance.new("Frame")
	root.Name = "Root"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundColor3 = Color3.fromRGB(32, 24, 18)
	root.BackgroundTransparency = 0.15
	root.BorderSizePixel = 0
	root.Parent = billboard

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = root

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(180, 150, 95)
	stroke.Thickness = 2
	stroke.Parent = root

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, -16, 0, 22)
	title.Position = UDim2.new(0, 8, 0, 6)
	title.Font = Enum.Font.GothamBold
	title.Text = "Upgrading Base..."
	title.TextColor3 = Color3.fromRGB(245, 230, 200)
	title.TextScaled = false
	title.TextSize = 16
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = root

	local timerLabel = Instance.new("TextLabel")
	timerLabel.Name = "Timer"
	timerLabel.BackgroundTransparency = 1
	timerLabel.Size = UDim2.new(1, -16, 0, 18)
	timerLabel.Position = UDim2.new(0, 8, 0, 26)
	timerLabel.Font = Enum.Font.Gotham
	timerLabel.Text = "01:00"
	timerLabel.TextColor3 = Color3.fromRGB(255, 220, 140)
	timerLabel.TextScaled = false
	timerLabel.TextSize = 14
	timerLabel.TextXAlignment = Enum.TextXAlignment.Left
	timerLabel.Parent = root

	local barBg = Instance.new("Frame")
	barBg.Name = "BarBg"
	barBg.Size = UDim2.new(1, -16, 0, 16)
	barBg.Position = UDim2.new(0, 8, 1, -24)
	barBg.BackgroundColor3 = Color3.fromRGB(60, 48, 38)
	barBg.BorderSizePixel = 0
	barBg.Parent = root

	local barBgCorner = Instance.new("UICorner")
	barBgCorner.CornerRadius = UDim.new(0, 8)
	barBgCorner.Parent = barBg

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.new(0, 0, 1, 0)
	fill.BackgroundColor3 = Color3.fromRGB(255, 190, 70)
	fill.BorderSizePixel = 0
	fill.Parent = barBg

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, 8)
	fillCorner.Parent = fill

	return billboard
end

local function updateBillboard(billboard: BillboardGui, spawnHub: Model)
    local adornee = findAdorneePart(spawnHub)
    if adornee and billboard.Adornee ~= (adornee :: Instance) then
        billboard.Adornee = adornee :: Instance
    end

	local active = spawnHub:GetAttribute("BaseUpgradeActive")
	local endTime = spawnHub:GetAttribute("BaseUpgradeEndTime")
	local duration = spawnHub:GetAttribute("BaseUpgradeDuration")
	local targetLevel = spawnHub:GetAttribute("BaseUpgradeTargetLevel")

	if active ~= true or type(endTime) ~= "number" or type(duration) ~= "number" then
		billboard.Enabled = false
		return
	end

	billboard.Enabled = true

	local now = os.time()
	local secondsLeft = math.max(0, endTime - now)
	local elapsed = math.clamp(duration - secondsLeft, 0, duration)
	local progress = if duration > 0 then (elapsed / duration) else 1

	local root = billboard:FindFirstChild("Root")
	if not (root and root:IsA("Frame")) then
		return
	end

	local title = root:FindFirstChild("Title")
	local timerLabel = root:FindFirstChild("Timer")
	local barBg = root:FindFirstChild("BarBg")

	if title and title:IsA("TextLabel") then
		if type(targetLevel) == "number" then
			title.Text = ("Upgrading Base to Lv.%d..."):format(targetLevel)
		else
			title.Text = "Upgrading Base..."
		end
	end

	if timerLabel and timerLabel:IsA("TextLabel") then
		timerLabel.Text = formatTime(secondsLeft)
	end

	if barBg and barBg:IsA("Frame") then
		local fill = barBg:FindFirstChild("Fill")
		if fill and fill:IsA("Frame") then
			fill.Size = UDim2.new(progress, 0, 1, 0)
		end
	end
end

local function run()
	local playerGui = player:WaitForChild("PlayerGui")
	local billboard = createGui(playerGui)

	while true do
		local spawnHub = findSpawnHub()
		if spawnHub then
			updateBillboard(billboard, spawnHub)
    else
        billboard.Enabled = false
    end

		task.wait(UPDATE_INTERVAL)
	end
end

task.spawn(run)