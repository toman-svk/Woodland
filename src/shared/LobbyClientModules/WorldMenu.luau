--!strict
-- src/shared/LobbyClientModules/WorldMenu.client.luau

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui

local shared = ReplicatedStorage:WaitForChild("Shared")
local remotes = shared:WaitForChild("Remotes")
local lobbyUI = remotes:WaitForChild("LobbyUI") :: Folder

local openWorldMenu = lobbyUI:WaitForChild("OpenWorldMenu") :: RemoteEvent

-- New remotes (create these as RemoteFunctions in ReplicatedStorage.Shared.Remotes)
local getWorldsRF = lobbyUI:WaitForChild("GetWorlds") :: RemoteFunction
local createWorldRF = lobbyUI:WaitForChild("CreateWorld") :: RemoteFunction
local deleteWorldRF = lobbyUI:WaitForChild("DeleteWorld") :: RemoteFunction
local joinWorldRF = lobbyUI:WaitForChild("JoinWorld") :: RemoteFunction

export type WorldInfo = {
	id: string,
	name: string,
	createdAt: number,
	seed: number?,
}

type UiRefs = {
	gui: ScreenGui,
	panel: Frame,
	list: ScrollingFrame,
	status: TextLabel,
	addButton: TextButton,
	createPanel: Frame,
	nameBox: TextBox,
	createBtn: TextButton,
	cancelBtn: TextButton,
	closeBtn: TextButton,
}

local refs: UiRefs? = nil

local function mkUICorner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function mkUIPadding(parent: Instance, pad: number)
	local p = Instance.new("UIPadding")
	p.PaddingTop = UDim.new(0, pad)
	p.PaddingBottom = UDim.new(0, pad)
	p.PaddingLeft = UDim.new(0, pad)
	p.PaddingRight = UDim.new(0, pad)
	p.Parent = parent
end

local function mkStroke(parent: Instance, thickness: number)
	local s = Instance.new("UIStroke")
	s.Thickness = thickness
	s.Parent = parent
end

local function clearChildren(container: Instance)
	for _, c in ipairs(container:GetChildren()) do
		if c:IsA("GuiObject") or c:IsA("UIBase") then
			c:Destroy()
		end
	end
end

