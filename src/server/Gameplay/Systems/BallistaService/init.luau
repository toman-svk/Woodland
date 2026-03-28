--!strict
-- src/server/Gameplay/Systems/BallistaService/init.luau
--
-- Manages all placed ballistae (Trebuchet building type):
--   • Rotates the "Upper" sub-model each tick so WedgeArrow faces the nearest enemy
--   • Fires arrow projectiles toward enemies at a configurable fire rate
--   • Tracks health; destroys + removes from save when health hits 0
--   • Syncs level to the world's base level so all ballistae upgrade together
--
-- ── HOW ROTATION WORKS ────────────────────────────────────────────────────────
-- Each ballista has a child Model called "Upper". We call upper:PivotTo() each
-- tick to yaw (rotate around WORLD Y) toward the nearest enemy.
--
-- We do NOT use CFrame.lookAt because it sets an absolute world-space orientation
-- which tilts the model if the Upper pivot in Studio isn't world-aligned.
-- Instead we capture the model's INITIAL CFrame at registration and then rotate
-- all three of its axes around world Y by the required delta angle. This preserves
-- whatever pitch/roll the model was designed with, only changing the yaw.
--
-- ── HOW PROJECTILES WORK ─────────────────────────────────────────────────────
-- A thin wooden Part is spawned at the WedgeArrow position and given a
-- LinearVelocity constraint so it flies in a straight line without gravity drop.
-- On the first Touched event from an enemy:
--   1. humanoid:TakeDamage(config.damage)
--   2. A velocity impulse is applied to HumanoidRootPart (pushback)
--   3. The arrow Part is destroyed
-- A Debris timeout destroys the arrow after 6 s if it never hits anything.

local Debris              = game:GetService("Debris")
local Workspace           = game:GetService("Workspace")
local ServerScriptService = game:GetService("ServerScriptService")

local WorldService = require(
	ServerScriptService
		:WaitForChild("Server")
		:WaitForChild("Gameplay")
		:WaitForChild("World")
		:WaitForChild("Runtime")
		:WaitForChild("WorldService")
)

-- ── Level configuration ───────────────────────────────────────────────────────
-- All values scale with the world's base level.
-- Add more entries for future levels.

type LevelConfig = {
	damage:         number,  -- HP removed per arrow hit
	fireRate:       number,  -- seconds between shots
	range:          number,  -- stud radius the ballista can see enemies
	projectileSpeed: number, -- studs/second arrow travels
}

local LEVEL_CONFIG: { [number]: LevelConfig } = {
	[1] = { damage = 20, fireRate = 4.0, range = 70, projectileSpeed = 70 },
	[2] = { damage = 40, fireRate = 2.5, range = 90, projectileSpeed = 90 },
}

-- Pushback applied to the enemy HumanoidRootPart when an arrow lands.
local PUSHBACK_HORIZONTAL = 30  -- studs/sec along arrow travel direction
local PUSHBACK_VERTICAL   = 8   -- studs/sec upward

-- Sound IDs
local SHOOT_SOUND_ID = "rbxassetid://132056209123432"  -- plays on the ballista when it fires
local HIT_SOUND_ID   = "rbxassetid://123129904315504"  -- same as melee skeleton hit sound

-- Recoil: how far the barrel kicks back on fire (radians, decays over RECOIL_STEPS ticks)
local RECOIL_ANGLE = 0.10   -- ~6°, positive = barrel tilts upward (recoil kick)
local RECOIL_STEPS = 8      -- number of 0.05 s steps to decay back to rest

-- ── Types ─────────────────────────────────────────────────────────────────────

type BallistaState = {
	uid:             string,
	model:           Model,
	upper:           Model,      -- rotating sub-model (Ballista1/Upper)
	arrow:           BasePart,   -- WedgeArrow inside Upper; projectiles spawn here
	lastFireTime:    number,     -- os.clock() of last shot
	level:           number,     -- current effective level (synced from BaseLevel)
	upperInitCF:     CFrame,     -- Upper model pivot CFrame captured at registration
	upperInitFwd:    Vector3,    -- horizontal component of Upper's initial LookVector
	rotCenter:       Vector3,    -- world position of UpperBase (the fixed rotation point)
	pivotOffset:     Vector3,    -- vector from rotCenter → model pivot (constant after registration)
	shootSound:      Sound,      -- 3D sound played each time the ballista fires
	recoilCF:        CFrame,     -- temporary local-space tilt applied on fire; decays to identity
}

