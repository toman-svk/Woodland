--!strict
-- ServerScriptService/Server/Systems/ResourceSystem

local CollectionService = game:GetService("CollectionService")
local ServerScriptService = game:GetService("ServerScriptService")

local TreeWiggle = require(script.Parent:WaitForChild("TreeWiggle"))
local TreeSound = require(script.Parent:WaitForChild("TreeSound"))
local PickupService = require(script.Parent:WaitForChild("PickupService"))

-- WorldService is Rojo-synced under ServerScriptService/Server/Gameplay/World/Runtime/WorldService
-- If your folder names differ, adjust this path.
local WorldService = require(
	ServerScriptService:WaitForChild("Server")
		:WaitForChild("Gameplay")
		:WaitForChild("World")
		:WaitForChild("Runtime")
		:WaitForChild("WorldService")
)

local ResourceSystem = {}

local DEBUG = true
local function log(...)
	if DEBUG then
		print("[ResourceSystem]", ...)
	end
end

--========================
-- Config
--========================
local TREE_TAG = "Tree"
local HP_ATTR = "HP"
local BROKEN_ATTR = "Broken"

local WOOD_PER_HIT = 0
local WOOD_ON_BREAK = 5

local HIT_COOLDOWN = 0.25
local lastHit: {[number]: {[Instance]: number}} = {}

local function now(): number
	return os.clock()
end

local function getUserMap(player: Player): {[Instance]: number}
	local uid = player.UserId
	local map = lastHit[uid]
	if not map then
		map = {}
		lastHit[uid] = map
	end
	return map
end

local function canHit(player: Player, target: Instance): boolean
	local map = getUserMap(player)
	local t = map[target] or 0
	local n = now()
	if n - t < HIT_COOLDOWN then
		return false
	end
	map[target] = n
	return true
end

-- Always resolve to the tagged tree MODEL if possible.
local function resolveTreeTarget(hit: Instance): Instance?
	local model = hit:FindFirstAncestorOfClass("Model")
	if model and CollectionService:HasTag(model, TREE_TAG) then
		return model
	end
	if CollectionService:HasTag(hit, TREE_TAG) then
		return hit
	end
	return nil
end

local function getHP(target: Instance): number
	local hpAttr = target:GetAttribute(HP_ATTR)
	if typeof(hpAttr) == "number" then
		return hpAttr
	end

	local defaultHP = 30
	target:SetAttribute("MaxHP", defaultHP)
	target:SetAttribute(HP_ATTR, defaultHP)
	log("Assigned default HP =", defaultHP, "to", target:GetFullName())
	return defaultHP
end

local function setHP(target: Instance, hp: number)
	target:SetAttribute(HP_ATTR, hp)
end

local function getTreePosition(target: Instance): Vector3
	if target:IsA("Model") then
		local primary = target.PrimaryPart
		if primary then
			return primary.Position
		end
		local anyPart = target:FindFirstChildWhichIsA("BasePart", true)
		if anyPart then
			return anyPart.Position
		end
		return Vector3.zero
	elseif target:IsA("BasePart") then
		return target.Position
	end
	return Vector3.zero
end

--========================
-- Persistence helpers
--========================
local function ensureSaveTables(save: any)
	-- save: WorldSave
	if save.diffs == nil then
		save.diffs = { choppedTrees = {}, minedGems = {} }
	end
	if save.diffs.choppedTrees == nil then
		save.diffs.choppedTrees = {}
	end
	if save.diffs.minedGems == nil then
		save.diffs.minedGems = {}
	end
end

local function persistTreeChopped(treeTarget: Instance)
	-- We expect the tree model to have WorldObjectId set in SpawnTrees
	local idAttr = treeTarget:GetAttribute("WorldObjectId")
	if typeof(idAttr) ~= "string" then
		warn("[ResourceSystem] Tree has no string WorldObjectId attribute; cannot persist:", treeTarget:GetFullName())
		return
	end
	local id = idAttr :: string

	local getSave = WorldService.GetSave
	if not getSave then
		warn("[ResourceSystem] GetSave method not available; cannot persist chopped tree:", id)
		return
	end
	local save = getSave()
	local getWorldId = WorldService.GetWorldId
	if not getWorldId then
		warn("[ResourceSystem] GetWorldId method not available; cannot persist chopped tree:", id)
		return
	end
	local worldId = getWorldId()
	if not save or not worldId then
		warn("[ResourceSystem] No world/save available; cannot persist chopped tree:", id)
		return
	end

	ensureSaveTables(save);

	-- Mark as chopped + request autosave
	(save.diffs.choppedTrees :: {[string]: boolean})[id] = true
	local markDirty = WorldService.MarkDirty
	if markDirty then
		markDirty()
	end

	log("Persisted chopped tree:", id, "worldId=", worldId)
end

--========================
-- Public API
--========================
function ResourceSystem.DamageTreeFromHit(player: Player, hit: Instance, damage: number): boolean
	local treeTarget = resolveTreeTarget(hit)
	if not treeTarget then
		return false
	end

	if treeTarget:GetAttribute(BROKEN_ATTR) == true then
		return true
	end

	if not canHit(player, treeTarget) then
		return true
	end

	local hpBefore = getHP(treeTarget)
	local hpAfter = math.max(0, hpBefore - damage)
	setHP(treeTarget, hpAfter)

	log(
		"Tree hit:",
		treeTarget:GetFullName(),
		"| Damage:", damage,
		"| HP:", hpBefore, "->", hpAfter
	)

	-- Optional per-hit wood direct-to-inventory
	if WOOD_PER_HIT > 0 then
		local InventoryService = require(script.Parent:WaitForChild("InventoryService"))
		InventoryService.Add(player, "Wood", WOOD_PER_HIT)
	end

	-- ===== NON-KILL HIT =====
	if hpAfter > 0 then
		TreeSound.PlayImpact(treeTarget)
		TreeWiggle.Wiggle(treeTarget)
		return true
	end

	-- ===== KILL HIT =====
	treeTarget:SetAttribute(BROKEN_ATTR, true)

	-- ✅ PERSIST BEFORE DESTROY
	persistTreeChopped(treeTarget)

	local pos = getTreePosition(treeTarget)

	TreeSound.PlayImpactAt(pos)
	TreeSound.PlayBreakAt(pos)

	TreeWiggle.Wiggle(treeTarget)

	log("Tree BROKEN:", treeTarget:GetFullName())

	if WOOD_ON_BREAK > 0 then
		log("Spawning wood logs:", WOOD_ON_BREAK, "at", pos)
		PickupService.SpawnWoodLogs(pos, WOOD_ON_BREAK)
	end

	task.delay(0.12, function()
		if treeTarget and treeTarget.Parent then
			treeTarget:Destroy()
		end
	end)

	return true
end

return ResourceSystem