local function ensureGui(): UiRefs
	if refs then
		return refs
	end

	local existing = playerGui:FindFirstChild("WorldMenuGui")
	if existing then
		existing:Destroy()
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "WorldMenuGui"
	gui.ResetOnSpawn = false
	gui.Enabled = false
	gui.Parent = playerGui

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromScale(0.52, 0.55)
	panel.Parent = gui
	panel.BackgroundColor3 = Color3.fromRGB(220, 220, 220)
	mkUICorner(panel, 10)
	mkStroke(panel, 1)
	mkUIPadding(panel, 10)

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, 0, 0, 40)
	title.Text = "Worlds"
	title.TextScaled = true
	title.Font = Enum.Font.GothamBold
	title.TextColor3 = Color3.fromRGB(30, 30, 30)
	title.Parent = panel

	local close = Instance.new("TextButton")
	close.Name = "Close"
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -6, 0, 6)
	close.Size = UDim2.fromOffset(44, 32)
	close.Text = "X"
	close.TextScaled = true
	close.Font = Enum.Font.GothamBold
	close.BackgroundColor3 = Color3.fromRGB(235, 235, 235)
	close.TextColor3 = Color3.fromRGB(40, 40, 40)
	close.Parent = panel
	mkUICorner(close, 8)
	mkStroke(close, 1)

	local add = Instance.new("TextButton")
	add.Name = "AddWorld"
	add.Position = UDim2.new(0, 0, 0, 52)
	add.Size = UDim2.fromOffset(160, 36)
	add.Text = "+ Add World"
	add.TextScaled = true
	add.Font = Enum.Font.GothamBold
	add.BackgroundColor3 = Color3.fromRGB(200, 230, 200)
	add.TextColor3 = Color3.fromRGB(20, 60, 20)
	add.Parent = panel
	mkUICorner(add, 8)
	mkStroke(add, 1)

	local status = Instance.new("TextLabel")
	status.Name = "Status"
	status.BackgroundTransparency = 1
	status.Position = UDim2.new(0, 170, 0, 52)
	status.Size = UDim2.new(1, -170, 0, 36)
	status.TextXAlignment = Enum.TextXAlignment.Left
	status.TextScaled = true
	status.Font = Enum.Font.Gotham
	status.TextColor3 = Color3.fromRGB(60, 60, 60)
	status.Text = ""
	status.Parent = panel

	local list = Instance.new("ScrollingFrame")
	list.Name = "WorldList"
	list.Position = UDim2.new(0, 0, 0, 96)
	list.Size = UDim2.new(1, 0, 1, -106)
	list.BackgroundColor3 = Color3.fromRGB(245, 245, 245)
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 8
	list.CanvasSize = UDim2.fromOffset(0, 0)
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.Parent = panel
	mkUICorner(list, 10)
	mkStroke(list, 1)
	mkUIPadding(list, 8)

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list

	-- Create panel (hidden)
	local createPanel = Instance.new("Frame")
	createPanel.Name = "CreatePanel"
	createPanel.Visible = false
	createPanel.AnchorPoint = Vector2.new(0.5, 0.5)
	createPanel.Position = UDim2.fromScale(0.5, 0.5)
	createPanel.Size = UDim2.fromScale(0.55, 0.35)
	createPanel.BackgroundColor3 = Color3.fromRGB(245, 245, 245)
	createPanel.Parent = gui
	mkUICorner(createPanel, 10)
	mkStroke(createPanel, 1)
	mkUIPadding(createPanel, 10)

	local cpTitle = Instance.new("TextLabel")
	cpTitle.BackgroundTransparency = 1
	cpTitle.Size = UDim2.new(1, 0, 0, 32)
	cpTitle.Text = "Create World"
	cpTitle.TextScaled = true
	cpTitle.Font = Enum.Font.GothamBold
	cpTitle.TextColor3 = Color3.fromRGB(30, 30, 30)
	cpTitle.Parent = createPanel

	local nameBox = Instance.new("TextBox")
	nameBox.Name = "NameBox"
	nameBox.Position = UDim2.new(0, 0, 0, 44)
	nameBox.Size = UDim2.new(1, 0, 0, 36)
	nameBox.PlaceholderText = "World name (e.g. My First World)"
	nameBox.Text = ""
	nameBox.TextScaled = true
	nameBox.Font = Enum.Font.Gotham
	nameBox.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	nameBox.TextColor3 = Color3.fromRGB(20, 20, 20)
	nameBox.ClearTextOnFocus = false
	nameBox.Parent = createPanel
	mkUICorner(nameBox, 8)
	mkStroke(nameBox, 1)
	mkUIPadding(nameBox, 6)

	local createBtn = Instance.new("TextButton")
	createBtn.Name = "Create"
	createBtn.AnchorPoint = Vector2.new(0, 1)
	createBtn.Position = UDim2.new(0, 0, 1, 0)
	createBtn.Size = UDim2.fromOffset(160, 36)
	createBtn.Text = "Create"
	createBtn.TextScaled = true
	createBtn.Font = Enum.Font.GothamBold
	createBtn.BackgroundColor3 = Color3.fromRGB(200, 230, 200)
	createBtn.TextColor3 = Color3.fromRGB(20, 60, 20)
	createBtn.Parent = createPanel
	mkUICorner(createBtn, 8)
	mkStroke(createBtn, 1)

	local cancelBtn = Instance.new("TextButton")
	cancelBtn.Name = "Cancel"
	cancelBtn.AnchorPoint = Vector2.new(1, 1)
	cancelBtn.Position = UDim2.new(1, 0, 1, 0)
	cancelBtn.Size = UDim2.fromOffset(160, 36)
	cancelBtn.Text = "Cancel"
	cancelBtn.TextScaled = true
	cancelBtn.Font = Enum.Font.GothamBold
	cancelBtn.BackgroundColor3 = Color3.fromRGB(235, 235, 235)
	cancelBtn.TextColor3 = Color3.fromRGB(40, 40, 40)
	cancelBtn.Parent = createPanel
	mkUICorner(cancelBtn, 8)
	mkStroke(cancelBtn, 1)

	local built: UiRefs = {
		gui = gui,
		panel = panel,
		list = list,
		status = status,
		addButton = add,
		createPanel = createPanel,
		nameBox = nameBox,
		createBtn = createBtn,
		cancelBtn = cancelBtn,
		closeBtn = close,
	}

	refs = built
	return built
