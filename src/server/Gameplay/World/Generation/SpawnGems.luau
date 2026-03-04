--!strict
-- src/server/Gameplay/World/Generation/SpawnGems.luau

local ServerStorage = game:GetService("ServerStorage")

local ConfigLocator = require(script.Parent.Parent.Config.ConfigLocator)
local WorldConfig = ConfigLocator.WorldConfig
local WorldHeight = ConfigLocator.WorldHeight

local SpawnGems = {}

local function getOrCreateFolder(parent: Instance, name: string): Folder
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("Folder") then
		return existing
	end
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

local function pivotToBottomOffsetY(model: Model): number
	local pivotY = model:GetPivot().Position.Y
	local bbCFrame, bbSize = model:GetBoundingBox()
	local bottomY = bbCFrame.Position.Y - (bbSize.Y / 2)
	return pivotY - bottomY
end

local function inSpawnHub(localX: number, localZ: number): boolean
	local SPAWN_X: number = (WorldConfig.SPAWN_CENTER_X :: number?) or 0
	local SPAWN_Z: number = (WorldConfig.SPAWN_CENTER_Z :: number?) or 0
	local SPAWN_R: number = (WorldConfig.SPAWN_CLEAR_RADIUS :: number?) or 90
	local dx = localX - SPAWN_X
	local dz = localZ - SPAWN_Z
	return (dx * dx + dz * dz) <= (SPAWN_R * SPAWN_R)
end

local function findCaveCenters(cavesFolder: Folder): {Vector3}
	local centers: {Vector3} = {}

	for _, inst in ipairs(cavesFolder:GetChildren()) do
		if inst:IsA("Model") then
			-- Prefer explicit primary part position if present, else bounding box center
			local pivot = inst:GetPivot()
			table.insert(centers, pivot.Position)
		elseif inst:IsA("BasePart") then
			table.insert(centers, inst.Position)
		end
	end

	return centers
end

function SpawnGems.Build(generated: Folder, origin: Vector3, rng: Random, save: any): number
	local templates = ServerStorage:WaitForChild("Templates")
	local gemsFolder = templates:WaitForChild("Gems")

	local gemTemplate = gemsFolder:FindFirstChild("Crystal")
	if not (gemTemplate and gemTemplate:IsA("Model")) then
		warn("[SpawnGems] Missing Crystal template (Model) at ServerStorage/Templates/Gems/Crystal")
		return 0
	end

	local cavesFolder = generated:FindFirstChild("Caves")
	if not (cavesFolder and cavesFolder:IsA("Folder")) then
		warn("[SpawnGems] No generated/Caves folder found. Gems require caves. Skipping.")
		return 0
	end

	local caveCenters = findCaveCenters(cavesFolder)
	if #caveCenters == 0 then
		print("[SpawnGems] No caves spawned -> no gems.")
		return 0
	end

	local gemsOut = getOrCreateFolder(generated, "Gems")
	local mined = (save and save.diffs and save.diffs.minedGems) or {}

	local BASE_Y: number = (WorldConfig.BASE_Y :: number?) or 0

	local perMin: number = (WorldConfig.GEMS_PER_CAVE_MIN :: number?) or 3
	local perMax: number = (WorldConfig.GEMS_PER_CAVE_MAX :: number?) or 5
	local radius: number = (WorldConfig.GEM_SPAWN_RADIUS :: number?) or 55
	local minFromCave: number = (WorldConfig.GEM_MIN_DISTANCE_FROM_CAVE :: number?) or 18

	local templateOffsetToBottom = pivotToBottomOffsetY(gemTemplate)

	local count = 0

	for ci, cavePos in ipairs(caveCenters) do
		local n = rng:NextInteger(perMin, perMax)

		for gi = 1, n do
			-- Random point in an annulus around cave
			local angle = rng:NextNumber(0, math.pi * 2)
			local r = rng:NextNumber(minFromCave, radius)

			local x = cavePos.X + math.cos(angle) * r
			local z = cavePos.Z + math.sin(angle) * r

			-- Convert to local for spawn-clear check (origin is 0,0,0 in your runtime but keep it correct)
			local localX = x - origin.X
			local localZ = z - origin.Z

			if inSpawnHub(localX, localZ) then
				continue
			end

			local id = ("gem_c%d_%d_%d"):format(ci, math.floor(localX), math.floor(localZ))
			if mined[id] then
				continue
			end

			local height = WorldHeight.heightAt(x, z)
			local yGround = BASE_Y + height
			local yPivot = yGround + templateOffsetToBottom

			local rot = rng:NextNumber(0, math.pi * 2)

			local gem = gemTemplate:Clone()
			gem.Parent = gemsOut
			gem:SetAttribute("WorldObjectId", id)
			gem:SetAttribute("WorldObjectType", "Gem")
			gem:PivotTo(CFrame.new(x, yPivot, z) * CFrame.Angles(0, rot, 0))

			count += 1
		end
	end

	print(("[SpawnGems] Spawned crystals near caves: %d (caves=%d, %d-%d each)"):format(count, #caveCenters, perMin, perMax))
	return count
end

return SpawnGems