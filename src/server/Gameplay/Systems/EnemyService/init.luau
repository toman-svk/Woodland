--!strict
-- src/server/Gameplay/Systems/EnemyService/init.luau

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local WorldService = require(
	ServerScriptService:WaitForChild("Server")
		:WaitForChild("Gameplay")
		:WaitForChild("World")
		:WaitForChild("Runtime")
		:WaitForChild("WorldService")
)

-- BallistaService is required here so enemies can target and damage ballistae.
-- EnemyService → BallistaService is a one-way dependency (no cycle).
local BallistaService = require(
	ServerScriptService:WaitForChild("Server")
		:WaitForChild("Gameplay")
		:WaitForChild("Systems")
		:WaitForChild("BallistaService")
)

local Shared = ReplicatedStorage:WaitForChild("Shared")

local EnemyService = {}

local started = false
local currentPhase: "Day" | "Night" = "Day"

local MOVE_INTERVAL          = 0.4
local AGGRO_RANGE            = 40   -- range to initially spot a player or ballista
local DEAGGRO_RANGE          = 80   -- range at which the skeleton gives up chasing a player
local ATTACK_RANGE           = 4
local ATTACK_COOLDOWN        = 1.2
-- If a player steps within this range while the enemy is chasing a ballista,
-- the enemy immediately switches to the player (player always wins up close).
local PLAYER_PRIORITY_RANGE  = 18

local enemyLastAttack: { [Model]: number }      = {}
local aggroTarget: { [Model]: Player }          = {}  -- which player each enemy is chasing
local spawnPos: { [Model]: Vector3 }            = {}  -- original spawn position per enemy
local attackTrack: { [Model]: AnimationTrack }  = {}  -- cached attack animation per enemy

-- Animation asset ID played when a skeleton swings at the player.
-- This runs server-side so all clients see the animation replicated automatically.
local SKELETON_ATTACK_ANIM_ID = "rbxassetid://116235674827914"

-- ── helpers ──────────────────────────────────────────────────────────────────

local function getHumanoid(model: Model): Humanoid?
	return model:FindFirstChildOfClass("Humanoid")
end

local function getRoot(model: Model): BasePart?
	local hrp = model:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:IsA("BasePart") then
		return hrp :: BasePart
	end
	return nil
end

local function getEnemiesFolder(): Folder?
	if typeof(WorldService.GetCurrentWorld) ~= "function" then
		return nil
	end
	local world = WorldService.GetCurrentWorld()
	if not world then
		return nil
	end
	local enemies = world.generated:FindFirstChild("Enemies")
	if enemies and enemies:IsA("Folder") then
		return enemies :: Folder
	end
	return nil
end

local function getBaseTargetPosition(): Vector3?
	if typeof(WorldService.GetCurrentWorld) ~= "function" then
		return nil
	end
	local world = WorldService.GetCurrentWorld()
	if not world then
		return nil
	end
	local cf = world.spawnCFrame
	if cf then
		return cf.Position
	end
	return nil
end

local function isPlayerAlive(player: Player): boolean
	local char = player.Character
	if not char then return false end
	local hum = getHumanoid(char)
	local root = getRoot(char)
	return hum ~= nil and hum.Health > 0 and root ~= nil
end

local function findNearestPlayer(position: Vector3, maxRange: number): Player?
	local best: Player? = nil
	local bestDist = maxRange
	for _, player in ipairs(Players:GetPlayers()) do
		local char = player.Character
		if not char then continue end
		local hum = getHumanoid(char)
		local root = getRoot(char)
		if hum and hum.Health > 0 and root then
			local d = (root.Position - position).Magnitude
			if d < bestDist then
				bestDist = d
				best = player
			end
		end
	end
	return best
end

-- ── animation ─────────────────────────────────────────────────────────────

