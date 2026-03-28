--!strict
-- DayUI

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

local player = Players.LocalPlayer

local FADE_IN_TIME = 0.5
local SHOW_TIME = 1.8
local FADE_OUT_TIME = 0.7

local WELCOME_TEXT = "Welcome to Woodland"
local WELCOME_SHOW_TIME = 2.5

local function tween(object: Instance, time: number, props: {[string]: any})
	local info = TweenInfo.new(time, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	local tw = TweenService:Create(object, info, props)
	tw:Play()
	return tw
end

local function start()
	local playerGui = player:WaitForChild("PlayerGui")

	local dayGui = playerGui:WaitForChild("DayGui") :: ScreenGui
	local frame = dayGui:WaitForChild("Frame") :: Frame
	local label = frame:WaitForChild("TextLabel") :: TextLabel

	-- Force good layout from code
	frame.AnchorPoint = Vector2.new(0.5, 0.3)
	frame.Position = UDim2.new(0.5, 0, 0.3, 0)

	label.Size = UDim2.fromScale(1, 1)
	label.Position = UDim2.fromScale(0, 0)
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.TextYAlignment = Enum.TextYAlignment.Center

	label.Visible = false
	label.TextTransparency = 1
	label.TextStrokeTransparency = 1

	local shared = ReplicatedStorage:WaitForChild("Shared")
	local stateFolder = shared:WaitForChild("State")

	local currentDayValue = stateFolder:WaitForChild("CurrentDay") :: IntValue

	local lastDay = currentDayValue.Value
	local showingToken = 0

	local function showPopup(text: string, holdTime: number)
		showingToken += 1
		local token = showingToken

		label.Text = text
		label.Visible = true
		label.TextTransparency = 1
		label.TextStrokeTransparency = 1

		tween(label, FADE_IN_TIME, {
			TextTransparency = 0,
			TextStrokeTransparency = 0.35,
		})

		task.delay(FADE_IN_TIME + holdTime, function()
			if token ~= showingToken then
				return
			end

			tween(label, FADE_OUT_TIME, {
				TextTransparency = 1,
				TextStrokeTransparency = 1,
			})

			task.delay(FADE_OUT_TIME, function()
				if token ~= showingToken then
					return
				end

				label.Visible = false
			end)
		end)
	end

	-- Welcome popup on join
	task.delay(0.8, function()
		showPopup(WELCOME_TEXT, WELCOME_SHOW_TIME)
	end)

	currentDayValue:GetPropertyChangedSignal("Value"):Connect(function()
		local newDay = currentDayValue.Value
		if newDay ~= lastDay then
			lastDay = newDay
			showPopup(("Day %d"):format(newDay), SHOW_TIME)
		end
	end)

	print("[DayUI] Started.")
end

return {
	Start = start,
}