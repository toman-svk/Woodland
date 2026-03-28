--!strict
-- src/client/StructureTimerBillboard.client.luau
--
-- Displays a construction timer billboard above any building that is currently
-- being constructed. Works for ALL building types automatically — no per-type
-- client code needed.
--
-- ── HOW IT WORKS ─────────────────────────────────────────────────────────────
-- BuildingService (server) sets these attributes on a Model when it's under
-- construction:
--
--   ConstructionActive   (boolean) – true while building
--   ConstructionEndTime  (number)  – os.time() when construction finishes
--   ConstructionDuration (number)  – total build time in seconds
--   ConstructionLabel    (string)  – e.g. "Building Trebuchet..."
--
-- This script watches workspace for any model with ConstructionActive = true
-- and attaches a BillboardGui timer to it. When ConstructionActive becomes
-- false the billboard hides automatically.
--
-- ── VISUAL DESIGN ────────────────────────────────────────────────────────────
-- Same style as BaseUpgradeBillboard (dark wooden card, golden accents,
-- MM:SS timer, progress bar). Both use the same visual language so the player
-- learns to recognise the pattern for any timed construction.

local Players   = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local UPDATE_INTERVAL = 0.1  -- seconds between timer refreshes

-- ── Helpers ───────────────────────────────────────────────────────────────────

local function formatTime(secondsLeft: number): string
	local safe    = math.max(0, math.floor(secondsLeft))
	local minutes = math.floor(safe / 60)
	local seconds = safe % 60
	return string.format("%02d:%02d", minutes, seconds)
end

-- Finds a suitable BasePart in the model to use as the BillboardGui's Adornee.
-- The Adornee is the 3D anchor the billboard floats above.
-- We prefer the PrimaryPart; otherwise use the first BasePart we find.
local function findAdornee(model: Model): BasePart?
	if model.PrimaryPart then return model.PrimaryPart end
	for _, inst in ipairs(model:GetDescendants()) do
		if inst:IsA("BasePart") then
			return inst
		end
	end
	return nil
end

-- ── Billboard factory ─────────────────────────────────────────────────────────
-- Creates one BillboardGui per building, parented to PlayerGui.
-- Adornee is set to a Part in the model so it floats in 3D space.
-- Using PlayerGui (not the model itself) means the GUI respects
-- the player's screen resolution and is hidden when they're too far away.

local BILLBOARD_OFFSET = Vector3.new(0, 14, 0)  -- studs above the adornee part
local BILLBOARD_SIZE   = UDim2.fromOffset(220, 70)
local MAX_DISTANCE     = 100  -- studs; billboard fades out beyond this

local function createBillboard(model: Model): BillboardGui
	-- Re-use an existing one if this model already has a billboard
	-- (e.g. from a previous session where the script reloaded).
	local existingName = "ConstructionTimer_" .. model:GetAttribute("BuildingUid") :: string
	local existing = playerGui:FindFirstChild(existingName)
	if existing and existing:IsA("BillboardGui") then
		return existing
	end

	-- ── BillboardGui ──────────────────────────────────────────────────────
	local billboard = Instance.new("BillboardGui")
	billboard.Name         = existingName
	billboard.Size         = BILLBOARD_SIZE
	billboard.StudsOffset  = BILLBOARD_OFFSET
	billboard.AlwaysOnTop  = true
	billboard.MaxDistance  = MAX_DISTANCE
	billboard.Enabled      = false  -- hidden until ConstructionActive = true
	billboard.Parent       = playerGui

	-- ── Root frame ────────────────────────────────────────────────────────
	-- Matches the BaseUpgradeBillboard visual style exactly so the player
	-- sees the same UI pattern for all construction activity in the world.
	local root = Instance.new("Frame")
	root.Name                   = "Root"
	root.Size                   = UDim2.fromScale(1, 1)
	root.BackgroundColor3       = Color3.fromRGB(32, 24, 18)
	root.BackgroundTransparency = 0.15
	root.BorderSizePixel        = 0
	root.Parent                 = billboard

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent       = root

	local stroke = Instance.new("UIStroke")
	stroke.Color     = Color3.fromRGB(180, 150, 95)
	stroke.Thickness = 2
	stroke.Parent    = root

	-- Title label (e.g. "Building Trebuchet...")
	local title = Instance.new("TextLabel")
	title.Name                   = "Title"
	title.BackgroundTransparency = 1
	title.Size                   = UDim2.new(1, -16, 0, 22)
	title.Position               = UDim2.new(0, 8, 0, 6)
	title.Font                   = Enum.Font.GothamBold
	title.Text                   = "Building..."
	title.TextColor3             = Color3.fromRGB(245, 230, 200)
	title.TextScaled             = false
	title.TextSize               = 16
	title.TextXAlignment         = Enum.TextXAlignment.Left
	title.Parent                 = root

	-- MM:SS countdown
	local timerLabel = Instance.new("TextLabel")
	timerLabel.Name                   = "Timer"
	timerLabel.BackgroundTransparency = 1
	timerLabel.Size                   = UDim2.new(1, -16, 0, 18)
	timerLabel.Position               = UDim2.new(0, 8, 0, 26)
	timerLabel.Font                   = Enum.Font.Gotham
	timerLabel.Text                   = "00:10"
	timerLabel.TextColor3             = Color3.fromRGB(255, 220, 140)
	timerLabel.TextScaled             = false
	timerLabel.TextSize               = 14
	timerLabel.TextXAlignment         = Enum.TextXAlignment.Left
	timerLabel.Parent                 = root

	-- Progress bar background track
	local barBg = Instance.new("Frame")
	barBg.Name            = "BarBg"
	barBg.Size            = UDim2.new(1, -16, 0, 16)
	barBg.Position        = UDim2.new(0, 8, 1, -24)
	barBg.BackgroundColor3 = Color3.fromRGB(60, 48, 38)
	barBg.BorderSizePixel = 0
	barBg.Parent          = root
	local barCorner = Instance.new("UICorner")
	barCorner.CornerRadius = UDim.new(0, 8)
	barCorner.Parent       = barBg

	-- Progress fill (grows left → right as time elapses)
	local fill = Instance.new("Frame")
	fill.Name             = "Fill"
	fill.Size             = UDim2.new(0, 0, 1, 0)
	fill.BackgroundColor3 = Color3.fromRGB(255, 190, 70)
	fill.BorderSizePixel  = 0
	fill.Parent           = barBg
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, 8)
	fillCorner.Parent       = fill

	return billboard
