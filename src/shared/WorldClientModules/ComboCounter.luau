--!strict
-- src/shared/WorldClientModules/ComboCounter.luau
--
-- Displays a hit-combo counter at the top-centre of the screen.
-- Shows up when the local player lands hits in quick succession,
-- plays a "pop" animation on each new hit, and fades away after
-- COMBO_TIMEOUT seconds of not hitting anything.
--
-- ── PUBLIC API (used by Spells.luau) ─────────────────────────────────────────
--   M.GetCombo()           → returns the current combo count as a number
--   M.OnComboChanged(fn)   → registers a listener called every time the count changes
--   M.ConsumeCombo()       → resets combo to 0 and hides the display immediately
--                            (called by Spells.luau when the player uses Q spell)
--
-- ── HOW THE DATA FLOWS ───────────────────────────────────────────────────────
--   Player presses F / left-click
--     → CombatService deals damage, fires CombatHit(attacker, target, damage)
--       → ComboCounter checks if attacker == LocalPlayer
--           → onHit(): increment count, animate, notify listeners, restart timer
--
-- ── HOW COMBO TIMEOUT WORKS ──────────────────────────────────────────────────
-- After each hit we schedule task.delay(COMBO_TIMEOUT, tryReset).
-- If another hit lands before the delay fires, we bump `generation`.
-- The delayed callback checks if generation changed — if it has, it exits
-- without resetting, because a newer hit already owns the timer.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")

local player = Players.LocalPlayer

local Shared        = ReplicatedStorage:WaitForChild("Shared")
local RemotesFolder = Shared:WaitForChild("Remotes")
local GetRemote     = require(RemotesFolder:WaitForChild("GetRemote"))
local hitEvent      = GetRemote("CombatHit", "RemoteEvent") :: RemoteEvent

-- ── Tuning ────────────────────────────────────────────────────────────────────

local COMBO_TIMEOUT = 5   -- seconds of no hits before combo resets
local SCREEN_Y      = 0.08  -- vertical position (0 = top, 1 = bottom)
local POP_SCALE     = 1.35  -- how big the number jumps on each hit
local POP_TIME      = 0.18  -- seconds for the spring to settle back to 1.0
local FADE_TIME     = 0.35  -- seconds for the fade-out when combo expires

local TIERS: { { count: number, color: Color3, label: string } } = {
	{ count = 20, color = Color3.fromRGB(200,  80, 255), label = "ULTRA COMBO!" },
	{ count = 15, color = Color3.fromRGB(255,  60,  60), label = "MEGA COMBO!"  },
	{ count = 10, color = Color3.fromRGB(255, 150,  30), label = "GREAT COMBO!" },
	{ count =  5, color = Color3.fromRGB(255, 220,  40), label = "COMBO!"       },
	{ count =  1, color = Color3.fromRGB(255, 255, 255), label = "COMBO"        },
}

-- ── State ─────────────────────────────────────────────────────────────────────

local comboCount = 0
local generation = 0
local guiVisible = false

-- Listeners registered via M.OnComboChanged().
-- Each entry is a function(newCount: number) that gets called whenever the
-- combo changes — including when it resets to 0.
-- task.spawn is used when calling them so an error in one listener
-- doesn't break the others or the counter itself.
local comboListeners: { (number) -> () } = {}

local function notifyListeners(count: number)
	for _, fn in ipairs(comboListeners) do
		task.spawn(fn, count)
	end
end

-- ── GUI construction ──────────────────────────────────────────────────────────

local playerGui = player:WaitForChild("PlayerGui")

local screenGui = Instance.new("ScreenGui")
screenGui.Name           = "ComboCounter"
screenGui.ResetOnSpawn   = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.IgnoreGuiInset = true
screenGui.Parent         = playerGui

local frame = Instance.new("Frame")
frame.Name                = "ComboFrame"
frame.BackgroundTransparency = 1
frame.AnchorPoint         = Vector2.new(0.5, 0)
frame.Position            = UDim2.new(0.5, 0, SCREEN_Y, 0)
frame.Size                = UDim2.new(0, 260, 0, 110)
frame.Visible             = false
frame.Parent              = screenGui

-- UIScale lets TweenService animate the whole frame's size proportionally.
local uiScale = Instance.new("UIScale")
uiScale.Scale  = 1
uiScale.Parent = frame

