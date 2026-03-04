-- (optional) remote setup for lobby UI

-- safeguard so it doesn't run outside of Lobby
local LOBBY_PLACE_ID = 131782889117139
if game.PlaceId ~= LOBBY_PLACE_ID then
	return
end