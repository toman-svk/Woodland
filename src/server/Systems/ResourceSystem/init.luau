--!strict
-- ServerScriptService/Server/Systems/ResourceSystem
-- Damages resources (trees for now). When a tree breaks:
-- 1) Tree model disappears
-- 2) Wood log pickups spawn on the ground (count = WOOD_ON_BREAK) via PickupService
-- 3) Player must walk near each log; logs fly into the player
-- 4) Inventory Wood increases ONLY after each log is collected

local CollectionService = game:GetService("CollectionService")

local TreeWiggle = require(script.Parent:WaitForChild("TreeWiggle"))
local PickupService = require(script.Parent:WaitForChild("PickupService"))

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

-- Reward config
local WOOD_PER_HIT = 0      -- optional: goes straight to inventory (not pickups)
local WOOD_ON_BREAK = 5     -- number of wood LOGS to spawn when tree breaks

-- Anti-spam per player per target
local HIT_COOLDOWN = 0.25
local lastHit: {[number]: {[Instance]: number}} = {} -- userId -> (target -> time)

--========================
-- Time helpers
--========================
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

--========================
-- Tree target + HP
--========================
local function resolveTreeTarget(hit: Instance): Instance?
	-- Prefer model (so you damage one “tree entity” even if it has many parts)
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
-- Public API
--========================
function ResourceSystem.DamageTreeFromHit(player: Player, hit: Instance, damage: number): boolean
	local treeTarget = resolveTreeTarget(hit)
	if not treeTarget then
		return false
	end

	-- Already broken? Ignore, but treat as handled.
	if treeTarget:GetAttribute(BROKEN_ATTR) == true then
		return true
	end

	if not canHit(player, treeTarget) then
		return true
	end

	local hpBefore = getHP(treeTarget)
	local hpAfter = math.max(0, hpBefore - damage)
	setHP(treeTarget, hpAfter)

	TreeWiggle.Wiggle(treeTarget)

	log(
		"Tree hit:",
		treeTarget:GetFullName(),
		"| Damage:", damage,
		"| HP:", hpBefore, "->", hpAfter
	)

	-- Optional: per-hit wood goes straight to inventory (not pickups)
	if WOOD_PER_HIT > 0 then
		-- If you keep WOOD_PER_HIT enabled, PickupService should NOT also award for those logs.
		-- Leave WOOD_PER_HIT at 0 for your current "collect logs to gain wood" design.
		local InventoryService = require(script.Parent:WaitForChild("InventoryService"))
		InventoryService.Add(player, "Wood", WOOD_PER_HIT)
	end

	if hpAfter <= 0 then
		treeTarget:SetAttribute(BROKEN_ATTR, true)
		log("Tree BROKEN:", treeTarget:GetFullName())

		local pos = getTreePosition(treeTarget)

		if WOOD_ON_BREAK > 0 then
			log("Spawning wood logs:", WOOD_ON_BREAK, "at", pos)
			PickupService.SpawnWoodLogs(pos, WOOD_ON_BREAK)
		end

		-- Remove the tree entity so it disappears
		treeTarget:Destroy()
	end

	return true
end

return ResourceSystem