local numberLabel = Instance.new("TextLabel")
numberLabel.Name                   = "Number"
numberLabel.BackgroundTransparency = 1
numberLabel.Size                   = UDim2.new(1, 0, 0.65, 0)
numberLabel.Position               = UDim2.new(0, 0, 0, 0)
numberLabel.Text                   = "0"
numberLabel.TextScaled             = true
numberLabel.Font                   = Enum.Font.GothamBlack
numberLabel.TextColor3             = Color3.fromRGB(255, 255, 255)
numberLabel.TextStrokeTransparency = 0.3
numberLabel.Parent                 = frame

local labelText = Instance.new("TextLabel")
labelText.Name                   = "Label"
labelText.BackgroundTransparency = 1
labelText.Size                   = UDim2.new(1, 0, 0.35, 0)
labelText.Position               = UDim2.new(0, 0, 0.65, 0)
labelText.Text                   = "COMBO"
labelText.TextScaled             = true
labelText.Font                   = Enum.Font.GothamBold
labelText.TextColor3             = Color3.fromRGB(255, 255, 255)
labelText.TextStrokeTransparency = 0.4
labelText.Parent                 = frame

-- ── Helpers ───────────────────────────────────────────────────────────────────

local function getTier(count: number): { color: Color3, label: string }
	for _, tier in ipairs(TIERS) do
		if count >= tier.count then
			return tier
		end
	end
	return TIERS[#TIERS]
end

local function cancelFade()
	numberLabel.TextTransparency       = 0
	numberLabel.TextStrokeTransparency = 0.3
	labelText.TextTransparency         = 0
	labelText.TextStrokeTransparency   = 0.4
end

local currentPopTween: Tween? = nil

local function playPop()
	if currentPopTween then
		currentPopTween:Cancel()
	end
	uiScale.Scale = POP_SCALE
	local info  = TweenInfo.new(POP_TIME, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out)
	local tween = TweenService:Create(uiScale, info, { Scale = 1.0 })
	tween:Play()
	currentPopTween = tween
end

local function fadeOut()
	local info = TweenInfo.new(FADE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(numberLabel, info, {
		TextTransparency       = 1,
		TextStrokeTransparency = 1,
	}):Play()
	local lTween = TweenService:Create(labelText, info, {
		TextTransparency       = 1,
		TextStrokeTransparency = 1,
	})
	lTween:Play()
	lTween.Completed:Connect(function()
		frame.Visible = false
		guiVisible    = false
	end)
end

local function tryReset(gen: number)
	if gen ~= generation then
		return  -- a newer hit came in; this timer is stale
	end
	comboCount = 0
	notifyListeners(0)  -- tell Spells.luau the combo dropped to 0 → hide Q indicator
	fadeOut()
end

-- ── Main update ───────────────────────────────────────────────────────────────

local function onHit()
	comboCount += 1
	generation += 1
	local thisGen = generation

	local tier = getTier(comboCount)

	cancelFade()
	frame.Visible = true
	guiVisible    = true

	numberLabel.Text       = tostring(comboCount)
	numberLabel.TextColor3 = tier.color
	labelText.Text         = tier.label
	labelText.TextColor3   = tier.color

	playPop()

	-- Notify any subscribers (e.g. Spells.luau) that the combo count changed.
	notifyListeners(comboCount)

	task.delay(COMBO_TIMEOUT, function()
		tryReset(thisGen)
	end)
end

-- ── Module ────────────────────────────────────────────────────────────────────

local M = {}

-- Returns the current combo count.
-- Call this from Spells.luau inside cast() to check if the player is eligible.
function M.GetCombo(): number
	return comboCount
end

-- Registers a callback that fires whenever the combo count changes.
-- The callback receives the new count (0 = just reset, >0 = hit landed).
-- Multiple listeners can be registered; all are called independently.
--
-- Example usage in Spells.luau:
--   ComboCounter.OnComboChanged(function(count)
--       if count > COMBO_THRESHOLD then showQIndicator() else hideQIndicator() end
--   end)
function M.OnComboChanged(fn: (number) -> ())
	table.insert(comboListeners, fn)
end

-- Immediately resets the combo to 0 and hides the display.
-- Call this from Spells.luau BEFORE firing the spell remote so that:
--   1. The combo counter disappears as immediate feedback that the spell consumed it.
--   2. The Q indicator hides (via the listener notified here).
function M.ConsumeCombo()
	comboCount = 0
	generation += 1    -- invalidate any pending timeout timers
	notifyListeners(0) -- hide Q indicator in Spells.luau
	fadeOut()
end

function M.Start()
	hitEvent.OnClientEvent:Connect(function(attacker: Player, _target: Model, _damage: number)
		if attacker ~= player then return end
		onHit()
	end)
	print("[ComboCounter] Started.")
end

return M
