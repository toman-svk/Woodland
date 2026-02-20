-- ServerScriptService/WorldModules/SpawnHubBuilder (ModuleScript)

local SpawnHubBuilder = {}

local function anchorModel(model, anchored)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = anchored
		end
	end
end

function SpawnHubBuilder.Build()
	local ServerStorage = game:GetService("ServerStorage")
	local Terrain = workspace.Terrain

	local WorldModules = script.Parent
	local WorldConfig = require(WorldModules:WaitForChild("WorldConfig"))
	local WorldHeight = require(WorldModules:WaitForChild("WorldHeight"))

	-- If already exists, do nothing
	local generated = workspace:FindFirstChild("Generated")
	if generated and generated:FindFirstChild("SpawnHub") then
		warn("[SpawnHubBuilder] SpawnHub already exists. Delete it to rebuild.")
		return
	end

	-- Ensure Generated
	generated = generated or Instance.new("Folder")
	generated.Name = "Generated"
	generated.Parent = workspace

	-- Create SpawnHub model
	local spawnModel = Instance.new("Model")
	spawnModel.Name = "SpawnHub"
	spawnModel.Parent = generated

	-- Config
	local spawnX = WorldConfig.SPAWN_CENTER_X or 0
	local spawnZ = WorldConfig.SPAWN_CENTER_Z or 0
	local flatR = WorldConfig.SPAWN_FLAT_RADIUS or 60

	local h = WorldHeight.heightAt(spawnX, spawnZ)
	local groundY = (WorldConfig.BASE_Y or 0) + h
	local spawnPos = Vector3.new(spawnX, groundY, spawnZ)

	-- =========================================================
	-- Flatten terrain for EDITOR preview (does NOT bury the house)
	-- =========================================================
	-- Terrain:FillBlock fills a FULL 3D box. We want the TOP of the box
	-- to sit at (groundY + TOP_OFFSET) and the rest goes downward.
	local THICKNESS = 40       -- how deep it goes down
	local TOP_OFFSET = 0.5     -- top surface slightly above ground (prevents tiny holes)

	local size = Vector3.new(flatR * 2, THICKNESS, flatR * 2)

	-- Center Y so that: top = centerY + THICKNESS/2 = groundY + TOP_OFFSET
	local centerY = (groundY + TOP_OFFSET) - (THICKNESS / 2)
	local cf = CFrame.new(spawnPos.X, centerY, spawnPos.Z)

	Terrain:FillBlock(cf, size, Enum.Material.Grass)

	-- House
	local houseTemplate = ServerStorage
		:WaitForChild("Templates")
		:WaitForChild("Structures")
		:WaitForChild("House1")

	local house = houseTemplate:Clone()
	house.Name = "House"
	house.Parent = spawnModel

	local _, houseSize = house:GetBoundingBox()
	local houseOffsetBack = 20
	local houseRotation = CFrame.Angles(0, math.rad(180), 0)

	house:PivotTo(
		CFrame.new(spawnPos.X, groundY + houseSize.Y/2, spawnPos.Z - houseOffsetBack)
			* houseRotation
	)
	anchorModel(house, true)

	-- DropZone
	local dropZone = Instance.new("Part")
	dropZone.Name = "DropZone"
	dropZone.Shape = Enum.PartType.Cylinder
	dropZone.Anchored = true
	dropZone.CanCollide = false
	dropZone.Material = Enum.Material.Neon
	dropZone.Color = Color3.fromRGB(255, 220, 120)
	dropZone.Transparency = 0.15
	dropZone.Size = Vector3.new(1, 12, 12)
	dropZone.Parent = spawnModel

	local dropForward = 18
	dropZone.CFrame =
		CFrame.new(spawnPos.X, groundY + 0.2, spawnPos.Z - houseOffsetBack + dropForward)
		* CFrame.Angles(0, 0, math.rad(90))

	-- SpawnLocation (create if missing)
	local spawnLocation = workspace:FindFirstChildOfClass("SpawnLocation")
	if not spawnLocation then
		spawnLocation = Instance.new("SpawnLocation")
		spawnLocation.Name = "SpawnLocation"
		spawnLocation.Parent = workspace
	end

	spawnLocation.Anchored = true
	spawnLocation.Position = Vector3.new(spawnPos.X, groundY + 3, spawnPos.Z)
	spawnLocation.Neutral = true

	print("[SpawnHubBuilder] SpawnHub baked into Workspace. groundY=", groundY, "flatR=", flatR)
end

return SpawnHubBuilder