-- Return type used by GetNearestBallista (consumed by EnemyService).
export type NearestBallista = {
	uid:      string,
	position: Vector3,
}

-- ── Module state ──────────────────────────────────────────────────────────────

local BallistaService = {}

local registered:    { [string]: BallistaState } = {}
local currentLevel = 1

-- ── Internal helpers ──────────────────────────────────────────────────────────

local function findNearestEnemy(position: Vector3, range: number): Model?
	local world = WorldService.GetCurrentWorld()
	if not world then return nil end

	local enemiesFolder = world.generated:FindFirstChild("Enemies")
	if not (enemiesFolder and enemiesFolder:IsA("Folder")) then return nil end

	local nearest: Model? = nil
	local bestDist = range

	for _, child in ipairs(enemiesFolder:GetChildren()) do
		if not child:IsA("Model") then continue end
		local hrp = child:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not hrp then continue end
		local hum = child:FindFirstChildOfClass("Humanoid")
		if not hum or hum.Health <= 0 then continue end

		local d = (hrp.Position - position).Magnitude
		if d < bestDist then
			bestDist = d
			nearest  = child :: Model
		end
	end

	return nearest
end

-- Rotates the Upper model so WedgeArrow faces `targetPos`, pivoting around
-- UpperBase's world position (the fixed attachment point to the lower frame).
--
-- KEY FORMULA — "rotate around a point":
--   newPivotPos = rotCenter + rot * (initPivotPos - rotCenter)
--
-- This keeps UpperBase pinned in place while everything else in the Upper
-- model orbits around it, exactly like a real turret bearing.
local function aimUpper(state: BallistaState, targetPos: Vector3)
	local rotCenter = state.rotCenter  -- UpperBase world pos (never moves)

	-- Direction to enemy projected onto the horizontal plane
	local dx = targetPos.X - rotCenter.X
	local dz = targetPos.Z - rotCenter.Z
	if math.abs(dx) < 0.01 and math.abs(dz) < 0.01 then return end
	local desiredDir = Vector3.new(dx, 0, dz).Unit

	-- Signed angle: how far to rotate from the model's rest forward direction
	local dot      = math.clamp(state.upperInitFwd:Dot(desiredDir), -1, 1)
	local cross    = state.upperInitFwd:Cross(desiredDir)
	local deltaYaw = math.acos(dot) * (if cross.Y < 0 then -1 else 1)

	-- Pure world-Y rotation operator (position = 0 so it only rotates vectors)
	local rot    = CFrame.fromAxisAngle(Vector3.new(0, 1, 0), deltaYaw)
	local initCF = state.upperInitCF

	-- Rotate the model's own axes to preserve its Studio pitch/roll
	local newRight = rot * initCF.RightVector
	local newUp    = rot * initCF.UpVector
	local newBack  = -(rot * initCF.LookVector)   -- back = +Z = -LookVector

	-- Compute where the model pivot must be so that UpperBase stays at rotCenter:
	--   newPivotPos = rotCenter + rot * (initPivotPos - rotCenter)
	-- pivotOffset was pre-computed at registration as (initPivotPos - rotCenter).
	local newPivotPos = rotCenter + rot * state.pivotOffset

	-- recoilCF is a local-space tilt (identity when at rest).
	-- Multiplying AFTER the world-space CFrame applies the tilt in the Upper
	-- model's own coordinate frame, so the kick always goes "backward" regardless
	-- of which direction the ballista is currently facing.
	state.upper:PivotTo(CFrame.fromMatrix(newPivotPos, newRight, newUp, newBack) * state.recoilCF)
end

-- Animates the recoil kick: sets recoilCF to RECOIL_ANGLE then steps it back to
-- identity over RECOIL_STEPS × 0.05 s so aimUpper smoothly blends it away.
local function triggerRecoil(state: BallistaState)
	state.recoilCF = CFrame.Angles(RECOIL_ANGLE, 0, 0)
	task.spawn(function()
		for i = 1, RECOIL_STEPS do
			task.wait(0.05)
			if not state.model.Parent then break end
			local t     = i / RECOIL_STEPS
			local angle = RECOIL_ANGLE * (1 - t)
			state.recoilCF = CFrame.Angles(angle, 0, 0)
		end
		state.recoilCF = CFrame.identity
	end)
