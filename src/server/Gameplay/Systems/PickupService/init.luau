--!strict
-- src/server/Gameplay/Systems/PickupService/init.luau
--
-- Spawns physical resource pickups in the world and handles collection:
-- when a player walks close enough, the pickup flies toward them and
-- adds the item to their inventory.
--
-- Currently supports:
--   • Wood logs  (spawned by ResourceService when a tree is chopped)
--   • Gems       (spawned by ResourceService when a crystal is mined)
--
-- Adding a new pickup type in the future:
--   1. Create a makeXxx(pos) helper that builds the Part with the right look.
--   2. Add a SpawnXxx(pos, count) public function that calls it.
--   3. The scanner loop below already works for ANY item — no changes needed there.

local Players     = game:GetService("Players")
local Debris      = game:GetService("Debris")
local HttpService = game:GetService("HttpService")

local InventoryService = require(script.Parent:WaitForChild("InventoryService"))

local PickupService = {}

local DEBUG = true
local function log(...)
	if DEBUG then
		print("[PickupService]", ...)
	end
end

-- ── Config ────────────────────────────────────────────────────────────────────

local PICKUP_FOLDER_NAME = "Pickups"

-- How close a player must be (in studs) to trigger the fly-to-player animation.
local PICKUP_RADIUS   = 6

-- After this many seconds the pickup disappears even if uncollected.
-- Prevents the world filling up with forgotten items.
local PICKUP_LIFETIME = 60

-- How long (seconds) the fly animation takes.
local PICKUP_FLY_TIME = 0.40

-- How often (seconds) we scan for nearby players.
-- Lower = more responsive but more CPU. 0.15 is a good balance.
local PICKUP_SCAN_TICK = 0.15

-- ── Wood log visuals & physics ─────────────────────────────────────────────

-- Cylinder axis in Roblox is X, so X = length of the log.
PickupService.LOG_SIZE     = Vector3.new(7.2, 1.2, 1.2)
PickupService.LOG_MATERIAL = Enum.Material.Wood
PickupService.LOG_COLOR    = Color3.fromRGB(138, 102, 66)

