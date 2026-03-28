--!strict
-- src/server/Gameplay/World/Generation/SpawnCaveSkeletons.luau

local ServerStorage = game:GetService("ServerStorage")

local ConfigLocator = require(script.Parent.Parent.Config:WaitForChild("ConfigLocator"))
local WorldConfig = ConfigLocator.WorldConfig
local WorldHeight = ConfigLocator.WorldHeight

local SpawnCaveSkeletons = {}

local function mustFolder(parent: Instance, name: string): Folder
	local inst = parent:WaitForChild(name)
	if not inst:IsA("Folder") then
		error(("Expected %s under %s to be Folder, got %s"):format(name, parent:GetFullName(), inst.ClassName))
	end
	return inst
end

local function mustModel(parent: Instance, name: string): Model
	local inst = parent:WaitForChild(name)
	if not inst:IsA("Model") then
		error(("Expected %s under %s to be Model, got %s"):format(name, parent:GetFullName(), inst.ClassName))
	end
	return inst
end

local templatesFolder = mustFolder(ServerStorage, "Templates")
local charactersFolder = mustFolder(templatesFolder, "Characters")
local skeletonTemplate: Model = mustModel(charactersFolder, "Skeleton")

local function getOrCreateFolder(parent: Instance, name: string): Folder
	local f = parent:FindFirstChild(name)
	if f and f:IsA("Folder") then
		return f
	end

	local nf = Instance.new("Folder")
	nf.Name = name
	nf.Parent = parent
	return nf
end

local function setAnchored(model: Model, anchored: boolean)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = anchored
		end
	end
end

-- Spawn settings
local SKELETONS_PER_CAVE = 3
local SPAWN_RADIUS_MIN = 18
local SPAWN_RADIUS_MAX = 35
local MAX_TRIES_PER_SKELETON = 12
local MAX_HEALTH = 60

local function spawnSkeletonAt(worldX: number, worldZ: number, enemiesFolder: Folder, rng: Random): Model
	local h = WorldHeight.heightAt(worldX, worldZ)
	local baseY: number = (WorldConfig.BASE_Y :: number?) or 0
	local groundY = baseY + h

	local skel = skeletonTemplate:Clone()
	skel.Name = "Skeleton"
	skel.Parent = enemiesFolder

	skel:SetAttribute("EnemyType", "Skeleton")
	skel:SetAttribute("IsEnemy", true)
	skel:SetAttribute("MaxHealth", MAX_HEALTH)
	skel:SetAttribute("Damage", 4)
	skel:SetAttribute("AttackRange", 4)
	skel:SetAttribute("AggroRange", 80)
	skel:SetAttribute("MoveSpeed", 10)
	skel:SetAttribute("LeashToBaseAtNight", true)

	local hum = skel:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.MaxHealth = MAX_HEALTH
		hum.Health = hum.MaxHealth
		hum.WalkSpeed = 10

		hum.Died:Connect(function()
			task.delay(2, function()
				if skel.Parent then
					skel:Destroy()
				end
			end)
		end)
	end

	local _, size = skel:GetBoundingBox()
	local rot = CFrame.Angles(0, math.rad(rng:NextInteger(0, 359)), 0)
	skel:PivotTo(CFrame.new(worldX, groundY + size.Y / 2 + 1, worldZ) * rot)

	-- must be unanchored for humanoid movement
	setAnchored(skel, false)

	return skel
end

function SpawnCaveSkeletons.Build(root: Folder, origin: Vector3, rng: Random, _save: any): number
	local cavesFolderInst = root:FindFirstChild("Caves")
	if not (cavesFolderInst and cavesFolderInst:IsA("Folder")) then
		warn("[SpawnCaveSkeletons] No Caves folder under world root. Did SpawnCaves run first?")
		return 0
	end
	local cavesFolder: Folder = cavesFolderInst

	local caves = cavesFolder:GetChildren()
	if #caves == 0 then
		warn("[SpawnCaveSkeletons] No caves found. Did SpawnCaves spawn any caves?")
		return 0
	end

	local enemiesFolder = getOrCreateFolder(root, "Enemies")

	local totalSpawned = 0
	local half = (((WorldConfig.AREA_SIZE :: number?) or 800) / 2)

	for _, cave in ipairs(caves) do
		if not cave:IsA("Model") then
			continue
		end

		local cavePos = cave:GetPivot().Position

		for _ = 1, SKELETONS_PER_CAVE do
			local spawned = false

			for _ = 1, MAX_TRIES_PER_SKELETON do
				local angle = rng:NextNumber() * math.pi * 2
				local radius = rng:NextInteger(SPAWN_RADIUS_MIN, SPAWN_RADIUS_MAX)

				local worldX = cavePos.X + math.cos(angle) * radius
				local worldZ = cavePos.Z + math.sin(angle) * radius

				local localX = worldX - origin.X
				local localZ = worldZ - origin.Z
				if localX < -half or localX > half or localZ < -half or localZ > half then
					continue
				end

				spawnSkeletonAt(worldX, worldZ, enemiesFolder, rng)
				totalSpawned += 1
				spawned = true
				break
			end

			if not spawned then
				warn("[SpawnCaveSkeletons] Could not find a spawn point near cave:", cave.Name)
			end
		end
	end

	print(("[SpawnCaveSkeletons] Spawned %d skeletons near %d caves."):format(totalSpawned, #caves))
	return totalSpawned
end

return SpawnCaveSkeletons