end

-- Spawns an arrow projectile from the WedgeArrow tip and flies it at the enemy.
local function fireProjectile(state: BallistaState, enemy: Model, config: LevelConfig)
	local hrp = enemy:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then return end

	local startPos  = state.arrow.Position
	local direction = (hrp.Position - startPos).Unit

	-- ── Fire sound + recoil wiggle ────────────────────────────────────────
	state.shootSound:Play()
	triggerRecoil(state)

	-- ── Arrow Part ────────────────────────────────────────────────────────
	-- Thin brown cylinder: looks like a rough wooden bolt.
	local arrow        = Instance.new("Part")
	arrow.Name         = "BallistaArrow"
	arrow.Size         = Vector3.new(0.22, 0.22, 3.0)   -- thin log shape
	arrow.Color        = Color3.fromRGB(100, 70, 35)     -- dark wood brown
	arrow.Material     = Enum.Material.Wood
	-- Orient the long Z axis toward the target
	arrow.CFrame       = CFrame.new(startPos + direction * 1.5, startPos + direction * 10)
	arrow.Anchored     = false
	arrow.CanCollide   = false   -- passes through terrain so it doesn't bounce
	arrow.CanTouch     = true    -- Touched still fires for hit detection
	arrow.CastShadow   = false
	arrow.Massless     = true
	arrow.Parent       = Workspace

	-- ── Straight-line flight via LinearVelocity ───────────────────────────
	-- LinearVelocity overrides gravity so the arrow flies flat across the map.
	local att = Instance.new("Attachment")
	att.Parent = arrow

	local lv                    = Instance.new("LinearVelocity")
	lv.Attachment0              = att
	lv.VelocityConstraintMode   = Enum.VelocityConstraintMode.Vector
	lv.VectorVelocity           = direction * config.projectileSpeed
	lv.MaxForce                 = 1e5
	lv.Parent                   = arrow

	-- ── Hit detection ─────────────────────────────────────────────────────
	local didHit  = false
	local balUid  = state.uid  -- capture uid for the closure below
	arrow.Touched:Connect(function(other: BasePart)
		if didHit then return end

		-- Walk up the instance tree to find the enemy Model
		local model = other:FindFirstAncestorOfClass("Model")
		if not model then return end
		if model:GetAttribute("IsEnemy") ~= true then return end

		didHit = true

		-- Damage
		local hum = model:FindFirstChildOfClass("Humanoid")
		if hum and hum.Health > 0 then
			hum:TakeDamage(config.damage)
		end

		-- Hit sound at the enemy's position (same sound as melee hits)
		local enemyRoot = model:FindFirstChild("HumanoidRootPart") :: BasePart?
		if enemyRoot then
			local hitSfx          = Instance.new("Sound")
			hitSfx.SoundId        = HIT_SOUND_ID
			hitSfx.Volume         = 0.9
			hitSfx.RollOffMaxDistance = 60
			hitSfx.Parent         = enemyRoot
			hitSfx:Play()
			Debris:AddItem(hitSfx, 3)

			-- Pushback: kick the enemy in the arrow's travel direction + upward
			enemyRoot.AssemblyLinearVelocity =
				direction * PUSHBACK_HORIZONTAL + Vector3.new(0, PUSHBACK_VERTICAL, 0)
		end

		-- Tag the enemy so EnemyService knows it was shot by this ballista.
		-- EnemyService uses this to re-aggro the ballista after the player de-aggros.
		model:SetAttribute("ShooterBallistaUid", balUid)

		arrow:Destroy()
	end)

	-- Safety: destroy arrow after 6 s even if it misses
	Debris:AddItem(arrow, 6)
end

-- ── Public API ────────────────────────────────────────────────────────────────

