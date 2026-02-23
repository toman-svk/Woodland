--!strict
-- StarterPlayerScripts/UIScaler.client.luau
-- One script to scale/position multiple ScreenGuis for mobile.

local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui

-- Adjust these names to match your Explorer
local GUI_NAMES = {
	MainHUD = "ScreenGui",      -- your Health/Mana/Avatar GUI
	ResourceHUD = "ResourceHUD",
	DayGui = "DayGui",
}

-- Helper: get or create UIScale in a ScreenGui
local function getOrCreateUIScale(gui: ScreenGui): UIScale
	local existing = gui:FindFirstChildOfClass("UIScale")
	if existing then
		return existing
	end
	local s = Instance.new("UIScale")
	s.Parent = gui
	return s
end

-- Compute a “phone-friendly” scale factor.
-- Base design assumed around 900x600-ish. Change if your UI was designed on a different size.
local function computeScale(viewport: Vector2): number
	local baseW = 900
	local baseH = 600

	local scaleW = viewport.X / baseW
	local scaleH = viewport.Y / baseH

	-- Use smaller of the two so UI fits both directions.
	local s = math.min(scaleW, scaleH)

	-- Clamp so it doesn't become huge on big screens or tiny on very small ones
	return math.clamp(s, 0.3, 1.0)
end

-- DayGui positioning: centered horizontally, slightly above center vertically
local function fixDayGui(dayGui: ScreenGui, viewport: Vector2)
	-- Your structure: DayGui -> Frame -> TextLabel
	local frame = dayGui:FindFirstChild("Frame")
	if not (frame and frame:IsA("Frame")) then
		return
	end

	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.42) -- slightly above center
	-- Optional: ensure it doesn't get weird on mobile
	frame.SizeConstraint = Enum.SizeConstraint.RelativeXY
end

-- Find your spell "Q" button and make it smaller + circular.
-- This tries a few common patterns so you don't need to rename things.
local function fixQButton(viewport: Vector2)
	-- Search for a button with Text == "Q" somewhere in PlayerGui
	local qButton: GuiButton? = nil

	for _, gui in ipairs(playerGui:GetDescendants()) do
		if gui:IsA("TextButton") then
			if gui.Text == "Q" then
				qButton = gui
				break
			end
		elseif gui:IsA("ImageButton") then
			if gui.Name == "QButton" or gui.Name == "SpellButton" then
				qButton = gui
				break
			end
		end
	end

	if not qButton then
		return
	end

	-- Make it square and smaller on mobile.
	local isSmallScreen = (viewport.X <= 900) or UIS.TouchEnabled
	local sizeScale = isSmallScreen and 0.11 or 0.08 -- tweak

	qButton.AnchorPoint = Vector2.new(1, 1)
	qButton.Position = UDim2.fromScale(0.965, 0.93)
	qButton.Size = UDim2.fromScale(sizeScale, sizeScale)

	-- Force circle look (UICorner)
	local cornerInst = qButton:FindFirstChildOfClass("UICorner")
	local corner: UICorner
	if cornerInst and cornerInst:IsA("UICorner") then
		corner = cornerInst
	else
		corner = Instance.new("UICorner")
		corner.Parent = qButton
	end
	corner.CornerRadius = UDim.new(1, 0)

	-- Keep perfect circle (UIAspectRatioConstraint)
	local aspectInst = qButton:FindFirstChildOfClass("UIAspectRatioConstraint")
	local aspect: UIAspectRatioConstraint
	if aspectInst and aspectInst:IsA("UIAspectRatioConstraint") then
		aspect = aspectInst
	else
		aspect = Instance.new("UIAspectRatioConstraint")
		aspect.Parent = qButton
	end
	aspect.AspectRatio = 1
end

local function apply()
	local viewport = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(900, 600)
	local scale = computeScale(viewport)

	-- Scale main HUD + resource HUD
	for _, name in pairs(GUI_NAMES) do
		local gui = playerGui:FindFirstChild(name)
		if gui and gui:IsA("ScreenGui") then
			local uiScale = getOrCreateUIScale(gui)
			-- You may want DayGui not scaled (depending on your design).
			if name == "DayGui" then
				uiScale.Scale = math.clamp(scale, 0.8, 1.0) -- usually fine
				fixDayGui(gui, viewport)
			else
				uiScale.Scale = scale
			end
		end
	end

	-- Q button fix (independent of naming)
	fixQButton(viewport)
end

-- Run once, then update on resize (emulator changes viewport)
apply()

local cam = workspace.CurrentCamera
if cam then
	cam:GetPropertyChangedSignal("ViewportSize"):Connect(function()
		apply()
	end)
end