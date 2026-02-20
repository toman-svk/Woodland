
local Players = game:GetService("Players")

Players.PlayerAdded:Connect(function(player)
	-- leaderstats optional; for HUD we can use a folder
	local stats = Instance.new("Folder")
	stats.Name = "Stats"
	stats.Parent = player

	local mana = Instance.new("NumberValue")
	mana.Name = "Mana"
	mana.Value = 100
	mana.Parent = stats

	local maxMana = Instance.new("NumberValue")
	maxMana.Name = "MaxMana"
	maxMana.Value = 100
	maxMana.Parent = stats
end)
