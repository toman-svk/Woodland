--!strict
-- src/server/Gameplay/Systems/BuildingService/init.luau
--
-- SERVER-SIDE building placement, persistence, and construction timers.
--
-- ── ADDING A NEW BUILDING TYPE ────────────────────────────────────────────────
-- 1. Add an entry to BUILDING_CONFIGS with the type key, template name, etc.
-- 2. Put a Model named exactly `templateName` in ServerStorage/Templates/Structures/.
--    Its pivot should be set at the base (ground level).
--
-- ── HOW PERSISTENCE WORKS ────────────────────────────────────────────────────
-- When a building is placed it is appended to save.structures.placed.
-- On world load, RestoreFromSave() clones each entry back into the world.
-- If buildEndsAt is in the future the construction timer is resumed
-- (the building wasn't finished when the server shut down).
--
-- ── HOW THE TIMER BILLBOARD WORKS ────────────────────────────────────────────
-- BuildingService sets these attributes on the placed Model while it's
-- under construction. The client-side StructureTimerBillboard.client.luau
-- watches for any model with ConstructionActive = true and shows a timer.
-- This means the billboard is automatic — no per-building client code needed.
--
--   ConstructionActive   (boolean)  true while building, false when done
--   ConstructionEndTime  (number)   os.time() when construction finishes
--   ConstructionDuration (number)   total seconds of construction
--   ConstructionLabel    (string)   e.g. "Building Trebuchet..."

local Players             = game:GetService("Players")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerStorage       = game:GetService("ServerStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local WorldService = require(
	ServerScriptService
		:WaitForChild("Server")
		:WaitForChild("Gameplay")
		:WaitForChild("World")
		:WaitForChild("Runtime")
		:WaitForChild("WorldService")
)

local Shared        = ReplicatedStorage:WaitForChild("Shared")
local Remotes       = Shared:WaitForChild("Remotes")
local PlaceBuilding = Remotes:WaitForChild("PlaceBuilding") :: RemoteEvent

-- ── Building definitions ──────────────────────────────────────────────────────

type BuildingConfig = {
	templateName:    string,   -- Model name inside ServerStorage/Templates/Structures/
	sizeRadius:      number,   -- sphere radius for overlap/occupancy check
	buildDuration:   number,   -- seconds from placement to completion
	maxHealth:       number,   -- starting and maximum health (0–100)
}

local BUILDING_CONFIGS: { [string]: BuildingConfig } = {
	-- buildingType key → config
	-- The key is what HammerClient sends as `buildingId`.
	-- templateName is the Model name inside ServerStorage/Templates/Structures/.
	Trebuchet = {
		templateName  = "Ballista1",
		sizeRadius    = 6,
		buildDuration = 10,
		maxHealth     = 100,
	},
}

-- How far (studs) a player can place a building from their own position.
local MAX_PLACE_DISTANCE = 80

-- ── State ─────────────────────────────────────────────────────────────────────
-- Maps uid → the live Model in the world. Used to update/destroy buildings
-- without scanning the Buildings folder every time.
local spawnedByUid: { [string]: Model } = {}

-- ── Template helpers ──────────────────────────────────────────────────────────

-- Loads a template Model from ServerStorage/Templates/Structures/.
-- ServerStorage is server-only — clients can never access it, which means
-- building assets are never exposed to potential exploiters.
local function getTemplate(templateName: string): Model?
	local ok, result = pcall(function()
		return ServerStorage
			:WaitForChild("Templates", 5)
			:WaitForChild("Structures", 5)
			:FindFirstChild(templateName)
	end)
	if not ok or not result then
		return nil
	end
	if result:IsA("Model") then
		return result :: Model
	end
	return nil
end

-- ── World helpers ─────────────────────────────────────────────────────────────

-- Gets or lazily creates the Buildings folder inside the world's generated folder.
-- All placed building Models live here.
local function getBuildingsFolder(): Folder?
	local world = WorldService.GetCurrentWorld()
	if not world then return nil end
	local f = world.generated:FindFirstChild("Buildings")
	if f and f:IsA("Folder") then return f :: Folder end
	local newF  = Instance.new("Folder")
	newF.Name   = "Buildings"
	newF.Parent = world.generated
	return newF
end

-- Returns true if a spot is already occupied by another building's Parts.
local function isPositionOccupied(position: Vector3, radius: number): boolean
	local folder = getBuildingsFolder()
	if not folder then return false end
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { folder }
	return #workspace:GetPartBoundsInRadius(position, radius, params) > 0
end

-- ── Construction timer ────────────────────────────────────────────────────────
-- Sets the standard construction attributes on a Model so the client billboard
-- can display a timer without knowing anything about the building type.
local function setConstructionAttributes(model: Model, endTime: number, duration: number, label: string)
	model:SetAttribute("ConstructionActive",   true)
	model:SetAttribute("ConstructionEndTime",  endTime)
	model:SetAttribute("ConstructionDuration", duration)
	model:SetAttribute("ConstructionLabel",    label)
end

local function clearConstructionAttributes(model: Model)
	model:SetAttribute("ConstructionActive", false)
	-- Leave EndTime/Duration so the client can show "just finished" if needed.
end

-- Schedules the completion of a building after `secondsRemaining` seconds.
-- When it fires: clears the timer attributes, updates the save entry.
local function scheduleCompletion(uid: string, secondsRemaining: number)
	task.delay(math.max(0, secondsRemaining), function()
		local model = spawnedByUid[uid]
		if not model or not model.Parent then return end

		clearConstructionAttributes(model)

		-- Update the save: buildEndsAt = nil means construction is complete.
		local world = WorldService.GetCurrentWorld()
		if world then
			for _, entry in ipairs(world.save.structures.placed) do
				if entry.uid == uid then
					entry.buildEndsAt = nil
					break
				end
			end
			WorldService.MarkDirty()
		end

		print(("[BuildingService] Construction complete: uid=%s"):format(uid))
	end)
end

-- ── Spawn a building model ────────────────────────────────────────────────────
-- Clones the template (or spawns a placeholder) and places it at `position`.
-- Does NOT start the construction timer — caller handles that.
local function spawnModel(
	uid:          string,
	buildingType: string,
	config:       BuildingConfig,
	position:     Vector3,
	parent:       Instance
): Model
	local template = getTemplate(config.templateName)

	local model: Model
	if template then
		model = template:Clone()
		model.Name = buildingType
		model:PivotTo(CFrame.new(position))
	else
		warn(("[BuildingService] No template '%s' found — spawning placeholder."):format(config.templateName))
		model = Instance.new("Model")
		model.Name = buildingType

		local body = Instance.new("Part")
		body.Name     = "Body"
		body.Size     = Vector3.new(8, 6, 8)
		body.Material = Enum.Material.Concrete
		body.Color    = Color3.fromRGB(120, 120, 120)
		body.Anchored = true
		body.Position = position + Vector3.new(0, 3, 0)
		body.Parent   = model

		local tag = Instance.new("BillboardGui")
		tag.Size         = UDim2.fromOffset(160, 40)
		tag.StudsOffset  = Vector3.new(0, 5, 0)
		tag.AlwaysOnTop  = false
		tag.Parent       = body
		local lbl        = Instance.new("TextLabel")
		lbl.Size         = UDim2.fromScale(1, 1)
		lbl.BackgroundTransparency = 1
		lbl.Text         = buildingType .. "\n(placeholder)"
		lbl.TextScaled   = true
		lbl.Font         = Enum.Font.GothamBold
		lbl.TextColor3   = Color3.fromRGB(255, 255, 255)
		lbl.Parent       = tag

		model.PrimaryPart = body
	end

	-- Tag the model with its uid so other systems can identify it.
	model:SetAttribute("BuildingUid",  uid)
	model:SetAttribute("BuildingType", buildingType)
	model:SetAttribute("Health",       config.maxHealth)
	model.Parent = parent

	spawnedByUid[uid] = model
	return model
end

-- ── Public: PlaceBuilding ─────────────────────────────────────────────────────

local BuildingService = {}
local started = false

-- Validates and places a new building at `position`.
-- Called both from the OnServerEvent handler (new placements)
-- and RestoreFromSave (loading existing ones).
--
-- `isRestore` = true skips the distance and occupancy checks,
-- because a restored building was already validated when first placed.
function BuildingService.PlaceBuilding(
	player:      Player?,     -- nil when called from RestoreFromSave
	buildingType: string,
	position:    Vector3,
	savedUid:    string?,     -- supply when restoring; nil = generate fresh uid
	savedHealth: number?,     -- restore saved health value
	savedBuildEndsAt: number? -- restore timer state
): boolean

	local config = BUILDING_CONFIGS[buildingType]
	if not config then
		warn("[BuildingService] Unknown buildingType:", buildingType)
		return false
	end

	-- ── Validate new placements only ──────────────────────────────────────
	local isRestore = savedUid ~= nil
	if not isRestore then
		if player then
			local char = player.Character
			if not char then return false end
			local hrp = char:FindFirstChild("HumanoidRootPart") :: BasePart?
			if not hrp then return false end

			local dist = ((hrp :: BasePart).Position - position).Magnitude
			if dist > MAX_PLACE_DISTANCE then
				warn(("[BuildingService] Placement rejected: too far (%.1f studs) for %s"):format(dist, player.Name))
				return false
			end
		end

		if isPositionOccupied(position, config.sizeRadius) then
			warn("[BuildingService] Placement rejected: position already occupied.")
			return false
		end
	end

	-- ── Get Buildings folder ───────────────────────────────────────────────
	local buildingsFolder = getBuildingsFolder()
	if not buildingsFolder then
		warn("[BuildingService] No world available, cannot place building.")
		return false
	end

	-- ── Generate uid ──────────────────────────────────────────────────────
	-- The uid uniquely identifies this building instance in the save.
	-- Format: "Type_timestamp_random" — collision probability is negligible.
	local uid = savedUid or (buildingType .. "_" .. tostring(os.time()) .. "_" .. tostring(math.random(100000, 999999)))

	-- ── Spawn the model ───────────────────────────────────────────────────
	local model = spawnModel(uid, buildingType, config, position, buildingsFolder)

	-- ── Determine construction state ──────────────────────────────────────
	-- New placement: start a fresh 10-second timer.
	-- Restore: check if buildEndsAt is in the future (timer was interrupted by server restart).
	local endTime: number
	local secondsRemaining: number

	if isRestore and savedBuildEndsAt ~= nil then
		-- Server restarted mid-construction — resume the timer from where it left off.
		endTime          = savedBuildEndsAt
		secondsRemaining = math.max(0, endTime - os.time())
	elseif isRestore and savedBuildEndsAt == nil then
		-- Construction was already complete when saved — no timer needed.
		clearConstructionAttributes(model)
		if savedHealth then
			model:SetAttribute("Health", savedHealth)
		end
		print(("[BuildingService] Restored complete building: %s uid=%s"):format(buildingType, uid))
		return true
	else
		-- Brand-new placement — start a fresh construction timer.
		endTime          = os.time() + config.buildDuration
		secondsRemaining = config.buildDuration
	end

	-- Show the construction timer on the model (visible to all clients
	-- via StructureTimerBillboard.client.luau which watches for this attribute).
	setConstructionAttributes(
		model,
		endTime,
		config.buildDuration,
		"Building " .. buildingType .. "..."
	)

	scheduleCompletion(uid, secondsRemaining)

	-- ── Persist ───────────────────────────────────────────────────────────
	local world = WorldService.GetCurrentWorld()
	if world then
		if not isRestore then
			-- New placement: append to the save array.
			table.insert(world.save.structures.placed, {
				uid          = uid,
				buildingType = buildingType,
				px           = position.X,
				py           = position.Y,
				pz           = position.Z,
				health       = config.maxHealth,
				buildEndsAt  = endTime,
			})
		end
		WorldService.MarkDirty()
	end

	print(("[BuildingService] %s '%s' at %s. uid=%s secondsLeft=%.1f"):format(
		if isRestore then "Restored" else "Placed",
		buildingType,
		tostring(position),
		uid,
		secondsRemaining
	))
	return true
end

-- ── Restore from save ─────────────────────────────────────────────────────────
-- Called once when the world becomes available. Spawns every previously placed
-- building back into the world, resuming construction timers if needed.
function BuildingService.RestoreFromSave()
	local world = WorldService.GetCurrentWorld()
	if not world then return end

	local placed = world.save.structures.placed
	if not placed or #placed == 0 then
		print("[BuildingService] No saved buildings to restore.")
		return
	end

	print(("[BuildingService] Restoring %d saved buildings..."):format(#placed))
	for _, entry in ipairs(placed) do
		BuildingService.PlaceBuilding(
			nil,                                          -- no player (restore)
			entry.buildingType,
			Vector3.new(entry.px, entry.py, entry.pz),
			entry.uid,                                    -- savedUid → marks as restore
			entry.health,
			entry.buildEndsAt
		)
	end
end

-- ── Start ─────────────────────────────────────────────────────────────────────

function BuildingService.Start()
	if started then return end
	started = true

	-- Listen for new placement requests from HammerClient.
	PlaceBuilding.OnServerEvent:Connect(function(player: Player, data: any)
		if typeof(data) ~= "table" then return end
		local buildingType = data.buildingId
		local position     = data.position
		if typeof(buildingType) ~= "string"  then return end
		if typeof(position)     ~= "Vector3" then return end

		BuildingService.PlaceBuilding(player, buildingType, position, nil, nil, nil)
	end)

	-- Wait for the world to be available, then restore saved buildings.
	-- The world is created asynchronously (when the first player joins),
	-- so we poll briefly rather than blocking GameplayBootstrap.
	task.spawn(function()
		local TIMEOUT = 60  -- seconds; give up if world never appears (shouldn't happen)
		local elapsed = 0
		while WorldService.GetCurrentWorld() == nil and elapsed < TIMEOUT do
			task.wait(0.5)
			elapsed += 0.5
		end
		BuildingService.RestoreFromSave()
	end)

	Players.PlayerRemoving:Connect(function()
		-- No per-player building state to clean up yet.
	end)

	print("[BuildingService] Started.")
end

return BuildingService
