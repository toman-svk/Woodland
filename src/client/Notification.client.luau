--!strict
-- src/client/Notification.client.luau
--
-- Listens for ShowNotification remote events from the server and displays a
-- brief toast message at the top-centre of the screen.
--
-- Visual: dark rounded frame, white text, fades in → holds → fades out.
-- Multiple notifications queue and display one after another.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")

local player    = Players.LocalPlayer :: Player
local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui

-- ── Remote ────────────────────────────────────────────────────────────────────

local Shared    = ReplicatedStorage:WaitForChild("Shared")
local Remotes   = Shared:WaitForChild("Remotes")
local notifyRE  = Remotes:WaitForChild("ShowNotification") :: RemoteEvent

-- ── Constants ─────────────────────────────────────────────────────────────────

local FADE_TIME     = 0.25   -- seconds to fade in / out
local DEFAULT_HOLD  = 4      -- seconds the message is fully visible if no duration given
local BG_COLOR      = Color3.fromRGB(22, 18, 14)
local TEXT_COLOR    = Color3.fromRGB(255, 235, 180)
local STROKE_COLOR  = Color3.fromRGB(180, 130, 60)

-- ── Build the ScreenGui (created once, reused for all toasts) ─────────────────

local screenGui            = Instance.new("ScreenGui")
screenGui.Name             = "NotificationGui"
screenGui.ResetOnSpawn     = false
screenGui.ZIndexBehavior   = Enum.ZIndexBehavior.Sibling
screenGui.Enabled          = true
screenGui.Parent           = playerGui

local frame                = Instance.new("Frame")
frame.Name                 = "Toast"
frame.AnchorPoint          = Vector2.new(0.5, 0)
frame.Position             = UDim2.new(0.5, 0, 0.06, 0)
frame.Size                 = UDim2.new(0, 420, 0, 54)
frame.BackgroundColor3     = BG_COLOR
frame.BackgroundTransparency = 1  -- starts invisible
frame.BorderSizePixel      = 0
frame.Parent               = screenGui

local corner               = Instance.new("UICorner")
corner.CornerRadius        = UDim.new(0, 10)
corner.Parent              = frame

local stroke               = Instance.new("UIStroke")
stroke.Color               = STROKE_COLOR
stroke.Thickness           = 1.5
stroke.Transparency        = 1  -- hidden until shown
stroke.Parent              = frame

local label                = Instance.new("TextLabel")
label.Name                 = "Message"
label.Size                 = UDim2.new(1, -24, 1, 0)
label.Position             = UDim2.new(0, 12, 0, 0)
label.BackgroundTransparency = 1
label.Font                 = Enum.Font.GothamBold
label.TextSize             = 15
label.TextColor3           = TEXT_COLOR
label.TextTransparency     = 1  -- hidden until shown
label.TextXAlignment       = Enum.TextXAlignment.Center
label.TextYAlignment       = Enum.TextYAlignment.Center
label.TextWrapped          = true
label.Parent               = frame

-- ── Queue system (so rapid notifications don't overlap) ───────────────────────

type ToastPayload = { message: string, duration: number }
local queue: { ToastPayload } = {}
local showing = false

local function showNext()
	if showing or #queue == 0 then return end
	showing = true

	local payload = table.remove(queue, 1)
	local holdTime = math.max(1, payload.duration)

	label.Text = payload.message

	-- Fade IN
	local fadeIn = TweenService:Create(frame, TweenInfo.new(FADE_TIME, Enum.EasingStyle.Quad), {
		BackgroundTransparency = 0.15,
	})
	local fadeInText = TweenService:Create(label, TweenInfo.new(FADE_TIME, Enum.EasingStyle.Quad), {
		TextTransparency = 0,
	})
	local fadeInStroke = TweenService:Create(stroke, TweenInfo.new(FADE_TIME, Enum.EasingStyle.Quad), {
		Transparency = 0.3,
	})
	fadeIn:Play()
	fadeInText:Play()
	fadeInStroke:Play()
	fadeIn.Completed:Wait()

	-- Hold
	task.wait(holdTime)

	-- Fade OUT
	local fadeOut = TweenService:Create(frame, TweenInfo.new(FADE_TIME, Enum.EasingStyle.Quad), {
		BackgroundTransparency = 1,
	})
	local fadeOutText = TweenService:Create(label, TweenInfo.new(FADE_TIME, Enum.EasingStyle.Quad), {
		TextTransparency = 1,
	})
	local fadeOutStroke = TweenService:Create(stroke, TweenInfo.new(FADE_TIME, Enum.EasingStyle.Quad), {
		Transparency = 1,
	})
	fadeOut:Play()
	fadeOutText:Play()
	fadeOutStroke:Play()
	fadeOut.Completed:Wait()

	showing = false
	showNext()  -- process next item in queue
end

-- ── Listen for server events ──────────────────────────────────────────────────

notifyRE.OnClientEvent:Connect(function(payload: { message: string, duration: number? })
	if type(payload) ~= "table" then return end
	local msg = payload.message
	if type(msg) ~= "string" or #msg == 0 then return end

	table.insert(queue, {
		message  = msg,
		duration = if type(payload.duration) == "number" then payload.duration else DEFAULT_HOLD,
	})
	task.spawn(showNext)
end)
