--!strict
-- ServerScriptService/Server/Systems/PickupService
-- Spawns resource pickups (wood logs for now) and handles collection (walk near -> fly -> award inventory)

local Players = game:GetService("Players")
local Debris = game:GetService("Debris")
local HttpService = game:GetService("HttpService")

local InventoryService = require(script.Parent:WaitForChild("InventoryService"))

local PickupService = {}

local DEBUG = true
local function log(...)
	if DEBUG then
		print("[PickupService]", ...)
	end
end

--========================
-- Config
--========================
local PICKUP_FOLDER_NAME = "Pickups"

local PICKUP_RADIUS = 6
local PICKUP_LIFETIME = 60
local PICKUP_FLY_TIME = 0.40
local PICKUP_SCAN_TICK = 0.15

--========================
-- Wood log visuals & physics
--========================
-- Size of log part (Cylinder axis is X, so X = length)
PickupService.LOG_SIZE = Vector3.new(7.2, 1.2, 1.2)

PickupService.LOG_MATERIAL = Enum.Material.Wood
PickupService.LOG_COLOR = Color3.fromRGB(138, 102, 66)

-- Friction tuning:
-- Roblox friction range is typically 0..1+ (higher = more grip).
-- Try friction = 1.0 to 2.0 for "doesn't slide much".
-- Density affects how heavy it feels; doesn't directly stop sliding, but helps stability.
PickupService.LOG_PHYSICS = PhysicalProperties.new(
	0.9,  -- Density
	2.0,  -- Friction (increase this)
	0.0,  -- Elasticity
	1.0,  -- FrictionWeight
	1.0   -- ElasticityWeight
)

-- Extra anti-slide: damp velocities right after spawn
local APPLY_DAMPING_ON_SPAWN = true
local DAMPING_TIME = 0.35

--========================
-- Internal helpers
--========================
local function getPickupFolder(): Folder
	local existing = workspace:FindFirstChild(PICKUP_FOLDER_NAME)
	if existing and existing:IsA("Folder") then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = PICKUP_FOLDER_NAME
	folder.Parent = workspace
	return folder
end

local function findClosestPlayerWithin(pos: Vector3, radius: number): Player?
	local bestPlayer: Player? = nil
	local bestDist = radius

	for _, plr in ipairs(Players:GetPlayers()) do
		local char = plr.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if hrp and hrp:IsA("BasePart") then
			local dist = (hrp.Position - pos).Magnitude
			if dist <= bestDist then
				bestDist = dist
				bestPlayer = plr
			end
		end
	end

	return bestPlayer
end

local function flyPickupToPlayerAndAward(pickup: BasePart, player: Player)
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not (hrp and hrp:IsA("BasePart")) then
		pickup:SetAttribute("Collecting", false)
		return
	end

	local itemAttr = pickup:GetAttribute("Item")
	local amountAttr = pickup:GetAttribute("Amount")
	if typeof(itemAttr) ~= "string" or typeof(amountAttr) ~= "number" then
		pickup:Destroy()
		return
	end

	-- Fly
	pickup.CanCollide = false
	pickup.Anchored = true

	local startPos = pickup.Position
	local endPos = hrp.Position + Vector3.new(0, 2, 0)
	local t0 = os.clock()

	while true do
		local a = (os.clock() - t0) / PICKUP_FLY_TIME
		if a >= 1 then break end
		pickup.Position = startPos:Lerp(endPos, a)
		task.wait()
	end

	-- Award AFTER reaching player
	InventoryService.Add(player, itemAttr, amountAttr)
	pickup:Destroy()
end

local function makeWoodLog(pos: Vector3): Part
	local p = Instance.new("Part")
	p.Name = "WoodLog"
	p.Shape = Enum.PartType.Cylinder
	p.Size = PickupService.LOG_SIZE
	p.Material = PickupService.LOG_MATERIAL
	p.Color = PickupService.LOG_COLOR
	p.CustomPhysicalProperties = PickupService.LOG_PHYSICS

	p.CanCollide = true
	p.Anchored = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth

	-- Lay it on the ground: cylinder axis is X, so rotate around Z to make it horizontal
	p.CFrame = CFrame.new(pos)
		* CFrame.Angles(0, math.rad(math.random(0, 360)), math.rad(90))

	-- Attributes define reward
	p:SetAttribute("Item", "Wood")
	p:SetAttribute("Amount", 1)
	p:SetAttribute("PickupId", HttpService:GenerateGUID(false))
	p:SetAttribute("Collecting", false)

	-- Optional: reduce initial chaos sliding
	if APPLY_DAMPING_ON_SPAWN then
		task.spawn(function()
			local t0 = os.clock()
			while os.clock() - t0 < DAMPING_TIME do
				if not p.Parent then return end
				-- Gentle damping
				p.AssemblyLinearVelocity *= 0.85
				p.AssemblyAngularVelocity *= 0.85
				task.wait(0.05)
			end
		end)
	end

	return p
end

--========================
-- Public API
--========================
function PickupService.SpawnWoodLogs(spawnPos: Vector3, count: number)
	local pickupFolder = getPickupFolder()

	for _ = 1, count do
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

--========================
-- Auto-start pickup scan loop
--========================
task.spawn(function()
	local pickupFolder = getPickupFolder()

	while true do
		task.wait(PICKUP_SCAN_TICK)

		if not pickupFolder.Parent then
			pickupFolder = getPickupFolder()
		end

		for _, inst in ipairs(pickupFolder:GetChildren()) do
			if not inst:IsA("BasePart") then
				continue
			end
			if inst:GetAttribute("Collecting") == true then
				continue
			end

			local item = inst:GetAttribute("Item")
			if item ~= "Wood" then
				continue
			end

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