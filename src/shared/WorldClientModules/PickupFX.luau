--!strict
-- src/shared/WorldClientModules/PickupFX.luau

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

local player = Players.LocalPlayer
if not player then
	warn("[PickupFX] LocalPlayer missing")
	return {} -- must return exactly one value (ModuleScript)
end

local Shared = ReplicatedStorage:WaitForChild("Shared")
local RemotesFolder = Shared:WaitForChild("Remotes")
local GetRemote = require(RemotesFolder:WaitForChild("GetRemote"))

local PickupFX = GetRemote("PickupFX", "RemoteEvent") :: RemoteEvent

local PICKUP_SOUND_ID = "rbxassetid://140562468516526"

local function getHRP(): BasePart?
	local char = player.Character
	if not char then return nil end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:IsA("BasePart") then
		return hrp
	end
	return nil
end

local function playPickupSound(parentPart: BasePart)
	local s = Instance.new("Sound")
	s.Name = "WoodPickupSFX"
	s.SoundId = PICKUP_SOUND_ID
	s.Volume = 0.8
	s.PlaybackSpeed = 1
	s.RollOffMaxDistance = 60
	s.Looped = false
	s.PlayOnRemove = true
	s.Parent = parentPart
	s:Destroy()
end

local M = {}
local started = false

function M.Start()
	if started then return end
	started = true

	PickupFX.OnClientEvent:Connect(function(logPart: BasePart)
		if not logPart or not logPart:IsA("BasePart") then return end

		local hrp = getHRP()
		if not hrp then return end

		playPickupSound(hrp)

		local ghost = logPart:Clone()
		ghost.Anchored = true
		ghost.CanCollide = false
		ghost.CanQuery = false
		ghost.CanTouch = false
		ghost.Parent = workspace

		ghost.CFrame = logPart.CFrame
		local goal = hrp.CFrame * CFrame.new(0, 1.5, -1)

		local tween = TweenService:Create(
			ghost,
			TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ CFrame = goal }
		)
		tween:Play()
		tween.Completed:Connect(function()
			if ghost then ghost:Destroy() end
		end)
	end)
end

return M