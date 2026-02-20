local CollectionService = game:GetService("CollectionService")

local DEFAULT_HP = 5

local function setupTree(treeModel: Model)
	if not treeModel:GetAttribute("MaxHP") then
		treeModel:SetAttribute("MaxHP", DEFAULT_HP)
	end
	if treeModel:GetAttribute("HP") == nil then
		treeModel:SetAttribute("HP", treeModel:GetAttribute("MaxHP"))
	end

	-- ensure tagged
	if not CollectionService:HasTag(treeModel, "Tree") then
		CollectionService:AddTag(treeModel, "Tree")
	end
end

-- Setup existing trees (tag them "Tree" OR put them under workspace.Trees)
for _, inst in ipairs(workspace:GetDescendants()) do
	if inst:IsA("Model") and inst.Name == "Tree" then
		setupTree(inst)
	end
end

-- If you spawn trees later, call setupTree(newTreeModel) after cloning/spawning.