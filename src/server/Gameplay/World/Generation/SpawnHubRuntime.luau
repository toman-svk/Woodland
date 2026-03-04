--!strict
-- src/server/Gameplay/World/Generation/SpawnHubRuntime.luau

local ServerStorage = game:GetService("ServerStorage")

local ConfigLocator = require(script.Parent.Parent.Config:WaitForChild("ConfigLocator"))
local WorldConfig = ConfigLocator.WorldConfig
local WorldHeight = ConfigLocator.WorldHeight

local SpawnHubRuntime = {}

local function setAnchoredRecursive(inst: Instance, anchored: boolean)
	-- IMPORTANT: include the instance itself if it's a BasePart (top-level SpawnLocation!)
	if inst:IsA("BasePart") then
		inst.Anchored = anchored
	end
	for _, d in ipairs(inst:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = anchored
		end
	end
end

local function offsetInstance(inst: Instance, delta: Vector3)
	if inst:IsA("Model") then
		inst:PivotTo(inst:GetPivot() + delta)
	elseif inst:IsA("BasePart") then
		inst.CFrame = inst.CFrame + delta
	end
end

local function findSpawnLocationInFolder(folder: Instance): SpawnLocation?
	return folder:FindFirstChildWhichIsA("SpawnLocation", true)
end

local function findSpawnMarker(folder: Instance): BasePart?
	local sl = folder:FindFirstChildWhichIsA("SpawnLocation", true)
	if sl then return sl end

	local p = folder:FindFirstChild("SpawnLocation", true)
	if p and p:IsA("BasePart") then
		return p
	end

	return nil
end

export type BuildResult = {
	count: number,
	spawnCFrame: CFrame?,
}

function SpawnHubRuntime.Build(root: Folder, origin: Vector3, _rng: Random, _save: any): BuildResult
	local templates = ServerStorage:WaitForChild("Templates")
	local templateFolder = templates:WaitForChild("SpawnHubTemplate")

	local clones: {Instance} = {}
	local spawnLoc: BasePart? = nil
	local count = 0

	-- 1) Clone and offset into world
	for _, child in ipairs(templateFolder:GetChildren()) do
		local clone = child:Clone()
		clone.Parent = root
		offsetInstance(clone, origin)

		table.insert(clones, clone)

		if spawnLoc == nil then
			local sl = findSpawnLocationInFolder(clone)
			if sl then
				spawnLoc = sl
			else
				local fallback = findSpawnMarker(root)
				if fallback then
					warn("[SpawnHubRuntime] No SpawnLocation found in SpawnHubTemplate clones. Looking for BasePart named 'SpawnLocation' as fallback, found:", fallback:GetFullName())
					spawnLoc = fallback :: BasePart?
				end
			end
		end

		count += 1
	end

	-- 2) Snap vertically using the SAME height math as terrain
	-- 2) Snap vertically to the SAME hub ground height as TerrainGenerator
	if spawnLoc then
		local baseY: number = (WorldConfig.BASE_Y :: number?) or 0
		local spawnX: number = (WorldConfig.SPAWN_CENTER_X :: number?) or 0
		local spawnZ: number = (WorldConfig.SPAWN_CENTER_Z :: number?) or 0

		local hubGroundY: number
		do
			local fixed = WorldConfig.SPAWN_HUB_FIXED_GROUND_Y
			if typeof(fixed) == "number" then
				hubGroundY = (fixed :: number)
			else
				local plateauH = WorldHeight.heightAt(origin.X + spawnX, origin.Z + spawnZ)
				hubGroundY = baseY + plateauH
			end
		end

		local LIFT = 0.05
		local EXTRA_RAISE = 1.0 -- studs (raise hub a bit above grass)
		local targetY = hubGroundY + (spawnLoc.Size.Y * 0.5) + LIFT + EXTRA_RAISE
		local dy = targetY - spawnLoc.Position.Y

		if math.abs(dy) > 1e-3 then
			local delta = Vector3.new(0, dy, 0)
			for _, inst in ipairs(clones) do
				offsetInstance(inst, delta)
			end
		end
	else
		warn("[SpawnHubRuntime] No SpawnLocation found in SpawnHubTemplate clones.")
	end

	-- 3) Anchor after final placement (and anchor top-level parts too)
	for _, inst in ipairs(clones) do
		setAnchoredRecursive(inst, true)
	end

	local spawnCFrame: CFrame? = if spawnLoc then spawnLoc.CFrame else nil

	return {
		count = count,
		spawnCFrame = spawnCFrame,
	}
end

return SpawnHubRuntime