-- Called automatically when a Trebuchet model appears in the Buildings folder.
function BallistaService.Register(model: Model, uid: string)
	-- Validate the required sub-hierarchy exists
	local upper = model:FindFirstChild("Upper")
	if not (upper and upper:IsA("Model")) then
		warn(("[BallistaService] 'Upper' model not found — uid=%s"):format(uid))
		return
	end

	-- Search recursively so WedgeArrow can be nested inside Upper's children
	local arrow = upper:FindFirstChild("WedgeArrow", true)
	if not (arrow and arrow:IsA("BasePart")) then
		warn(("[BallistaService] 'WedgeArrow' not found inside Upper — uid=%s"):format(uid))
		return
	end

	-- UpperBase is the physical part around which Upper rotates.
	-- We use its world position as the fixed rotation centre.
	local upperBase = upper:FindFirstChild("UpperBase", true) :: BasePart?
	if not upperBase then
		warn(("[BallistaService] 'UpperBase' part not found inside Upper — uid=%s. "
			.. "The upper model will orbit incorrectly. Add a part named UpperBase "
			.. "at the rotation centre."):format(uid))
	end

	-- The true rotation centre: UpperBase's world-space centre position.
	-- Falls back to the model pivot if UpperBase is missing.
	local rotCenter: Vector3 = if upperBase
		then upperBase.Position
		else upper:GetPivot().Position

	-- Capture the Upper model's pivot CFrame BEFORE any runtime rotation.
	local initCF = upper:GetPivot()

	-- Pre-compute the constant offset from UpperBase → model pivot.
	-- aimUpper() uses this every tick to compute where the pivot must land
	-- so that UpperBase stays pinned at rotCenter after each rotation.
	local pivotOffset = initCF.Position - rotCenter

	-- True forward direction: from UpperBase (rotation center) → WedgeArrow tip,
	-- projected onto the horizontal plane.
	-- This is more reliable than the model's LookVector because it directly
	-- measures which way the arrow actually points in the world.
	local arrowDir = arrow.Position - rotCenter
	local lookFlat = Vector3.new(arrowDir.X, 0, arrowDir.Z)
	if lookFlat.Magnitude < 0.01 then
		-- Fallback: arrow is directly above/below UpperBase (unlikely but safe)
		local look = initCF.LookVector
		lookFlat = Vector3.new(look.X, 0, look.Z)
		if lookFlat.Magnitude < 0.01 then lookFlat = Vector3.new(0, 0, -1) end
	end
	lookFlat = lookFlat.Unit

	-- Create the shoot sound parented to WedgeArrow so it has a world position
	-- for 3D audio distance attenuation.
	local shootSound                  = Instance.new("Sound")
	shootSound.Name                   = "BallistaShoot"
	shootSound.SoundId                = SHOOT_SOUND_ID
	shootSound.Volume                 = 1.0
	shootSound.RollOffMaxDistance     = 100
	shootSound.RollOffMode            = Enum.RollOffMode.InverseTapered
	shootSound.Parent                 = arrow :: BasePart

	registered[uid] = {
		uid          = uid,
		model        = model,
		upper        = upper :: Model,
		arrow        = arrow :: BasePart,
		lastFireTime = 0,
		level        = currentLevel,
		upperInitCF  = initCF,
		upperInitFwd = lookFlat,
		rotCenter    = rotCenter,
		pivotOffset  = pivotOffset,
		shootSound   = shootSound,
		recoilCF     = CFrame.identity,  -- no kick at rest
	}
	print(("[BallistaService] Registered uid=%s level=%d"):format(uid, currentLevel))
end

-- Called by EnemyService when an enemy melee-attacks a ballista.
function BallistaService.TakeDamage(uid: string, amount: number)
	local state = registered[uid]
	if not state or not state.model.Parent then return end

	local health = state.model:GetAttribute("Health")
	if type(health) ~= "number" then return end

	local newHealth = math.max(0, health - amount)
	state.model:SetAttribute("Health", newHealth)
	print(("[BallistaService] uid=%s took %.0f dmg — health now %.0f"):format(uid, amount, newHealth))

	if newHealth <= 0 then
		-- Remove from the persistent save so it isn't restored after restart
		local world = WorldService.GetCurrentWorld()
		if world then
			for i, entry in ipairs(world.save.structures.placed) do
				if entry.uid == uid then
					table.remove(world.save.structures.placed, i)
					WorldService.MarkDirty()
					break
				end
			end
		end

		registered[uid] = nil
		state.model:Destroy()
		print(("[BallistaService] Ballista destroyed uid=%s"):format(uid))
	end
end

-- Returns the nearest active (non-under-construction) ballista within `range`
-- studs of `position`. Used by EnemyService to pick targets.
function BallistaService.GetNearestBallista(position: Vector3, range: number): NearestBallista?
	local bestDist = range
	local best:    NearestBallista? = nil

	for uid, state in pairs(registered) do
		if not state.model.Parent then continue end
		-- Don't let enemies attack a ballista that's still being built
		if state.model:GetAttribute("ConstructionActive") == true then continue end

		local bPos = state.model:GetPivot().Position
		local d    = (bPos - position).Magnitude
		if d < bestDist then
			bestDist = d
			best     = { uid = uid, position = bPos }
		end
	end

	return best
