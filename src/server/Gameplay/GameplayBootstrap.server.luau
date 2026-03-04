--!strict
-- src/server/Gameplay/GameplayBootstrap.server.luau
-- Gameplay-place entrypoint. Loads/creates the world (by worldId from TeleportData), then generates it.
-- Safe with Rojo sync because it guards by PlaceId.

-- >>> YOUR PLACE IDS <<<
local LOBBY_PLACE_ID = 131782889117139
local GAMEPLAY_PLACE_ID = 74640557554115

-- Only run in the Gameplay place
if game.PlaceId ~= GAMEPLAY_PLACE_ID then
	return
end

local WorldService = require(script.Parent.World.Runtime.WorldService)

if WorldService.Bootstrap then
	WorldService.Bootstrap()
end

print("[GameplayBootstrap] WorldService bootstrapped for gameplay place.")