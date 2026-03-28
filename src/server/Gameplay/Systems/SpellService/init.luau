--!strict
-- src/server/Gameplay/Systems/SpellService/init.luau
--
-- SERVER-SIDE spell handler.
-- Listens to CastSpell remote events from clients and applies damage to enemies.
--
-- ── CURRENT SPELLS ────────────────────────────────────────────────────────────
-- "BasicStrike" — a forward-aimed melee strike.
--   • Normal cast:       BASE_SPELL_DAMAGE damage (disabled — spell always requires combo)
--   • Combo strike:      BASE_SPELL_DAMAGE × COMBO_MULTIPLIER damage
--     Triggered when payload.comboStrike == true (client consumed their combo to cast)
--
-- ── SECURITY NOTE ────────────────────────────────────────────────────────────
-- We trust the client on `comboStrike`. A cheater could always set it to true
-- and get the bonus damage. This is acceptable for this game's scope — the
-- server still validates that a real enemy exists in range, so they can't
-- deal infinite damage to targets that aren't there.
-- If you want server-side combo validation later, track hit counts in
-- CombatService and expose a GetCombo(player) function here.
--
-- ── HOW ENEMY DETECTION WORKS ────────────────────────────────────────────────
-- Instead of a thin raycast (which misses easily), we scan all alive enemies
-- in the world folder and pick the closest one within SPELL_RANGE studs.
-- This is the same approach CombatService uses for normal attacks.

local Players             = game:GetService("Players")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local WorldService = require(
	ServerScriptService
		:WaitForChild("Server")
		:WaitForChild("Gameplay")
		:WaitForChild("World")
		:WaitForChild("Runtime")
		:WaitForChild("WorldService")
)

local ObjectWiggle = require(
	ServerScriptService
		:WaitForChild("Server")
		:WaitForChild("Gameplay")
		:WaitForChild("Systems")
		:WaitForChild("ObjectWiggle")
)

local Shared    = ReplicatedStorage:WaitForChild("Shared")
local Remotes   = Shared:WaitForChild("Remotes")
local CastSpell = Remotes:WaitForChild("CastSpell")  :: RemoteEvent
local CombatHit = Remotes:WaitForChild("CombatHit")  :: RemoteEvent

-- ── Tuning ────────────────────────────────────────────────────────────────────

local COOLDOWN          = 1.0   -- server-enforced minimum seconds between casts
local SPELL_RANGE       = 12    -- studs: how far the spell can reach
local BASE_SPELL_DAMAGE = 10    -- damage for a non-combo cast
local COMBO_MULTIPLIER  = 2     -- combo strike multiplies damage by this

-- ── State ─────────────────────────────────────────────────────────────────────

local lastCast: { [Player]: number } = {}

-- ── Helpers ───────────────────────────────────────────────────────────────────

local function getCharHumRoot(player: Player): (Model?, Humanoid?, BasePart?)
	local character = player.Character
	if not character then return nil, nil, nil end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return character, nil, nil end

	local root = character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return character, humanoid, nil
	end

	return character, humanoid, root
end

local function isAlive(h: Humanoid?): boolean
	return h ~= nil and (h :: Humanoid).Health > 0
end

local function canCast(player: Player): boolean
	local now  = os.clock()
	local last = lastCast[player]
	if last and (now - last) < COOLDOWN then
		return false
	end
	lastCast[player] = now
	return true
end

-- Returns the Enemies folder from the current world, or nil if unavailable.
local function getEnemiesFolder(): Folder?
	local world = WorldService.GetCurrentWorld()
	if not world then return nil end
	local enemies = world.generated:FindFirstChild("Enemies")
	if enemies and enemies:IsA("Folder") then
		return enemies :: Folder
	end
	return nil
end

-- Finds the closest alive enemy (IsEnemy = true) within `range` studs of `origin`.
-- Returns the enemy Model, or nil if none found.
local function getNearestEnemyInRange(origin: Vector3, range: number): Model?
	local folder = getEnemiesFolder()
	if not folder then return nil end

	local best: Model?  = nil
	local bestDist      = range  -- anything farther than range is automatically excluded

	for _, inst in ipairs(folder:GetChildren()) do
		if not inst:IsA("Model") then continue end
		if inst:GetAttribute("IsEnemy") ~= true then continue end

		local enemy = inst :: Model
		local hum   = enemy:FindFirstChildOfClass("Humanoid")
		if not hum or hum.Health <= 0 then continue end

		local hrp = enemy:FindFirstChild("HumanoidRootPart")
		if not hrp or not hrp:IsA("BasePart") then continue end

		local dist = ((hrp :: BasePart).Position - origin).Magnitude
		if dist < bestDist then
			bestDist = dist
			best     = enemy
		end
	end

	return best
end

-- ── Main handler ──────────────────────────────────────────────────────────────

local function onCastSpell(player: Player, payload: any)
	-- Validate that the payload is a table (basic sanity check).
	if typeof(payload) ~= "table" then return end

	-- Server-side cooldown — mirrors the client cooldown as a cheat prevention layer.
	if not canCast(player) then return end

	local character, humanoid, root = getCharHumRoot(player)
	if not character or not isAlive(humanoid) or not root then return end

	-- Calculate damage.
	-- comboStrike is set by Spells.luau when the player consumed their combo to cast.
	local damage = BASE_SPELL_DAMAGE
	if payload.comboStrike == true then
		damage = damage * COMBO_MULTIPLIER
	end

	-- Find the closest alive enemy within spell range.
	local target = getNearestEnemyInRange((root :: BasePart).Position, SPELL_RANGE)
	if not target then return end

	local targetHum = target:FindFirstChildOfClass("Humanoid")
	if not targetHum or targetHum.Health <= 0 then return end

	-- Deal damage.
	targetHum:TakeDamage(damage)

	-- Visual + audio hit feedback.
	-- ObjectWiggle makes the skeleton react visually to the hit.
	-- CombatHit shows the floating damage number on all clients.
	-- Including `player` as the first arg lets ComboCounter know who cast this
	-- (the spell hit starts a new combo — 1 hit — just like a normal attack).
	ObjectWiggle.Wiggle(target, ObjectWiggle.Presets.Skeleton)
	CombatHit:FireAllClients(player, target, damage)

	-- If the spell killed the enemy, clean it up after a short delay
	-- so the death animation can play before the model disappears.
	if targetHum.Health <= 0 then
		task.delay(2, function()
			if target.Parent then
				target:Destroy()
			end
		end)
	end
end

-- ── Module ────────────────────────────────────────────────────────────────────

local SpellService = {}
local started      = false

function SpellService.Start()
	if started then return end
	started = true

	CastSpell.OnServerEvent:Connect(onCastSpell)

	Players.PlayerRemoving:Connect(function(player)
		lastCast[player] = nil
	end)

	print("[SpellService] Started.")
end

return SpellService
