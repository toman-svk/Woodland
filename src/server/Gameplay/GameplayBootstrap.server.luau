--!strict
-- src/server/Gameplay/GameplayBootstrap.server.luau

local Players = game:GetService("Players")

local GAMEPLAY_PLACE_ID = 74640557554115

if game.PlaceId ~= GAMEPLAY_PLACE_ID then
	return
end

local WorldService = require(script.Parent.World.Runtime.WorldService)
local InventoryService = require(script.Parent.Systems.InventoryService)
local NPCService = require(script.Parent.NPC.NPCService)
local BaseUpgradeService = require(script.Parent.Systems.BaseUpgradeService)
local TimeDayCycleService = require(script.Parent.Systems.Time.TimeDayCycleService)
local CombatService   = require(script.Parent.Systems.CombatService)
local EnemyService    = require(script.Parent.Systems.EnemyService)
local SpellService    = require(script.Parent.Systems.SpellService)
local BuildingService = require(script.Parent.Systems.BuildingService)
local BallistaService = require(script.Parent.Systems.BallistaService)

if WorldService.Bootstrap then
	WorldService.Bootstrap()
end

task.defer(function()
	-- Wait until WorldService has finished the full bootstrap (terrain generation,
	-- hub placement, save applied) before reading the base level.
	-- Previously this used task.wait(1) which was a fixed delay that could fire
	-- before the world was ready, causing GetLevel() to return the fallback of 1.
	while WorldService.GetCurrentWorld() == nil do
		task.wait(0.5)
	end
	local level = BaseUpgradeService.GetLevel()
	local ok = BaseUpgradeService.ApplyLevel(level)
	print("[GameplayBootstrap] Applied base level:", level, "ok=", ok)
end)

local function initPlayer(player: Player)
	InventoryService.InitPlayer(player)
end

for _, player in ipairs(Players:GetPlayers()) do
	initPlayer(player)
end

Players.PlayerAdded:Connect(function(player)
	initPlayer(player)
end)

if NPCService.Start then
	NPCService.Start()
end

CombatService.Start()
EnemyService.Start()
SpellService.Start()
BuildingService.Start()
BallistaService.Start()

print("[GameplayBootstrap] WorldService bootstrapped for gameplay place.")
print("[GameplayBootstrap] InventoryService hooked.")
print("[GameplayBootstrap] NPCService started.")
print("[GameplayBootstrap] TimeDayCycleService loaded:", TimeDayCycleService ~= nil)
print("[GameplayBootstrap] CombatService started.")
print("[GameplayBootstrap] EnemyService started.")
print("[GameplayBootstrap] SpellService started.")