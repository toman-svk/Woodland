local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

local player = Players.LocalPlayer
local PickupFX = ReplicatedStorage:WaitForChild("PickupFX")

local function getHRP()
	local char = player.Character
	if not char then return nil end
	return char:FindFirstChild("HumanoidRootPart")
end

PickupFX.OnClientEvent:Connect(function(logPart: BasePart)
	if not logPart or not logPart:IsA("BasePart") then return end

	local hrp = getHRP()
	if not hrp then return end

	-- clone locally so the server can destroy the real one
	local ghost = logPart:Clone()
	ghost.Anchored = true
	ghost.CanCollide = false
	ghost.Parent = workspace

	-- start at log position, fly to player
	ghost.CFrame = logPart.CFrame
	local goal = hrp.CFrame * CFrame.new(0, 1.5, -1) -- near chest

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