end

local function setStatus(text: string)
	local r = ensureGui()
	r.status.Text = text
end

local function createRow(world: WorldInfo, onDelete: (string) -> ())
	local r = ensureGui()

	local row = Instance.new("Frame")
	row.Name = "Row_" .. world.id
	row.Size = UDim2.new(1, 0, 0, 64) -- ✅ a bit taller for 2 lines
	row.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	row.Parent = r.list
	mkUICorner(row, 10)
	mkStroke(row, 1)
	mkUIPadding(row, 8)

	-- ✅ container for 2-line text on the left
	local left = Instance.new("Frame")
	left.Name = "Left"
	left.BackgroundTransparency = 1
	left.Position = UDim2.new(0, 0, 0, 0)
	left.Size = UDim2.new(1, -230, 1, 0) -- leave room for buttons
	left.Parent = row

	local leftLayout = Instance.new("UIListLayout")
	leftLayout.FillDirection = Enum.FillDirection.Vertical
	leftLayout.SortOrder = Enum.SortOrder.LayoutOrder
	leftLayout.Padding = UDim.new(0, 2)
	leftLayout.Parent = left

	local name = Instance.new("TextLabel")
	name.Name = "WorldName"
	name.BackgroundTransparency = 1
	name.Size = UDim2.new(1, 0, 0, 28)
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.TextScaled = true
	name.Font = Enum.Font.GothamBold
	name.TextColor3 = Color3.fromRGB(20, 20, 20)
	name.Text = world.name
	name.Parent = left

	-- ✅ NEW: small grey meta line
	local meta = Instance.new("TextLabel")
	meta.Name = "WorldMeta"
	meta.BackgroundTransparency = 1
	meta.Size = UDim2.new(1, 0, 0, 18)
	meta.TextXAlignment = Enum.TextXAlignment.Left
	meta.TextScaled = true
	meta.Font = Enum.Font.Gotham
	meta.TextColor3 = Color3.fromRGB(120, 120, 120)

	local seedText = if typeof(world.seed) == "number" then tostring(world.seed) else "?"
	meta.Text = ("ID: %s   Seed: %s"):format(world.id, seedText)
	meta.Parent = left

	local join = Instance.new("TextButton")
	join.Name = "Join"
	join.AnchorPoint = Vector2.new(1, 0.5)
	join.Position = UDim2.new(1, -110, 0.5, 0)
	join.Size = UDim2.fromOffset(100, 34)
	join.Text = "Join"
	join.TextScaled = true
	join.Font = Enum.Font.GothamBold
	join.BackgroundColor3 = Color3.fromRGB(200, 220, 235)
	join.TextColor3 = Color3.fromRGB(15, 35, 70)
	join.Parent = row
	mkUICorner(join, 8)
	mkStroke(join, 1)

	local del = Instance.new("TextButton")
	del.Name = "Delete"
	del.AnchorPoint = Vector2.new(1, 0.5)
	del.Position = UDim2.new(1, 0, 0.5, 0)
	del.Size = UDim2.fromOffset(100, 34)
	del.Text = "Delete"
	del.TextScaled = true
	del.Font = Enum.Font.GothamBold
	del.BackgroundColor3 = Color3.fromRGB(235, 200, 200)
	del.TextColor3 = Color3.fromRGB(90, 20, 20)
	del.Parent = row
	mkUICorner(del, 8)
	mkStroke(del, 1)

	join.MouseButton1Click:Connect(function()
		setStatus("Joining...")
		local ok, res = pcall(function()
			return joinWorldRF:InvokeServer(world.id)
		end)
		if not ok then
			setStatus("Join failed: " .. tostring(res))
			return
		end

		if type(res) ~= "table" or (res :: any).ok ~= true then
			setStatus("Join failed: " .. tostring((res :: any).error or "unknown"))
			return
		end

		setStatus("Teleporting...")
	end)

	del.MouseButton1Click:Connect(function()
		onDelete(world.id)
	end)
end