-- Returns a cached AnimationTrack for the enemy, loading it on first call.
-- Server-side animation works the same as client-side: load via Animator,
-- then call :Play(). Roblox replicates NPC animations to all clients automatically.
local function getOrLoadAttackTrack(enemy: Model): AnimationTrack?
	local cached = attackTrack[enemy]
	if cached then
		return cached
	end

	local hum = getHumanoid(enemy)
	if not hum then return nil end

	-- Find or create an Animator inside the Humanoid.
	-- Animator is required by Roblox to play animations on any Humanoid rig.
	local anim = hum:FindFirstChildOfClass("Animator")
	if not anim then
		anim = Instance.new("Animator")
		anim.Parent = hum
	end

	-- Create a temporary Animation object to hold the asset ID.
	-- We only need it during LoadAnimation; the resulting track is what we keep.
	local animObj = Instance.new("Animation")
	animObj.AnimationId = SKELETON_ATTACK_ANIM_ID

	local ok, result = pcall(function()
		return anim:LoadAnimation(animObj)
	end)
	animObj:Destroy()

	if not ok then
		warn("[EnemyService] Failed to load attack animation:", result)
		return nil
	end

	local track = result :: AnimationTrack
	track.Priority = Enum.AnimationPriority.Action
	attackTrack[enemy] = track
	return track
end

-- ── per-enemy AI ──────────────────────────────────────────────────────────────

-- If the enemy has a ShooterBallistaUid attribute and that ballista is still alive,
-- move toward (or attack) it and return true. Clears the stale attribute if the
-- ballista was destroyed, and returns false so the caller can fall through to idle.
local function tryReturnToShooterBallista(enemy: Model, pos: Vector3, hum: Humanoid): boolean
	local uid = enemy:GetAttribute("ShooterBallistaUid")
	if type(uid) ~= "string" then return false end

	local bPos = BallistaService.GetPosition(uid)
	if not bPos then
		-- Ballista was destroyed — clear the stale tag
		enemy:SetAttribute("ShooterBallistaUid", nil)
		return false
	end

	if (bPos - pos).Magnitude <= ATTACK_RANGE then
		attackBallista(enemy, uid)
		hum:MoveTo(pos)
	else
		hum:MoveTo(bPos)
	end
	return true
end

-- Melee-attacks a ballista. Delegates damage to BallistaService so health
-- tracking and destruction logic stay in one place.
local function attackBallista(enemy: Model, uid: string)
	local now  = os.clock()
	local last = enemyLastAttack[enemy] or 0
	if now - last < ATTACK_COOLDOWN then return end
	enemyLastAttack[enemy] = now

	local track = getOrLoadAttackTrack(enemy)
	if track then
		if track.IsPlaying then track:Stop(0) end
		track:Play(0.05, 1, 1.0)
	end

	local dmg = enemy:GetAttribute("Damage")
	BallistaService.TakeDamage(uid, if typeof(dmg) == "number" then dmg else 8)
end

local function attackPlayer(enemy: Model, player: Player)
	local now = os.clock()
	local last = enemyLastAttack[enemy] or 0
	if now - last < ATTACK_COOLDOWN then return end
	enemyLastAttack[enemy] = now

	local char = player.Character
	if not char then return end
	local hum = getHumanoid(char)
	if not hum or hum.Health <= 0 then return end

	-- Play the attack animation on the skeleton.
	-- Because this runs on the server, Roblox automatically replicates it
	-- to all clients — every player sees the skeleton swing at the same time.
	local track = getOrLoadAttackTrack(enemy)
	if track then
		-- Stop first so the animation restarts cleanly if the skeleton attacks again
		-- before the previous swing animation has finished.
		if track.IsPlaying then
			track:Stop(0)
		end
		track:Play(0.05, 1, 1.0)
	end

	local dmg = enemy:GetAttribute("Damage")
	hum:TakeDamage(if typeof(dmg) == "number" then dmg else 8)
end

