--!strict
-- src/server/Gameplay/World/Generation/SpawnHubRuntime.luau

local ServerStorage = game:GetService("ServerStorage")

local SpawnHubRuntime = {}

local function mustChild(parent: Instance, name: string): Instance
	local inst = parent:FindFirstChild(name)
	if not inst then
		error(("Missing %s under %s"):format(name, parent:GetFullName()))
	end
	return inst
end

local function setAnchoredRecursive(inst: Instance, anchored: boolean)
	-- include self
	if inst:IsA("BasePart") then
		inst.Anchored = anchored
	end

	for _, d in ipairs(inst:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = anchored
		end
	end
end

function SpawnHubRuntime.Build(root: Folder, origin: Vector3, _rng: Random, _save: unknown): number
	local templates = ServerStorage:WaitForChild("Templates")
	local templateFolderInst = mustChild(templates, "SpawnHubTemplate")

	if not templateFolderInst:IsA("Folder") then
		error(("Templates/SpawnHubTemplate must be a Folder, got %s"):format(templateFolderInst.ClassName))
	end
	local templateFolder: Folder = templateFolderInst

	local count = 0

	for _, child in ipairs(templateFolder:GetChildren()) do
		local clone = child:Clone()
		clone.Parent = root

		-- offset placement to this world's origin
		if clone:IsA("Model") then
			clone:PivotTo(clone:GetPivot() + origin)
		elseif clone:IsA("BasePart") then
			clone.CFrame = clone.CFrame + origin
		end

		-- hub is static for now
		setAnchoredRecursive(clone, true)

		count += 1
	end

	return count
end

return SpawnHubRuntime