local function fetchWorlds(): ({WorldInfo}?, string?)
	local ok, result = pcall(function()
		return getWorldsRF:InvokeServer()
	end)
	if not ok then
		return nil, tostring(result)
	end

	if type(result) ~= "table" then
		return nil, "Server returned invalid GetWorlds result."
	end

	-- expected: { worlds = { {id,name,createdAt}, ... } }
	local worldsAny = (result :: any).worlds
	if type(worldsAny) ~= "table" then
		return {}, nil
	end

	return worldsAny :: {WorldInfo}, nil
end

local function renderWorlds(worlds: {WorldInfo})
	local r = ensureGui()
	clearChildren(r.list)

	-- re-add layout & padding (they were destroyed by clearChildren)
	mkUIPadding(r.list, 8)
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = r.list

	if #worlds == 0 then
		local empty = Instance.new("TextLabel")
		empty.BackgroundTransparency = 1
		empty.Size = UDim2.new(1, 0, 0, 40)
		empty.Text = "No worlds yet. Click + Add World."
		empty.TextScaled = true
		empty.Font = Enum.Font.Gotham
		empty.TextColor3 = Color3.fromRGB(70, 70, 70)
		empty.Parent = r.list
		return
	end

	local function onDelete(worldId: string)
		setStatus("Deleting...")
		local ok, res = pcall(function()
			return deleteWorldRF:InvokeServer(worldId)
		end)
		if not ok then
			setStatus("Delete failed: " .. tostring(res))
			return
		end

		local success = (res :: any).ok
		local err = (res :: any).error
		if success ~= true then
			setStatus("Delete failed: " .. tostring(err or "unknown"))
			return
		end

		setStatus("Deleted.")
		task.delay(0.8, function()
			setStatus("")
		end)

		-- refresh list
		local newWorlds, fetchErr = fetchWorlds()
		if newWorlds then
			renderWorlds(newWorlds)
		else
			setStatus("Refresh failed: " .. tostring(fetchErr))
		end
	end

	for i, w in ipairs(worlds) do
		-- basic validation so UI never explodes
		if type(w) == "table" and type(w.id) == "string" and type(w.name) == "string" then
			(w :: any).createdAt = (w :: any).createdAt or 0
			createRow(w, onDelete);
			(r.list:FindFirstChild("Row_" .. w.id) :: any).LayoutOrder = i
		end
	end
end

local function openMenu()
	local r = ensureGui()
	r.gui.Enabled = true
	r.createPanel.Visible = false
	setStatus("Loading...")

	local worlds, err = fetchWorlds()
	if not worlds then
		setStatus("Load failed: " .. tostring(err))
		renderWorlds({})
		return
	end

	setStatus("")
	renderWorlds(worlds)
end

local function wireUi()
	local r = ensureGui()

	r.closeBtn.MouseButton1Click:Connect(function()
		r.gui.Enabled = false
	end)

	r.addButton.MouseButton1Click:Connect(function()
		r.nameBox.Text = ""
		r.createPanel.Visible = true
		r.nameBox:CaptureFocus()
	end)

	r.cancelBtn.MouseButton1Click:Connect(function()
		r.createPanel.Visible = false
	end)

	r.createBtn.MouseButton1Click:Connect(function()
		local name = r.nameBox.Text
		name = string.gsub(name, "^%s+", "")
		name = string.gsub(name, "%s+$", "")

		if #name < 2 then
			setStatus("Name too short.")
			return
		end

		setStatus("Creating...")
		local ok, res = pcall(function()
			return createWorldRF:InvokeServer(name)
		end)
		if not ok then
			setStatus("Create failed: " .. tostring(res))
			return
		end

		local success = (res :: any).ok
		local err = (res :: any).error
		if success ~= true then
			setStatus("Create failed: " .. tostring(err or "unknown"))
			return
		end

		r.createPanel.Visible = false
		setStatus("Created.")
		task.delay(0.8, function()
			setStatus("")
		end)

		-- refresh list
		local worlds, fetchErr = fetchWorlds()
		if worlds then
			renderWorlds(worlds)
		else
			setStatus("Refresh failed: " .. tostring(fetchErr))
		end
	end)
end

local started = false

local M = {}

function M.Start()
	if started then
		return
	end
	started = true

	wireUi()

	openWorldMenu.OnClientEvent:Connect(function()
		openMenu()
	end)
end

return M