local function updateEnemy(enemy: Model)
	local hum = getHumanoid(enemy)
	local root = getRoot(enemy)
	if not hum or hum.Health <= 0 or not root then
		aggroTarget[enemy]    = nil
		enemyLastAttack[enemy] = nil
		spawnPos[enemy]       = nil
		attackTrack[enemy]    = nil
		return
	end

	local pos = root.Position

	-- Record spawn position once on first AI tick
	if not spawnPos[enemy] then
		spawnPos[enemy] = pos
	end

	-- ── 1. Continue chasing the current player aggro target ────────────────
	local target = aggroTarget[enemy]
	if target then
		if not isPlayerAlive(target) then
			aggroTarget[enemy] = nil
		else
			local pRoot = getRoot(target.Character)
			if pRoot then
				local dist = (pRoot.Position - pos).Magnitude
				if dist > DEAGGRO_RANGE then
					-- Player escaped. If we were being shot by a ballista, go back to it.
					aggroTarget[enemy] = nil
					if tryReturnToShooterBallista(enemy, pos, hum) then return end
				else
					if dist <= ATTACK_RANGE then
						attackPlayer(enemy, target)
						hum:MoveTo(pos)
					else
						hum:MoveTo(pRoot.Position)
					end
					return
				end
			end
		end
	end

	-- ── 2. No current player aggro — find best target ──────────────────────
	-- A player within PLAYER_PRIORITY_RANGE ALWAYS wins, even if a ballista
	-- is geometrically closer. Beyond that range we pick whoever is nearer.
	local nearestPlayer = findNearestPlayer(pos, AGGRO_RANGE)
	local playerDist    = math.huge
	if nearestPlayer then
		local pRoot = getRoot(nearestPlayer.Character)
		if pRoot then playerDist = (pRoot.Position - pos).Magnitude end
	end

	local nearestBallista = BallistaService.GetNearestBallista(pos, AGGRO_RANGE)
	local ballistaDist    = if nearestBallista
		then (nearestBallista.position - pos).Magnitude
		else math.huge

	-- Player gets priority when: they are closer OR they are within the
	-- "danger close" threshold (enemy turns away from ballista to fight player).
	local playerWins = nearestPlayer ~= nil
		and (playerDist <= ballistaDist or playerDist <= PLAYER_PRIORITY_RANGE)

	if playerWins and nearestPlayer then
		-- ── Chase player ───────────────────────────────────────────────────
		aggroTarget[enemy] = nearestPlayer
		local pRoot = getRoot(nearestPlayer.Character)
		if pRoot then
			if playerDist <= ATTACK_RANGE then
				attackPlayer(enemy, nearestPlayer)
				hum:MoveTo(pos)
			else
				hum:MoveTo(pRoot.Position)
			end
			return
		end

	elseif nearestBallista then
		-- ── Chase ballista ─────────────────────────────────────────────────
		if ballistaDist <= ATTACK_RANGE then
			attackBallista(enemy, nearestBallista.uid)
			hum:MoveTo(pos)
		else
			hum:MoveTo(nearestBallista.position)
		end
		return
	end

	-- ── 3. Nothing in aggro range — return to shooter ballista if tagged ───
	-- This handles the case where the ballista is shooting from beyond AGGRO_RANGE
	-- but already tagged this enemy with ShooterBallistaUid.
	if tryReturnToShooterBallista(enemy, pos, hum) then return end

	-- ── 4. Night raid: march toward the base ───────────────────────────────
	if currentPhase == "Night" and enemy:GetAttribute("LeashToBaseAtNight") == true then
		local basePos = getBaseTargetPosition()
		if basePos then hum:MoveTo(basePos) end
		return
	end

	-- ── 5. Idle: drift back to spawn ───────────────────────────────────────
	local home = spawnPos[enemy]
	if home and (home - pos).Magnitude > 4 then
		hum:MoveTo(home)
	end
end

-- ── main loop ─────────────────────────────────────────────────────────────────

local function aiLoop()
	while true do
		task.wait(MOVE_INTERVAL)
		local folder = getEnemiesFolder()
		if not folder then continue end
		for _, inst in ipairs(folder:GetChildren()) do
			if inst:IsA("Model") and inst:GetAttribute("IsEnemy") == true then
				updateEnemy(inst :: Model)
			end
		end
	end
end

-- ── public ────────────────────────────────────────────────────────────────────

function EnemyService.Start()
	if started then return end
	started = true

	Shared:WaitForChild("State")
	local phaseValue = Shared.State:WaitForChild("CurrentPhase") :: StringValue
	currentPhase = if phaseValue.Value == "Night" then "Night" else "Day"

	phaseValue.Changed:Connect(function()
		currentPhase = if phaseValue.Value == "Night" then "Night" else "Day"
		print("[EnemyService] Phase:", currentPhase)

		-- On night start, clear all aggro so skeletons begin marching to base
		if currentPhase == "Night" then
			for enemy in pairs(aggroTarget) do
				aggroTarget[enemy] = nil
			end
		end
	end)

	task.spawn(aiLoop)
	print("[EnemyService] Started.")
end

return EnemyService