end

-- Returns the world position of a specific ballista (by uid), or nil if gone.
-- EnemyService uses this to navigate toward the ballista that shot them.
function BallistaService.GetPosition(uid: string): Vector3?
	local state = registered[uid]
	if not state or not state.model.Parent then return nil end
	return state.model:GetPivot().Position
end

-- Quick existence check used by EnemyService before committing to chase.
function BallistaService.IsAlive(uid: string): boolean
	local state = registered[uid]
	return state ~= nil and state.model.Parent ~= nil
end

-- Syncs all ballistae to a new level (called when BaseLevel attribute changes).
function BallistaService.SetLevel(level: number)
	currentLevel = math.clamp(level, 1, 2)
	for _, state in pairs(registered) do
		state.level = currentLevel
	end
	print(("[BallistaService] All ballistae → level %d"):format(currentLevel))
end

-- ── Start ─────────────────────────────────────────────────────────────────────

function BallistaService.Start()

	-- ── Watch the Buildings folder for new/restored Trebuchet models ─────────
	task.spawn(function()
		while WorldService.GetCurrentWorld() == nil do task.wait(0.5) end
		local world = WorldService.GetCurrentWorld()

		local function watchFolder(folder: Folder)
			-- Register buildings already in the folder (restored from save)
			for _, child in ipairs(folder:GetChildren()) do
				if child:IsA("Model") and child:GetAttribute("BuildingType") == "Trebuchet" then
					local uid = child:GetAttribute("BuildingUid")
					if type(uid) == "string" then
						BallistaService.Register(child :: Model, uid)
					end
				end
			end

			-- Register buildings placed while the game is running
			folder.ChildAdded:Connect(function(child)
				if child:IsA("Model") and child:GetAttribute("BuildingType") == "Trebuchet" then
					local uid = child:GetAttribute("BuildingUid")
					if type(uid) == "string" then
						BallistaService.Register(child :: Model, uid)
					end
				end
			end)
		end

		-- Buildings folder is created lazily on first placement
		local existingBuildings = world.generated:FindFirstChild("Buildings")
		if existingBuildings and existingBuildings:IsA("Folder") then
			watchFolder(existingBuildings :: Folder)
		end
		world.generated.ChildAdded:Connect(function(child)
			if child.Name == "Buildings" and child:IsA("Folder") then
				watchFolder(child :: Folder)
			end
		end)

		-- ── Sync level from world root attribute ──────────────────────────
		local initLevel = world.root:GetAttribute("BaseLevel")
		if type(initLevel) == "number" then BallistaService.SetLevel(initLevel) end

		world.root:GetAttributeChangedSignal("BaseLevel"):Connect(function()
			local lvl = world.root:GetAttribute("BaseLevel")
			if type(lvl) == "number" then BallistaService.SetLevel(lvl) end
		end)
	end)

	-- ── Ballista AI tick loop ─────────────────────────────────────────────────
	local TICK_RATE = 0.1  -- seconds between AI updates (10 fps is plenty for turrets)
	task.spawn(function()
		while true do
			task.wait(TICK_RATE)
			local now = os.clock()

			for uid, state in pairs(registered) do
				-- Clean up stale entries (model destroyed externally)
				if not state.model.Parent then
					registered[uid] = nil
					continue
				end

				-- Skip while construction timer is still running
				if state.model:GetAttribute("ConstructionActive") == true then continue end

				local config    = LEVEL_CONFIG[state.level] or LEVEL_CONFIG[1]
				local pivotPos  = state.upper:GetPivot().Position
				local enemy     = findNearestEnemy(pivotPos, config.range)
				if not enemy then continue end

				local hrp = enemy:FindFirstChild("HumanoidRootPart") :: BasePart?
				if not hrp then continue end

				-- Rotate turret to face enemy
				aimUpper(state, hrp.Position)

				-- Fire when cooldown has elapsed
				if (now - state.lastFireTime) >= config.fireRate then
					state.lastFireTime = now
					fireProjectile(state, enemy, config)
				end
			end
		end
	end)

	print("[BallistaService] Started.")
end

return BallistaService
