--!strict
-- src/shared/WorldClientModules/UIScaler.luau
-- ModuleScript version (must return exactly one value).
-- Call UIScaler.Start() from ClientBootstrap.

local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui

local GUI_NAMES = {
	"ScreenGui",      -- Main HUD
	"ResourceHUD",
	"DayGui",
}

local function getOrCreateUIScale(gui: ScreenGui): UIScale
	local existing = gui:FindFirstChildOfClass("UIScale")
	if existing then
		return existing
	end
	local s = Instance.new("UIScale")
	s.Parent = gui
	return s
end

local function computeScale(viewport: Vector2): number
	local baseW = 900
	local baseH = 600
	local scaleW = viewport.X / baseW
	local scaleH = viewport.Y / baseH
	local s = math.min(scaleW, scaleH)
	return math.clamp(s, 0.3, 1.0)
end

local function fixDayGui(dayGui: ScreenGui)
	local frame = dayGui:FindFirstChild("Frame")
	if not (frame and frame:IsA("Frame")) then
		return
	end
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.42)
end

local function fixQButton(viewport: Vector2)
	local qButton: GuiButton? = nil

	for _, gui in ipairs(playerGui:GetDescendants()) do
		if gui:IsA("TextButton") and gui.Text == "Q" then
			qButton = gui
			break
		end
	end
	if not qButton then
		return
	end

	local isSmallScreen = (viewport.X <= 900) or UIS.TouchEnabled
	local sizeScale = isSmallScreen and 0.11 or 0.08

	qButton.AnchorPoint = Vector2.new(1, 1)
	qButton.Position = UDim2.fromScale(0.965, 0.93)
	qButton.Size = UDim2.fromScale(sizeScale, sizeScale)

	local corner = qButton:FindFirstChildOfClass("UICorner") or Instance.new("UICorner")
	corner.Parent = qButton
	corner.CornerRadius = UDim.new(1, 0)

	local aspect = qButton:FindFirstChildOfClass("UIAspectRatioConstraint") or Instance.new("UIAspectRatioConstraint")
	aspect.Parent = qButton
	aspect.AspectRatio = 1
end

local running = false
local camConn: RBXScriptConnection? = nil

local function apply()
	local cam = workspace.CurrentCamera
	local viewport = if cam then cam.ViewportSize else Vector2.new(900, 600)
	local scale = computeScale(viewport)

	for _, name in ipairs(GUI_NAMES) do
		local gui = playerGui:FindFirstChild(name)
		if gui and gui:IsA("ScreenGui") then
			local uiScale = getOrCreateUIScale(gui)
			if name == "DayGui" then
				uiScale.Scale = math.clamp(scale, 0.8, 1.0)
				fixDayGui(gui)
			else
				uiScale.Scale = scale
			end
		end
	end

	fixQButton(viewport)
end

local M = {}

function M.Start()
	if running then return end
	running = true

	apply()

	local cam = workspace.CurrentCamera
	if cam then
		camConn = cam:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			apply()
		end)
	end
end

return M