end

-- ── Per-building update ───────────────────────────────────────────────────────
-- Called every UPDATE_INTERVAL to refresh the countdown and progress bar.

local function updateBillboard(billboard: BillboardGui, model: Model)
	local adornee = findAdornee(model)
	if adornee and billboard.Adornee ~= (adornee :: Instance) then
		billboard.Adornee = adornee :: Instance
	end

	local active   = model:GetAttribute("ConstructionActive")
	local endTime  = model:GetAttribute("ConstructionEndTime")
	local duration = model:GetAttribute("ConstructionDuration")
	local label    = model:GetAttribute("ConstructionLabel")

	if active ~= true or type(endTime) ~= "number" or type(duration) ~= "number" then
		billboard.Enabled = false
		return
	end

	billboard.Enabled = true

	local now         = os.time()
	local secondsLeft = math.max(0, endTime - now)
	local elapsed     = math.clamp(duration - secondsLeft, 0, duration)
	local progress    = if duration > 0 then (elapsed / duration) else 1

	local root = billboard:FindFirstChild("Root") :: Frame?
	if not root then return end

	local titleLabel = root:FindFirstChild("Title") :: TextLabel?
	local timerLabel = root:FindFirstChild("Timer") :: TextLabel?
	local barBg      = root:FindFirstChild("BarBg") :: Frame?

	if titleLabel then
		titleLabel.Text = if type(label) == "string" then label else "Building..."
	end
	if timerLabel then
		timerLabel.Text = formatTime(secondsLeft)
	end
	if barBg then
		local fillFrame = barBg:FindFirstChild("Fill") :: Frame?
		if fillFrame then
			fillFrame.Size = UDim2.new(progress, 0, 1, 0)
		end
	end
end

-- ── Watching buildings ────────────────────────────────────────────────────────
-- We maintain one billboard per model.
-- When ConstructionActive becomes false, the billboard hides and we stop watching.

local billboardByModel: { [Model]: BillboardGui } = {}

local function watchModel(model: Model)
	if billboardByModel[model] then return end  -- already watching

	-- Only care about models that have been tagged by BuildingService.
	if not model:GetAttribute("BuildingUid") then return end

	local billboard = createBillboard(model)
	billboardByModel[model] = billboard

	-- React immediately to the current state.
	updateBillboard(billboard, model)

	-- Also react whenever ConstructionActive changes (set by server when done).
	model:GetAttributeChangedSignal("ConstructionActive"):Connect(function()
		updateBillboard(billboard, model)
	end)

	-- Clean up when the model is removed from the world.
	model.AncestryChanged:Connect(function()
		if not model.Parent then
			billboard:Destroy()
			billboardByModel[model] = nil
		end
	end)
end

-- ── Find the Buildings folder ─────────────────────────────────────────────────
-- Searches Workspace/Worlds/*/Generated/Buildings/ the same way
-- BaseUpgradeBillboard searches for SpawnHub.

local function findBuildingsFolder(): Folder?
	local worlds = Workspace:FindFirstChild("Worlds")
	if not (worlds and worlds:IsA("Folder")) then return nil end

	for _, world in ipairs(worlds:GetChildren()) do
		if world:IsA("Folder") then
			local generated = world:FindFirstChild("Generated")
			if generated and generated:IsA("Folder") then
				local buildings = generated:FindFirstChild("Buildings")
				if buildings and buildings:IsA("Folder") then
					return buildings :: Folder
				end
			end
		end
	end
	return nil
end

-- ── Main loop ─────────────────────────────────────────────────────────────────
-- Runs forever, periodically refreshing all active billboards.
-- Also watches for new buildings added to the folder.

local function run()
	-- Wait until the Buildings folder exists (world may not be generated yet).
	local buildingsFolder: Folder? = nil
	while buildingsFolder == nil do
		buildingsFolder = findBuildingsFolder()
		if buildingsFolder == nil then
			task.wait(1)
		end
	end

	local folder = buildingsFolder :: Folder

	-- Watch models already in the folder (restored from save).
	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("Model") then
			watchModel(child)
		end
	end

	-- Watch for new models added while the game is running (fresh placements).
	folder.ChildAdded:Connect(function(child)
		if child:IsA("Model") then
			watchModel(child)
		end
	end)

	-- Refresh timer countdown on all watched buildings periodically.
	-- We don't use RenderStepped here because the timer only needs ~10fps refresh.
	while true do
		for model, billboard in pairs(billboardByModel) do
			if model.Parent then
				-- Only update if the billboard is active (saves work).
				if model:GetAttribute("ConstructionActive") == true then
					updateBillboard(billboard, model)
				end
			end
		end
		task.wait(UPDATE_INTERVAL)
	end
end

task.spawn(run)
