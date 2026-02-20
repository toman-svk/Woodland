-- src/server/LeaderStats.server.luau

local Players = game:GetService("Players")

Players.PlayerAdded:Connect(function(player)
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	leaderstats.Parent = player

	local wood = Instance.new("IntValue")
	wood.Name = "Wood"
	wood.Value = 0
	wood.Parent = leaderstats
end)