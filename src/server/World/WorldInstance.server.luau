--!strict
-- ServerScriptService/Server/World/WorldInstance.server.luau

local Players = game:GetService("Players")

local WorldService = require(script.Parent:WaitForChild("WorldService")) :: any

Players.PlayerAdded:Connect(function(player)
	WorldService.LoadPlayer(player)
end)

Players.PlayerRemoving:Connect(function(player)
	WorldService.UnloadPlayer(player)
end)

game:BindToClose(function()
	-- Best-effort save on shutdown
	for _, player in ipairs(Players:GetPlayers()) do
		WorldService.UnloadPlayer(player)
	end
end)

WorldService.ResetWorldEvent.OnServerEvent:Connect(function(player)
	WorldService.ResetPlayerWorld(player)
end)