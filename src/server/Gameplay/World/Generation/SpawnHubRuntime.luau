--!strict
-- src/server/Gameplay/World/Generation/SpawnHubRuntime.luau

local ServerStorage = game:GetService("ServerStorage")

local ConfigLocator = require(script.Parent.Parent.Config:WaitForChild("ConfigLocator"))
local WorldConfig = ConfigLocator.WorldConfig
local WorldHeight = ConfigLocator.WorldHeight

local SpawnHubRuntime = {}

local CONTACT_EPSILON = 0.0

local function setAnchoredRecursive(inst: Instance, anchored: boolean)
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

local function findSpawnLocationInInstance(inst: Instance): SpawnLocation?
	local sl = inst:FindFirstChildWhichIsA("SpawnLocation", true)
	if sl then
		return sl
	end
	return nil
end

local function findSpawnMarkerInInstance(inst: Instance): BasePart?
	local sl = inst:FindFirstChildWhichIsA("SpawnLocation", true)
	if sl then
		return sl
	end

	local named = inst:FindFirstChild("SpawnLocation", true)
	if named and named:IsA("BasePart") then
		return named
	end

	return nil
end


-- Returns the lowest bottom-Y across every BasePart in the hub clones.
-- Using this instead of the SpawnLocation's Y means the hub base (not the
-- spawn marker, which may be elevated) is what sits on the terrain surface.
local function getHubBottomY(clonesList: {Instance}): number
	local minY = math.huge
	local lowestPart: BasePart? = nil
	local lowestParent: Instance? = nil
	local function checkPart(p: BasePart)
		-- Skip DropZone as it's intentionally deep and shouldn't affect ground positioning
		if p.Name == "DropZone" then
			return
		end
		local bottom = p.Position.Y - p.Size.Y / 2
		if bottom < minY then
			minY = bottom
			lowestPart = p
			lowestParent = p.Parent
		end
	end
	for _, inst in ipairs(clonesList) do
		if inst:IsA("BasePart") and inst.Name ~= "DropZone" then
			checkPart(inst :: BasePart)
		end
		for _, d in ipairs(inst:GetDescendants()) do
			if d:IsA("BasePart") and d.Name ~= "DropZone" then
				checkPart(d :: BasePart)
			end
		end
	end
	if lowestPart then
		print(("[SpawnHubRuntime] Lowest part: %s (parent: %s) at Y=%.1f, size=%.1f, bottom=%.1f"):format(
			lowestPart.Name, lowestParent and lowestParent.Name or "?", lowestPart.Position.Y, lowestPart.Size.Y, minY
		))
	end
	return if minY == math.huge then 0 else minY
end

export type BuildResult = {
	count: number,
	spawnCFrame: CFrame?,
}

function SpawnHubRuntime.Build(root: Folder, origin: Vector3, _rng: Random, _save: any): BuildResult
	local templates = ServerStorage:WaitForChild("Templates")
	local templateFolder = templates:WaitForChild("SpawnHubTemplate")

	local clones: {Instance} = {}
	local spawnMarker: BasePart? = nil
	local count = 0

	for _, child in ipairs(templateFolder:GetChildren()) do
		local clone = child:Clone()
		clone.Parent = root

		offsetInstance(clone, origin)
		table.insert(clones, clone)

		print(("[SpawnHubRuntime] Cloned %s (class: %s)"):format(clone.Name, clone.ClassName))

		if spawnMarker == nil then
			local exactSpawn = findSpawnLocationInInstance(clone)
			if exactSpawn then
				spawnMarker = exactSpawn
			else
				local fallback = findSpawnMarkerInInstance(clone)
				if fallback then
					spawnMarker = fallback
				end
			end
		end

		count += 1
	end

	if #clones == 0 then
		warn("[SpawnHubRuntime] SpawnHubTemplate is empty.")
		return {
			count = 0,
			spawnCFrame = nil,
		}
	end

	-- Anchor all parts BEFORE PivotTo so Motor6D joints don't interfere.
	-- When anchored, PivotTo sets positions directly without physics.
	for _, inst in ipairs(clones) do
		setAnchoredRecursive(inst, true)
	end

	local baseY: number = (WorldConfig.BASE_Y :: number?) or 0

	-- Use the same fixed ground height that terrain generation uses for the flat area
	local hubGroundY: number = (WorldConfig.SPAWN_HUB_FIXED_GROUND_Y :: number?) or 50
	local yOffset: number = (WorldConfig.SPAWN_HUB_Y_OFFSET :: number?) or 0
	hubGroundY = hubGroundY + yOffset

	local currentBottomY = getHubBottomY(clones)
	local targetBottomY = hubGroundY + CONTACT_EPSILON
	local dy = targetBottomY - currentBottomY

	print(("[SpawnHubRuntime] Positioning hub: currentBottomY=%.1f, targetBottomY=%.1f, offset=%.1f"):format(
		currentBottomY, targetBottomY, dy
	))

	if math.abs(dy) > 1e-4 then
		local delta = Vector3.new(0, dy, 0)
		for _, inst in ipairs(clones) do
			local posBefore = if inst:IsA("Model") then inst:GetPivot().Position else inst.Position
			offsetInstance(inst, delta)
			local posAfter = if inst:IsA("Model") then inst:GetPivot().Position else inst.Position
			print(("[SpawnHubRuntime] Offset %s: Y %.1f → Y %.1f"):format(inst.Name, posBefore.Y, posAfter.Y))

			-- Debug output for Blacksmith
			if inst.Name == "Blacksmith" then
				local partCount = 0
				for _, part in ipairs(inst:GetDescendants()) do
					if part:IsA("BasePart") then
						partCount += 1
						if partCount <= 5 then
							print(("[SpawnHubRuntime] Blacksmith part: %s, Transparency=%.1f, CanCollide=%s, Pos=%.1f"):format(
								part.Name, part.Transparency, tostring(part.CanCollide), part.Position.Y
							))
						end
					end
				end
				print(("[SpawnHubRuntime] Blacksmith total parts: %d"):format(partCount))
			end
		end
	end

	if spawnMarker == nil then
		warn("[SpawnHubRuntime] No SpawnLocation found inside SpawnHubTemplate.")
	end

	local spawnCFrame: CFrame? = nil
	if spawnMarker then
		spawnCFrame = spawnMarker.CFrame
	end

	return {
		count = count,
		spawnCFrame = spawnCFrame,
	}
end

return SpawnHubRuntime