
--!strict
-- src/server/Gameplay/GameConfigService.luau
-- Server-authoritative config exposed to clients via RemoteFunction GameConfig.

local ServerScriptService = game:GetService("ServerScriptService")

local Remotes = require(ServerScriptService.Server.Gameplay.Remotes)

local GameConfigService = {}

-- IMPORTANT: only send data that the client is allowed to know.
-- Keep it primitives-only (numbers/strings/bools) so it serializes safely.
local PUBLIC_CONFIG = {
	DayLengthSeconds = 120,
	DayPartRatio = 0.6,
	NightPartRatio = 0.4,

	PickupTweenSeconds = 0.25,

	TriggerDistanceQuestNPC = 25,

	-- Example movement values (if you want UI to display them)
	WalkSpeed = 16,
	SprintSpeed = 22,
}

function GameConfigService.Init()
	Remotes.GameConfig.OnServerInvoke = function(_player)
		return PUBLIC_CONFIG
	end
end

return GameConfigService