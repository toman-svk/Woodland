--!strict
-- src/server/Gameplay/Systems/ResourceService/init.luau
--
-- Central server-side handler for all destructible world resources:
--   • Trees   → chopped with Axe  → drops Wood logs
--   • Crystals → mined with Pickaxe → drops Gems
--
-- Each resource type follows the same lifecycle:
--   1. ToolServer script detects the physical hit (sphere overlap)
--   2. ToolServer calls the appropriate function here (DamageTreeFromHit / DamageCrystalFromHit)
--   3. This module checks tags, applies HP, plays feedback (sound + wiggle)
--   4. On death: persist the removal to the world save, spawn pickups, destroy the model
--
-- Adding a new resource type in the future:
--   1. Add TAG / HP / DROP config constants below
--   2. Write resolveXxxTarget, persistXxxMined, and DamageXxxFromHit
--      (copy the crystal section — they're identical in structure)
--   3. Add a corresponding SpawnXxx in PickupService
--   4. Call DamageXxxFromHit from the relevant tool's server script

local CollectionService   = game:GetService("CollectionService")
local ServerScriptService = game:GetService("ServerScriptService")

local ObjectWiggle   = require(script.Parent:WaitForChild("ObjectWiggle"))
local TreeSound      = require(script.Parent:WaitForChild("TreeSound"))
local PickupService  = require(script.Parent:WaitForChild("PickupService"))

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

-- ── Shared attribute names ─────────────────────────────────────────────────
-- Both trees and crystals use the same attribute keys on their models.
-- This keeps the HP / Broken logic completely reusable.
local HP_ATTR     = "HP"
local BROKEN_ATTR = "Broken"

-- ── Tree config ────────────────────────────────────────────────────────────
-- CollectionService tag that must be applied to each tree Model in Studio.
local TREE_TAG = "Tree"

-- How much wood drops when a tree dies.
-- WOOD_PER_HIT: award wood on every hit (useful for feel; set to 0 to disable).
-- WOOD_ON_BREAK: main reward when the tree is fully chopped.
local WOOD_PER_HIT  = 0
local WOOD_ON_BREAK = 5

-- Default HP assigned if the tree model has no HP attribute set in Studio.
local TREE_DEFAULT_HP = 30

-- Minimum seconds between two registered hits on the SAME tree by the SAME player.
-- Prevents spamming the remote faster than the animation plays.
local TREE_HIT_COOLDOWN = 0.25

-- ── Crystal config ─────────────────────────────────────────────────────────
local CRYSTAL_TAG = "Crystal"

local GEMS_PER_HIT  = 0   -- gems awarded each hit (set > 0 for incremental mining feel)
local GEMS_ON_BREAK = 3   -- gems awarded when the crystal is fully mined

local CRYSTAL_DEFAULT_HP = 50  -- crystals are tougher than trees

-- Pickaxe swings are slower (COOLDOWN = 0.55 in PickaxeServer), so we match
-- the crystal hit cooldown to that rhythm.
local CRYSTAL_HIT_COOLDOWN = 0.30

-- Sound IDs for crystal hit and break.
-- Replace these with real asset IDs when you have them.
-- For now they fall back gracefully to silence if the ID is empty.
local CRYSTAL_IMPACT_SOUND_ID = ""   -- TODO: fill in a mining impact sound
local CRYSTAL_BREAK_SOUND_ID  = ""   -- TODO: fill in a crystal shatter sound
local CRYSTAL_SOUND_VOLUME    = 0.8
local CRYSTAL_SOUND_DISTANCE  = 60

-- ── Shared hit-cooldown state ─────────────────────────────────────────────
-- Table layout: lastHit[userId][instanceRef] = timestamp
-- Each (player, resource instance) pair gets its own independent cooldown,
-- so hitting two different trees never blocks each other.
local lastHit: { [number]: { [Instance]: number } } = {}

local function now(): number
	return os.clock()
end

local function getUserMap(player: Player): { [Instance]: number }
	local uid = player.UserId
	local map = lastHit[uid]
	if not map then
		map = {}
		lastHit[uid] = map
	end
	return map
end

-- Returns true if the player is allowed to hit `target` right now.
-- `cooldown` is per-resource-type so trees and crystals can have different rates.
local function canHit(player: Player, target: Instance, cooldown: number): boolean
	local map = getUserMap(player)
	local lastTime = map[target] or 0
	if now() - lastTime < cooldown then
		return false
	end
	map[target] = now()
	return true
end

-- ── Shared HP helpers ─────────────────────────────────────────────────────

-- Returns the current HP of `target`, assigning a default if none is set.
local function getHP(target: Instance, defaultHP: number): number
	local attr = target:GetAttribute(HP_ATTR)
	if typeof(attr) == "number" then
		return attr
	end
	-- First hit — set both MaxHP and current HP so the UI can show a health bar later.
	target:SetAttribute("MaxHP", defaultHP)
	target:SetAttribute(HP_ATTR, defaultHP)
	log("Assigned default HP =", defaultHP, "to", target:GetFullName())
	return defaultHP
end

local function setHP(target: Instance, hp: number)
	target:SetAttribute(HP_ATTR, hp)
end

-- Returns the world position of a resource model.
-- Works for both Model and plain BasePart targets.
local function getModelPosition(target: Instance): Vector3
	if target:IsA("Model") then
		local primary = target.PrimaryPart
		if primary then return primary.Position end
		local anyPart = target:FindFirstChildWhichIsA("BasePart", true)
		if anyPart then return anyPart.Position end
		return Vector3.zero
	elseif target:IsA("BasePart") then
		return target.Position
	end
	return Vector3.zero
end

-- ── Shared persistence helpers ─────────────────────────────────────────────

local function ensureSaveTables(save: any)
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

-- Marks a resource as destroyed in the world save so it doesn't respawn.
-- `tableName` is which sub-table to write to ("choppedTrees" or "minedGems").
local function persistDestroyed(target: Instance, tableName: string, label: string)
	local idAttr = target:GetAttribute("WorldObjectId")
	if typeof(idAttr) ~= "string" then
		warn(("[ResourceSystem] %s has no WorldObjectId; cannot persist: %s"):format(
			label, target:GetFullName()
		))
		return
	end
	local id = idAttr :: string

	local save    = WorldService.GetSave and WorldService.GetSave()
	local worldId = WorldService.GetWorldId and WorldService.GetWorldId()
	if not save or not worldId then
		warn(("[ResourceSystem] No world save available; cannot persist %s: %s"):format(label, id))
		return
	end

	ensureSaveTables(save)
	;(save.diffs[tableName] :: { [string]: boolean })[id] = true

	if WorldService.MarkDirty then
		WorldService.MarkDirty()
	end

	log(("Persisted %s: %s (worldId=%s)"):format(label, id, worldId))
end

-- ── Crystal sound helpers ─────────────────────────────────────────────────
-- These mirror TreeSound but are inlined here since crystals don't have a
-- dedicated sound module yet. Once you have proper crystal SFX, extract this
-- into a CrystalSound module alongside TreeSound.

local Debris = game:GetService("Debris")

local function playCrystalSoundAt(pos: Vector3, soundId: string)
	if soundId == "" then return end  -- no asset set yet; skip silently

	-- Invisible emitter part — gives the sound a 3D position in the world.
	local emitter = Instance.new("Part")
	emitter.Name        = "CrystalSoundEmitter"
	emitter.Anchored    = true
	emitter.CanCollide  = false
	emitter.CanQuery    = false
	emitter.CanTouch    = false
	emitter.Transparency = 1
	emitter.Size        = Vector3.new(0.5, 0.5, 0.5)
	emitter.CFrame      = CFrame.new(pos)
	emitter.Parent      = workspace

	local s = Instance.new("Sound")
	s.SoundId            = soundId
	s.Volume             = CRYSTAL_SOUND_VOLUME
	s.RollOffMaxDistance = CRYSTAL_SOUND_DISTANCE
	s.PlaybackSpeed      = 0.95 + math.random() * 0.10  -- slight pitch variation
	s.Parent             = emitter
	s:Play()

	Debris:AddItem(emitter, 4)
end

-- ── Tree target resolver ───────────────────────────────────────────────────

-- Given any hit part, walks up the hierarchy to find the tagged tree Model.
-- Returns nil if the hit part is not part of a tree.
local function resolveTreeTarget(hit: Instance): Instance?
	-- Check the parent model first (most common case: hit a branch or trunk part).
	local model = hit:FindFirstAncestorOfClass("Model")
	if model and CollectionService:HasTag(model, TREE_TAG) then
		return model
	end
	-- Fallback: the hit instance itself is tagged (rare, e.g. a single-part tree).
	if CollectionService:HasTag(hit, TREE_TAG) then
		return hit
	end
	return nil
end

-- ── Crystal target resolver ────────────────────────────────────────────────

local function resolveCrystalTarget(hit: Instance): Instance?
	local model = hit:FindFirstAncestorOfClass("Model")
	if model and CollectionService:HasTag(model, CRYSTAL_TAG) then
		return model
	end
	if CollectionService:HasTag(hit, CRYSTAL_TAG) then
		return hit
	end
	return nil
end

-- ══════════════════════════════════════════════════════════════════════════════
-- PUBLIC API
-- ══════════════════════════════════════════════════════════════════════════════

-- ── DamageTreeFromHit ─────────────────────────────────────────────────────
-- Called by AxeServer when its sphere overlap hits something.
-- Returns true if the hit was on a tree (so AxeServer knows to stop processing).
-- Returns false if the hit was not a tree at all.
function ResourceSystem.DamageTreeFromHit(player: Player, hit: Instance, damage: number): boolean
	local target = resolveTreeTarget(hit)
	if not target then
		return false  -- not a tree; AxeServer should try other checks
	end

	-- Tree exists but is already destroyed this session — acknowledge the hit
	-- so AxeServer doesn't fall through to something else, but do nothing.
	if target:GetAttribute(BROKEN_ATTR) == true then
		return true
	end

	if not canHit(player, target, TREE_HIT_COOLDOWN) then
		return true  -- still a tree hit, just rate-limited
	end

	local hpBefore = getHP(target, TREE_DEFAULT_HP)
	local hpAfter  = math.max(0, hpBefore - damage)
	setHP(target, hpAfter)

	log("Tree hit:", target:GetFullName(), "| Damage:", damage, "| HP:", hpBefore, "->", hpAfter)

	if WOOD_PER_HIT > 0 then
		local InventoryService = require(script.Parent:WaitForChild("InventoryService"))
		InventoryService.Add(player, "Wood", WOOD_PER_HIT)
	end

	-- ── Non-fatal hit ──────────────────────────────────────────────────────
	if hpAfter > 0 then
		TreeSound.PlayImpact(target)
		ObjectWiggle.Wiggle(target, ObjectWiggle.Presets.Tree)
		return true
	end

	-- ── Fatal hit ─────────────────────────────────────────────────────────
	target:SetAttribute(BROKEN_ATTR, true)

	-- Persist BEFORE destroy so the save is updated even if Destroy() throws.
	persistDestroyed(target, "choppedTrees", "tree")

	local pos = getModelPosition(target)
	TreeSound.PlayImpactAt(pos)
	TreeSound.PlayBreakAt(pos)
	ObjectWiggle.Wiggle(target, ObjectWiggle.Presets.Tree)

	log("Tree BROKEN:", target:GetFullName())

	if WOOD_ON_BREAK > 0 then
		PickupService.SpawnWoodLogs(pos, WOOD_ON_BREAK)
	end

	-- Small delay before destroying so the wiggle animation has time to play.
	task.delay(0.12, function()
		if target and target.Parent then
			target:Destroy()
		end
	end)

	return true
end

-- ── DamageCrystalFromHit ──────────────────────────────────────────────────
-- Called by PickaxeServer when its sphere overlap hits something.
-- Returns true if the hit was on a crystal, false if not.
function ResourceSystem.DamageCrystalFromHit(player: Player, hit: Instance, damage: number): boolean
	local target = resolveCrystalTarget(hit)
	if not target then
		return false  -- not a crystal
	end

	if target:GetAttribute(BROKEN_ATTR) == true then
		return true  -- already mined this session
	end

	if not canHit(player, target, CRYSTAL_HIT_COOLDOWN) then
		return true
	end

	local hpBefore = getHP(target, CRYSTAL_DEFAULT_HP)
	local hpAfter  = math.max(0, hpBefore - damage)
	setHP(target, hpAfter)

	log("Crystal hit:", target:GetFullName(), "| Damage:", damage, "| HP:", hpBefore, "->", hpAfter)

	if GEMS_PER_HIT > 0 then
		local InventoryService = require(script.Parent:WaitForChild("InventoryService"))
		InventoryService.Add(player, "Gem", GEMS_PER_HIT)
	end

	-- ── Non-fatal hit ──────────────────────────────────────────────────────
	if hpAfter > 0 then
		playCrystalSoundAt(getModelPosition(target), CRYSTAL_IMPACT_SOUND_ID)
		ObjectWiggle.Wiggle(target, ObjectWiggle.Presets.Crystal)
		return true
	end

	-- ── Fatal hit ─────────────────────────────────────────────────────────
	target:SetAttribute(BROKEN_ATTR, true)

	persistDestroyed(target, "minedGems", "crystal")

	local pos = getModelPosition(target)
	playCrystalSoundAt(pos, CRYSTAL_IMPACT_SOUND_ID)
	playCrystalSoundAt(pos, CRYSTAL_BREAK_SOUND_ID)
	ObjectWiggle.Wiggle(target, ObjectWiggle.Presets.Crystal)

	log("Crystal MINED:", target:GetFullName())

	if GEMS_ON_BREAK > 0 then
		PickupService.SpawnGems(pos, GEMS_ON_BREAK)
	end

	task.delay(0.12, function()
		if target and target.Parent then
			target:Destroy()
		end
	end)

	return true
end

return ResourceSystem