-- PhysicalProperties.new(density, friction, elasticity, frictionWeight, elasticityWeight)
-- High friction stops logs from sliding all over uneven terrain.
PickupService.LOG_PHYSICS = PhysicalProperties.new(
	0.9,  -- Density
	2.0,  -- Friction     (high = doesn't slide)
	0.0,  -- Elasticity   (zero = not bouncy)
	1.0,  -- FrictionWeight
	1.0   -- ElasticityWeight
)

-- Briefly damp velocity after spawning to reduce the initial chaos of the log
-- flying out of the tree at high speed.
local APPLY_DAMPING_ON_SPAWN = true
local DAMPING_TIME           = 0.35

-- ── Gem visuals & physics ──────────────────────────────────────────────────

-- Gems are small glowing spheres. The Neon material makes them self-illuminate,
-- which looks great in caves.
PickupService.GEM_SIZE     = Vector3.new(0.8, 0.8, 0.8)
PickupService.GEM_MATERIAL = Enum.Material.Neon
PickupService.GEM_COLOR    = Color3.fromRGB(120, 80, 220)  -- purple-ish crystal

-- Gems are light — low density, they'll bounce a little on the ground.
PickupService.GEM_PHYSICS = PhysicalProperties.new(
	0.3,  -- Density    (light)
	0.6,  -- Friction
	0.4,  -- Elasticity (slight bounce)
	1.0,
	1.0
)

-- ── Internal helpers ──────────────────────────────────────────────────────────

local function getPickupFolder(): Folder
	-- Lazily create a "Pickups" folder in Workspace to keep things tidy.
	local existing = workspace:FindFirstChild(PICKUP_FOLDER_NAME)
	if existing and existing:IsA("Folder") then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name   = PICKUP_FOLDER_NAME
	folder.Parent = workspace
	return folder
end

local function findClosestPlayerWithin(pos: Vector3, radius: number): Player?
	-- Linear scan of all players. Fine for small player counts (≤ 20).
	local bestPlayer: Player? = nil
	local bestDist = radius

	for _, plr in ipairs(Players:GetPlayers()) do
		local char = plr.Character
		local hrp  = char and char:FindFirstChild("HumanoidRootPart")
		if hrp and hrp:IsA("BasePart") then
			local dist = (hrp.Position - pos).Magnitude
			if dist <= bestDist then
				bestDist   = dist
				bestPlayer = plr
			end
		end
	end

	return bestPlayer
end

-- Animates a pickup flying toward the player, then awards the item and
-- destroys the part. Runs inside task.spawn so it never blocks the scanner.
local function flyPickupToPlayerAndAward(pickup: BasePart, player: Player)
	local char = player.Character
	local hrp  = char and char:FindFirstChild("HumanoidRootPart")
	if not (hrp and hrp:IsA("BasePart")) then
		-- Player teleported away; release the lock so someone else can collect it.
		pickup:SetAttribute("Collecting", false)
		return
	end

	-- Read what this pickup is worth BEFORE we start moving it.
	-- Attributes are set when the part is created (see makeWoodLog / makeGem).
	local itemAttr   = pickup:GetAttribute("Item")
	local amountAttr = pickup:GetAttribute("Amount")
	if typeof(itemAttr) ~= "string" or typeof(amountAttr) ~= "number" then
		pickup:Destroy()
		return
	end

	-- Freeze the pickup while it's flying so physics doesn't fight the animation.
	pickup.CanCollide = false
	pickup.Anchored   = true

	local startPos = pickup.Position
	local endPos   = hrp.Position + Vector3.new(0, 2, 0)  -- aim at chest height
	local t0       = os.clock()

	-- Lerp the position each frame (task.wait() yields for one Heartbeat step).
	while true do
		local alpha = (os.clock() - t0) / PICKUP_FLY_TIME
		if alpha >= 1 then break end
		pickup.Position = startPos:Lerp(endPos, alpha)
		task.wait()
	end

	-- Award after arrival so the item doesn't appear in the inventory
	-- before the visual reaches the player.
	InventoryService.Add(player, itemAttr, amountAttr)
	pickup:Destroy()
end

-- ── Part constructors ─────────────────────────────────────────────────────────

local function makeWoodLog(pos: Vector3): Part
	local p = Instance.new("Part")
	p.Name     = "WoodLog"
	p.Shape    = Enum.PartType.Cylinder
	p.Size     = PickupService.LOG_SIZE
	p.Material = PickupService.LOG_MATERIAL
	p.Color    = PickupService.LOG_COLOR
	p.CustomPhysicalProperties = PickupService.LOG_PHYSICS

	p.CanCollide  = true
	p.Anchored    = false
	p.TopSurface    = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth

	-- Rotate randomly so logs don't all look identical.
	-- Cylinder axis is X, so we rotate 90° on Z to lay it flat, then
	-- spin randomly on Y for variety.
	p.CFrame = CFrame.new(pos)
		* CFrame.Angles(0, math.rad(math.random(0, 360)), math.rad(90))

	p:SetAttribute("Item",      "Wood")
	p:SetAttribute("Amount",    1)
	p:SetAttribute("PickupId",  HttpService:GenerateGUID(false))
	p:SetAttribute("Collecting", false)

	-- Damp velocity right after spawn to prevent logs from sliding off ledges.
	if APPLY_DAMPING_ON_SPAWN then
		task.spawn(function()
			local t0 = os.clock()
			while os.clock() - t0 < DAMPING_TIME do
				if not p.Parent then return end
				p.AssemblyLinearVelocity  *= 0.85
				p.AssemblyAngularVelocity *= 0.85
				task.wait(0.05)
			end
		end)
	end

	return p
end

local function makeGem(pos: Vector3): Part
	local p = Instance.new("Part")
	p.Name     = "Gem"
	p.Shape    = Enum.PartType.Ball  -- sphere looks gem-like and rolls nicely
	p.Size     = PickupService.GEM_SIZE
	p.Material = PickupService.GEM_MATERIAL  -- Neon = glows in the dark, great for caves
	p.Color    = PickupService.GEM_COLOR
	p.CustomPhysicalProperties = PickupService.GEM_PHYSICS

	p.CanCollide  = true
	p.Anchored    = false
	p.CastShadow  = false  -- tiny neon sphere shadow looks odd; skip it

	-- Gems don't need special rotation since they're spheres.
	p.CFrame = CFrame.new(pos)

	p:SetAttribute("Item",      "Gem")
	p:SetAttribute("Amount",    1)
	p:SetAttribute("PickupId",  HttpService:GenerateGUID(false))
	p:SetAttribute("Collecting", false)

	return p
end

-- ── Public API ────────────────────────────────────────────────────────────────

function PickupService.SpawnWoodLogs(spawnPos: Vector3, count: number)
	local pickupFolder = getPickupFolder()

	for _ = 1, count do
		-- Scatter the logs a bit so they don't all land on the same spot.
		local offset = Vector3.new(
			math.random(-3, 3),
			math.random(2, 4),
			math.random(-3, 3)
		)
		local logPart = makeWoodLog(spawnPos + offset)
		logPart.Parent = pickupFolder
		Debris:AddItem(logPart, PICKUP_LIFETIME)
	end

	log("SpawnWoodLogs", count, "at", spawnPos)
end

function PickupService.SpawnGems(spawnPos: Vector3, count: number)
	local pickupFolder = getPickupFolder()

	for _ = 1, count do
		-- Smaller scatter radius than logs — gems are compact.
		local offset = Vector3.new(
			math.random(-2, 2),
			math.random(1, 3),
			math.random(-2, 2)
		)
		local gemPart = makeGem(spawnPos + offset)
		gemPart.Parent = pickupFolder
		Debris:AddItem(gemPart, PICKUP_LIFETIME)
	end

	log("SpawnGems", count, "at", spawnPos)
end

-- ── Auto-start pickup scan loop ───────────────────────────────────────────────
-- Runs forever in the background. Every PICKUP_SCAN_TICK seconds it checks
-- every pickup in the folder and, if a player is close enough, starts the
-- fly-to-player animation for that pickup.
--
-- We use an attribute "Collecting" as a lock to prevent two scan ticks both
-- trying to award the same pickup simultaneously.
task.spawn(function()
	local pickupFolder = getPickupFolder()

	while true do
		task.wait(PICKUP_SCAN_TICK)

		-- Re-acquire the folder if somehow it got reparented.
		if not pickupFolder.Parent then
			pickupFolder = getPickupFolder()
		end

		for _, inst in ipairs(pickupFolder:GetChildren()) do
			if not inst:IsA("BasePart") then continue end

			-- Skip anything already being collected.
			if inst:GetAttribute("Collecting") == true then continue end

			-- Skip parts that have no Item attribute (shouldn't happen, but be safe).
			-- NOTE: We no longer filter by item type here — this scanner works for
			-- Wood, Gem, or any future item automatically. The item type is only
			-- used when awarding inventory inside flyPickupToPlayerAndAward.
			if typeof(inst:GetAttribute("Item")) ~= "string" then continue end

			local plr = findClosestPlayerWithin(inst.Position, PICKUP_RADIUS)
			if plr then
				inst:SetAttribute("Collecting", true)
				task.spawn(function()
					flyPickupToPlayerAndAward(inst, plr)
				end)
			end
		end
	end
end)

return PickupService
