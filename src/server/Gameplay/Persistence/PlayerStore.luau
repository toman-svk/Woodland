-- per-player data if you keep any separate (optional)--!strict
-- src/server/InitStats.server.luau

local Players = game:GetService("Players")

Players.PlayerAdded:Connect(function(player: Player)
	local stats = player:FindFirstChild("Stats")
	if not (stats and stats:IsA("Folder")) then
		stats = Instance.new("Folder")
		stats.Name = "Stats"
		stats.Parent = player
	end
	local statsFolder = stats :: Folder

	local mana = Instance.new("NumberValue")
	mana.Name = "Mana"
	mana.Value = 100
	mana.Parent = statsFolder

	local maxMana = Instance.new("NumberValue")
	maxMana.Name = "MaxMana"
	maxMana.Value = 100
	maxMana.Parent = statsFolder

	local day = Instance.new("IntValue")
	day.Name = "Day"
	day.Value = 1
	day.Parent = statsFolder

	local daysPlayed = Instance.new("IntValue")
	daysPlayed.Name = "DaysPlayed"
	daysPlayed.Value = 1
	daysPlayed.Parent = statsFolder
end)