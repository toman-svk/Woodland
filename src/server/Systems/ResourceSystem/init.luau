--!strict
-- ServerScriptService/Server/Systems/ResourceSystem

local CollectionService = game:GetService("CollectionService")

local TreeWiggle = require(script.Parent:WaitForChild("TreeWiggle"))
local TreeSound = require(script.Parent:WaitForChild("TreeSound"))
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
		-- ✅ sound first, then wiggle (feels “same time”)
		TreeSound.PlayImpact(treeTarget)
		TreeWiggle.Wiggle(treeTarget)
		return true
	end

	-- ===== KILL HIT =====
	treeTarget:SetAttribute(BROKEN_ATTR, true)

	local pos = getTreePosition(treeTarget)

	-- ✅ On the kill hit, play sounds at position so they survive Destroy()
	TreeSound.PlayImpactAt(pos)
	TreeSound.PlayBreakAt(pos)

	-- Optional: still do a tiny wiggle before disappearing
	TreeWiggle.Wiggle(treeTarget)

	log("Tree BROKEN:", treeTarget:GetFullName())

	if WOOD_ON_BREAK > 0 then
		log("Spawning wood logs:", WOOD_ON_BREAK, "at", pos)
		PickupService.SpawnWoodLogs(pos, WOOD_ON_BREAK)
	end

	-- ✅ Delay destroy slightly so wiggle reads + audio starts cleanly
	task.delay(0.12, function()
		if treeTarget and treeTarget.Parent then
			treeTarget:Destroy()
		end
	end)

	return true
end

return ResourceSystem