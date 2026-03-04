--!strict
-- src/server/Gameplay/World/Generation/SpawnTrees.luau

local ServerStorage = game:GetService("ServerStorage")

local ConfigLocator = require(script.Parent.Parent.Config.ConfigLocator)
local WorldConfig = ConfigLocator.WorldConfig
local WorldHeight = ConfigLocator.WorldHeight

local SpawnTrees = {}

local function anchorModel(model: Model, anchored: boolean)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = anchored
		end
	end
end

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

local function getTreeTemplates(): {Model}
	local templates = ServerStorage:FindFirstChild("Templates")
	if not templates then return {} end

	local trees = templates:FindFirstChild("Trees")
	if not trees then return {} end

	local list: {Model} = {}

	for _, name in ipairs({ "Tree1", "Tree2", "Tree3", "Tree4" }) do
		local m = trees:FindFirstChild(name)
		if m and m:IsA("Model") then
			table.insert(list, m)
		end
	end

	-- fallback: any models inside Trees
	if #list == 0 then
		for _, c in ipairs(trees:GetChildren()) do
			if c:IsA("Model") then
				table.insert(list, c)
			end
		end
	end

	return list
end

local function pickTreeTemplate(rng: Random, templates: {Model}): Model?
	if #templates == 0 then return nil end

	-- Desired ratio: 40/40/10/10 for Tree1..Tree4
	-- If some are missing, fallback to uniform.
	if #templates >= 4 then
		local roll = rng:NextNumber(0, 1)
		if roll < 0.40 then return templates[1] end
		if roll < 0.80 then return templates[2] end
		if roll < 0.90 then return templates[3] end
		return templates[4]
	end

	-- fallback uniform
	return templates[rng:NextInteger(1, #templates)]
end

local function pivotToBottomOffsetY(model: Model): number
	-- Works even if pivot is not at the base.
	local pivotY = model:GetPivot().Position.Y
	local bbCFrame, bbSize = model:GetBoundingBox()
	local bbCenterY = bbCFrame.Position.Y
	local bottomY = bbCenterY - (bbSize.Y / 2)
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

local function inWorld(localX: number, localZ: number): boolean
	local WORLD_R: number = (WorldConfig.WORLD_RADIUS :: number?) or ((WorldConfig.AREA_SIZE :: number) / 2)
	local EDGE_MARGIN: number = (WorldConfig.SPAWN_EDGE_MARGIN :: number?) or 0
	local r = (WORLD_R - EDGE_MARGIN)
	return (localX * localX + localZ * localZ) <= (r * r)
end

function SpawnTrees.Build(root: Folder, origin: Vector3, rng: Random, save): number
	local treeTemplates = getTreeTemplates()
	if #treeTemplates == 0 then
		warn("[SpawnTrees] Missing tree templates under ServerStorage/Templates/Trees (Tree1..Tree4).")
		return 0
	end
	if not treeTemplates then
		warn("[SpawnTrees] Missing tree template under ServerStorage/Templates. Expected Templates/Trees/Tree (Model).")
		return 0
	end

	local treesFolder = getOrCreateFolder(root, "Trees")
	local chopped = (save and save.diffs and save.diffs.choppedTrees) or {}

	local half: number = ((WorldConfig.AREA_SIZE :: number?) or 800) / 2
	local BASE_Y: number = (WorldConfig.BASE_Y :: number?) or 0

	local spacing: number = (WorldConfig.TREE_SPACING :: number?) or 12
	local chance: number = (WorldConfig.TREE_CHANCE :: number?) or 0.35
	local maxTrees: number = (WorldConfig.MAX_TREES :: number?) or 1200
	local scaleMin: number = (WorldConfig.TREE_SCALE_MIN :: number?) or 2.0
	local scaleMax: number = (WorldConfig.TREE_SCALE_MAX :: number?) or 5.0



	-- 1) Collect candidates across the whole island (no early stop)
	type Candidate = { x: number, z: number, id: string }
	local candidates: {Candidate} = {}

	-- jitter within each spacing cell so it looks natural (still respects spacing)
	local jitter = math.max(0, math.floor(spacing * 0.35))

	for lx = -half, half, spacing do
		for lz = -half, half, spacing do
			if not inWorld(lx, lz) then
				continue
			end
			if inSpawnHub(lx, lz) then
				continue
			end
			if rng:NextNumber() > chance then
				continue
			end

			local px = lx
			local pz = lz
			if jitter > 0 then
				px = lx + rng:NextInteger(-jitter, jitter)
				pz = lz + rng:NextInteger(-jitter, jitter)
				if not inWorld(px, pz) then
					continue
				end
				if inSpawnHub(px, pz) then
					continue
				end
			end

			local id = ("tree_%d_%d"):format(math.floor(px), math.floor(pz))
			if chopped[id] then
				continue
			end

			table.insert(candidates, { x = px, z = pz, id = id })
		end
	end

	-- 2) Deterministically shuffle candidates with rng (Fisher–Yates)
	for i = #candidates, 2, -1 do
		local j = rng:NextInteger(1, i)
		candidates[i], candidates[j] = candidates[j], candidates[i]
	end

	-- 3) Place up to maxTrees spread across island
	local count = 0
	local toPlace = math.min(maxTrees, #candidates)

	for i = 1, toPlace do
		local c = candidates[i]
		local h = WorldHeight.heightAt(origin.X + c.x, origin.Z + c.z)
		local groundY = BASE_Y + h

		local template = pickTreeTemplate(rng, treeTemplates)
		if not template then
			continue
		end
		local templateOffsetToBottom = pivotToBottomOffsetY(template)
		local tree = template:Clone()
		tree.Parent = treesFolder
		tree:SetAttribute("WorldObjectId", c.id)
		tree:SetAttribute("WorldObjectType", "Tree")

		local rot = CFrame.Angles(0, math.rad(rng:NextInteger(0, 359)), 0)
		local pivotY = groundY + templateOffsetToBottom
		tree:PivotTo(CFrame.new(origin.X + c.x, pivotY, origin.Z + c.z) * rot)

		if tree.ScaleTo then
			local s = rng:NextNumber(scaleMin, scaleMax)
			tree:ScaleTo(s)
		end

		anchorModel(tree, true)
		count += 1
	end

	print(("[SpawnTrees] Candidates=%d Placed=%d spacing=%d chance=%.2f max=%d"):format(#candidates, count, spacing, chance, maxTrees))
	return count
end

return SpawnTrees