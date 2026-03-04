--!strict
-- src/shared/WorldClientModules/Sprint.luau

local UIS = game:GetService("UserInputService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local RemotesFolder = Shared:WaitForChild("Remotes")
local GetRemote = require(RemotesFolder:WaitForChild("GetRemote"))

local sprintEvent = GetRemote("SprintToggle", "RemoteEvent") :: RemoteEvent

local NORMAL_SPEED = 16
local SPRINT_SPEED = 28
local SPRINT_KEY = Enum.KeyCode.LeftShift

local player = Players.LocalPlayer
local humanoid: Humanoid? = nil
local isSprinting = false

local function log(...)
	print("[Sprint]", ...)
end

local function bindCharacter(character: Model)
	local hum = character:FindFirstChildOfClass("Humanoid")
	if not hum then
		task.defer(function()
			local hum2 = character:FindFirstChildOfClass("Humanoid")
			if hum2 then
				humanoid = hum2
				isSprinting = false
				hum2.WalkSpeed = NORMAL_SPEED
				log("Bound character (deferred)")
			end
		end)
		return
	end

	humanoid = hum
	isSprinting = false
	hum.WalkSpeed = NORMAL_SPEED
	log("Bound character")
end

local function startSprint()
	local hum = humanoid
	if not hum or isSprinting then
		return
	end

	isSprinting = true
	hum.WalkSpeed = SPRINT_SPEED
	sprintEvent:FireServer(true)
	log("SPRINT ON")
end

local function stopSprint()
	local hum = humanoid
	if not hum or not isSprinting then
		return
	end

	isSprinting = false
	hum.WalkSpeed = NORMAL_SPEED
	sprintEvent:FireServer(false)
	log("SPRINT OFF")
end

local M = {}
local started = false

function M.Start()
	if started then return end
	started = true

	if player.Character then
		bindCharacter(player.Character)
	end
	player.CharacterAdded:Connect(bindCharacter)

	UIS.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then return end
		if input.KeyCode == SPRINT_KEY then
			startSprint()
		end
	end)

	UIS.InputEnded:Connect(function(input, gameProcessed)
		if gameProcessed then return end
		if input.KeyCode == SPRINT_KEY then
			stopSprint()
		end
	end)

	sprintEvent.OnClientEvent:Connect(function(serverSaysSprinting: boolean)
		if serverSaysSprinting == false then
			stopSprint()
		end
	end)
end

return M