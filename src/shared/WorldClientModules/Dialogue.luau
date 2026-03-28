--!strict
-- src/shared/WorldClientModules/Dialogue.client.luau
-- Generic reusable dialogue / quest template.
-- Supports:
--   1) legacy string states ("QuestNotDone", ...)
--   2) payload tables for reusable quests/NPC dialogues

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui

local Shared = ReplicatedStorage:WaitForChild("Shared")
local RemotesFolder = Shared:WaitForChild("Remotes")
local GetRemote = require(RemotesFolder:WaitForChild("GetRemote"))

local openDialogue = GetRemote("OpenDialogue", "RemoteEvent") :: RemoteEvent
local dialogueChoice = GetRemote("DialogueChoice", "RemoteEvent") :: RemoteEvent

-- Default assets for legacy blacksmith dialogue
local WOOD_ICON = "rbxassetid://85144837910297"
local BETTER_AXE_ICON = "rbxassetid://88097304181361"
local REQUIRED_WOOD = 10

export type DialogueRow = {
	icon: string?,
	text: string?,
}

export type DialogueActions = {
	showAccept: boolean?,
	showDecline: boolean?,
	acceptText: string?,
	declineText: string?,
}

export type DialoguePayload = {
	title: string?,
	body: string?,
	requirement: DialogueRow?,
	reward: DialogueRow?,
	actions: DialogueActions?,
	context: {
		npcId: string?,
		dialogueId: string?,
	}?,
}

type UiRefs = {
	screenGui: ScreenGui,
	clickCatcher: TextButton,
	panel: Frame,
	title: TextLabel,
	closeBtn: TextButton,
	bodyText: TextLabel,
	reqRow: Frame,
	reqIcon: ImageLabel,
	reqText: TextLabel,
	rewardRow: Frame,
	rewardIcon: ImageLabel,
	rewardText: TextLabel,
	acceptBtn: TextButton,
	declineBtn: TextButton,
}

local refs: UiRefs? = nil
local started = false
local currentContext: {npcId: string?, dialogueId: string?}? = nil

local function displayName(): string
	return (player.DisplayName ~= "" and player.DisplayName) or player.Name
end

local function ensureUi(): UiRefs
	if refs ~= nil then
		return refs
	end

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "DialogueGui"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = false
	screenGui.DisplayOrder = 300
	screenGui.Parent = playerGui

	local clickCatcher = Instance.new("TextButton")
	clickCatcher.Name = "ClickCatcher"
	clickCatcher.Parent = screenGui
	clickCatcher.Size = UDim2.fromScale(1, 1)
	clickCatcher.Position = UDim2.fromScale(0, 0)
	clickCatcher.BackgroundTransparency = 1
	clickCatcher.BorderSizePixel = 0
	clickCatcher.Visible = false
	clickCatcher.ZIndex = 1
	clickCatcher.AutoButtonColor = false
	clickCatcher.Text = ""
	clickCatcher.Active = true

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.Parent = screenGui
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.BackgroundTransparency = 1
	panel.Visible = false
	panel.ZIndex = 10

	-- Body frame
	local bodyFrame = Instance.new("Frame")
	bodyFrame.Name = "Body"
	bodyFrame.Parent = panel
	bodyFrame.BackgroundColor3 = Color3.fromRGB(214, 198, 158)
	bodyFrame.BorderSizePixel = 0
	bodyFrame.Size = UDim2.new(1, 0, 1, 0)
	bodyFrame.ZIndex = 12

	local bodyCorner = Instance.new("UICorner")
	bodyCorner.CornerRadius = UDim.new(0, 18)
	bodyCorner.Parent = bodyFrame

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = Color3.fromRGB(70, 58, 38)
	stroke.Transparency = 0.20
	stroke.Parent = bodyFrame

	-- Content
	local content = Instance.new("Frame")
	content.Name = "Content"
	content.Parent = bodyFrame
	content.BackgroundTransparency = 1
	content.BorderSizePixel = 0
	content.Position = UDim2.fromOffset(0, 0)
	content.Size = UDim2.new(1, 0, 1, 0)
	content.ZIndex = 20

	local contentPadding = Instance.new("UIPadding")
	contentPadding.Parent = content
	contentPadding.PaddingTop = UDim.new(0, 26)
	contentPadding.PaddingBottom = UDim.new(0, 22)
	contentPadding.PaddingLeft = UDim.new(0, 44)
	contentPadding.PaddingRight = UDim.new(0, 44)

	-- Header
	local header = Instance.new("Frame")
	header.Parent = content
	header.BackgroundTransparency = 1
	header.Size = UDim2.new(1, 0, 0, 44)
	header.ZIndex = 21

	local title = Instance.new("TextLabel")
	title.Parent = header
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, -44, 1, 0)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextYAlignment = Enum.TextYAlignment.Center
	title.Font = Enum.Font.GothamBold
	title.TextSize = 26
	title.TextColor3 = Color3.fromRGB(35, 28, 18)
	title.Text = "John — Blacksmith"
	title.ZIndex = 22

	local closeBtn = Instance.new("TextButton")
	closeBtn.Parent = header
	closeBtn.BackgroundTransparency = 1
	closeBtn.Size = UDim2.fromOffset(44, 44)
	closeBtn.Position = UDim2.new(1, -44, 0, 0)
	closeBtn.Text = "✕"
	closeBtn.Font = Enum.Font.GothamBold
	closeBtn.TextSize = 26
	closeBtn.TextColor3 = Color3.fromRGB(35, 28, 18)
	closeBtn.AutoButtonColor = true
	closeBtn.ZIndex = 23

	-- Body text
	local bodyText = Instance.new("TextLabel")
	bodyText.Parent = content
	bodyText.BackgroundTransparency = 1
	bodyText.Position = UDim2.fromOffset(0, 52)
	bodyText.Size = UDim2.new(1, 0, 1, -52 - 230)
	bodyText.TextWrapped = true
	bodyText.TextXAlignment = Enum.TextXAlignment.Left
	bodyText.TextYAlignment = Enum.TextYAlignment.Top
	bodyText.Font = Enum.Font.GothamMedium
	bodyText.TextSize = 22
	bodyText.TextColor3 = Color3.fromRGB(35, 28, 18)
	bodyText.Text = ""
	bodyText.ZIndex = 21

	-- Footer
	local footer = Instance.new("Frame")
	footer.Parent = content
	footer.BackgroundTransparency = 1
	footer.AnchorPoint = Vector2.new(0, 1)
	footer.Position = UDim2.new(0, 0, 1, 0)
	footer.Size = UDim2.new(1, 0, 0, 220)
	footer.ZIndex = 21

	local footerLayout = Instance.new("UIListLayout")
	footerLayout.Parent = footer
	footerLayout.FillDirection = Enum.FillDirection.Vertical
	footerLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	footerLayout.VerticalAlignment = Enum.VerticalAlignment.Top
	footerLayout.Padding = UDim.new(0, 10)
	footerLayout.SortOrder = Enum.SortOrder.LayoutOrder

	local function makeRow(): (Frame, ImageLabel, TextLabel)
		local row = Instance.new("Frame")
		row.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		row.BackgroundTransparency = 0.65
		row.BorderSizePixel = 0
		row.Size = UDim2.new(1, 0, 0, 44)
		row.ZIndex = 21

		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, 12)
		c.Parent = row

		local s = Instance.new("UIStroke")
		s.Thickness = 1
		s.Color = Color3.fromRGB(90, 70, 40)
		s.Transparency = 0.55
		s.Parent = row

		local icon = Instance.new("ImageLabel")
		icon.Parent = row
		icon.BackgroundTransparency = 1
		icon.Size = UDim2.fromOffset(30, 30)
		icon.Position = UDim2.fromOffset(12, 7)
		icon.ZIndex = 22

		local txt = Instance.new("TextLabel")
		txt.Parent = row
		txt.BackgroundTransparency = 1
		txt.Position = UDim2.fromOffset(54, 0)
		txt.Size = UDim2.new(1, -62, 1, 0)
		txt.TextXAlignment = Enum.TextXAlignment.Left
		txt.TextYAlignment = Enum.TextYAlignment.Center
		txt.Font = Enum.Font.GothamBold
		txt.TextSize = 20
		txt.TextColor3 = Color3.fromRGB(35, 28, 18)
		txt.ZIndex = 22

		return row, icon, txt
	end

	local reqRow, reqIcon, reqText = makeRow()
	reqRow.LayoutOrder = 1
	reqRow.Parent = footer

	local rewardRow, rewardIcon, rewardText = makeRow()
	rewardRow.LayoutOrder = 2
	rewardRow.Parent = footer

	-- Buttons row
	local buttonsRow = Instance.new("Frame")
	buttonsRow.Name = "ButtonsRow"
	buttonsRow.BackgroundTransparency = 1
	buttonsRow.Size = UDim2.new(1, 0, 0, 48)
	buttonsRow.LayoutOrder = 3
	buttonsRow.Parent = footer
	buttonsRow.ZIndex = 21

	local acceptBtn = Instance.new("TextButton")
	acceptBtn.Name = "Accept"
	acceptBtn.Size = UDim2.new(0.48, 0, 1, 0)
	acceptBtn.Position = UDim2.new(0, 0, 0, 0)
	acceptBtn.Text = "Accept"
	acceptBtn.Font = Enum.Font.GothamBold
	acceptBtn.TextSize = 22
	acceptBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	acceptBtn.BackgroundColor3 = Color3.fromRGB(55, 140, 70)
	acceptBtn.ZIndex = 22
	acceptBtn.Parent = buttonsRow

	local acceptCorner = Instance.new("UICorner")
	acceptCorner.CornerRadius = UDim.new(0, 12)
	acceptCorner.Parent = acceptBtn

	local acceptStroke = Instance.new("UIStroke")
	acceptStroke.Thickness = 1
	acceptStroke.Color = Color3.fromRGB(25, 80, 35)
	acceptStroke.Transparency = 0.25
	acceptStroke.Parent = acceptBtn

	local declineBtn = Instance.new("TextButton")
	declineBtn.Name = "Decline"
	declineBtn.Size = UDim2.new(0.48, 0, 1, 0)
	declineBtn.Position = UDim2.new(0.52, 0, 0, 0)
	declineBtn.Text = "Decline"
	declineBtn.Font = Enum.Font.GothamBold
	declineBtn.TextSize = 22
	declineBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	declineBtn.BackgroundColor3 = Color3.fromRGB(110, 35, 35)
	declineBtn.ZIndex = 22
	declineBtn.Parent = buttonsRow

	local declineCorner = Instance.new("UICorner")
	declineCorner.CornerRadius = UDim.new(0, 12)
	declineCorner.Parent = declineBtn

	local declineStroke = Instance.new("UIStroke")
	declineStroke.Thickness = 1
	declineStroke.Color = Color3.fromRGB(65, 15, 15)
	declineStroke.Transparency = 0.25
	declineStroke.Parent = declineBtn

	local r: UiRefs = {
		screenGui = screenGui,
		clickCatcher = clickCatcher,
		panel = panel,
		title = title,
		closeBtn = closeBtn,
		bodyText = bodyText,
		reqRow = reqRow,
		reqIcon = reqIcon,
		reqText = reqText,
		rewardRow = rewardRow,
		rewardIcon = rewardIcon,
		rewardText = rewardText,
		acceptBtn = acceptBtn,
		declineBtn = declineBtn,
	}

	refs = r
	return r
end

local function applyPanelLayout(panel: Frame)
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end
	local vp = cam.ViewportSize

	local insetTopLeft, insetBottomRight = GuiService:GetGuiInset()
	local topSafe = insetTopLeft.Y + 24
	local bottomSafe = insetBottomRight.Y + 160

	local availableH = math.max(240, math.floor(vp.Y - topSafe - bottomSafe))
	local w = math.clamp(math.floor(vp.X * 0.66), 520, 860)

	local targetRatio = 1.10
	local idealH = math.floor(w / targetRatio)
	local h = math.min(idealH, availableH)
	h = math.max(h, 500)

	panel.Size = UDim2.fromOffset(w, h)

	local desiredCenterY = math.floor(vp.Y * 0.50)
	local halfH = math.floor(h / 2)

	local minCenterY = topSafe + halfH
	local maxCenterY = vp.Y - bottomSafe - halfH

	local cy: number
	if maxCenterY < minCenterY then
		cy = math.floor((minCenterY + maxCenterY) / 2)
	else
		cy = math.clamp(desiredCenterY, minCenterY, maxCenterY)
	end

	panel.Position = UDim2.fromOffset(math.floor(vp.X / 2), cy)
end

local function hide(r: UiRefs)
	r.panel.Visible = false
	r.clickCatcher.Visible = false
	currentContext = nil
end

local function applyPayload(r: UiRefs, payload: DialoguePayload)
	r.title.Text = payload.title or "Dialogue"
	r.bodyText.Text = payload.body or ""

	if payload.requirement and payload.requirement.text then
		r.reqRow.Visible = true
		r.reqText.Text = payload.requirement.text
		r.reqIcon.Image = payload.requirement.icon or ""
	else
		r.reqRow.Visible = false
	end

	if payload.reward and payload.reward.text then
		r.rewardRow.Visible = true
		r.rewardText.Text = payload.reward.text
		r.rewardIcon.Image = payload.reward.icon or ""
	else
		r.rewardRow.Visible = false
	end

	local actions = payload.actions
	if actions then
		r.acceptBtn.Visible = actions.showAccept == true
		r.declineBtn.Visible = actions.showDecline == true
		r.acceptBtn.Text = actions.acceptText or "Accept"
		r.declineBtn.Text = actions.declineText or "Decline"
	else
		r.acceptBtn.Visible = false
		r.declineBtn.Visible = false
	end

	currentContext = payload.context
end

local function legacyPayloadFromState(state: any): DialoguePayload
	if state == "QuestNotDone" then
		return {
			title = "John — Blacksmith",
			body =
				("Welcome to Woodland, %s!\n\n"):format(displayName())
				.. "I’m John, the local blacksmith. My forge is running cold and I need wood to keep the furnace alive.\n"
				.. "Bring me enough and I’ll reinforce your axe so it bites deeper into the trees.",
			requirement = {
				icon = WOOD_ICON,
				text = ("Need: %d Wood"):format(REQUIRED_WOOD),
			},
			reward = {
				icon = BETTER_AXE_ICON,
				text = "Reward: Better Axe",
			},
			actions = {
				showAccept = true,
				showDecline = true,
				acceptText = "Accept",
				declineText = "Decline",
			},
		}
	elseif state == "QuestComplete" then
		return {
			title = "John — Blacksmith",
			body =
				("Excellent work, %s!\n\n"):format(displayName())
				.. "That wood will keep the furnace roaring. Here — take this improved axe.\n"
				.. "It’s balanced better and should make chopping feel much faster.",
			reward = {
				icon = BETTER_AXE_ICON,
				text = "Reward: Better Axe",
			},
			actions = {
				showAccept = false,
				showDecline = false,
			},
		}
	elseif state == "AlreadyDone" then
		return {
			title = "John — Blacksmith",
			body =
				("Good to see you again, %s!\n\n"):format(displayName())
				.. "Your improved axe should serve you well. If you need more upgrades later, come back with materials.",
			actions = {
				showAccept = false,
				showDecline = false,
			},
		}
	elseif state == "NoWoodStat" then
		return {
			title = "John — Blacksmith",
			body =
				("Hmm… %s, I can’t see your wood count yet.\n\n"):format(displayName())
				.. "Try chopping a tree first — then come back and we’ll talk upgrades.",
			actions = {
				showAccept = false,
				showDecline = false,
			},
		}
	else
		return {
			title = "Dialogue",
			body = ("[Unknown state: %s]"):format(tostring(state)),
			actions = {
				showAccept = false,
				showDecline = false,
			},
		}
	end
end

local M = {}

function M.Start()
	if started then
		return
	end
	started = true

	local r = ensureUi()

	r.closeBtn.MouseButton1Click:Connect(function()
		hide(r)
	end)

	r.clickCatcher.MouseButton1Click:Connect(function()
		hide(r)
	end)

	r.acceptBtn.MouseButton1Click:Connect(function()
		if currentContext then
			dialogueChoice:FireServer({
				npcId = currentContext.npcId,
				dialogueId = currentContext.dialogueId,
				choice = "Accept",
			})
		end

		hide(r)
	end)

	r.declineBtn.MouseButton1Click:Connect(function()
		if currentContext then
			dialogueChoice:FireServer({
				npcId = currentContext.npcId,
				dialogueId = currentContext.dialogueId,
				choice = "Decline",
			})
		end

		hide(r)
	end)

	UserInputService.InputBegan:Connect(function(input, gp)
		if gp then
			return
		end
		if not r.panel.Visible then
			return
		end
		if input.KeyCode == Enum.KeyCode.Escape then
			hide(r)
		end
	end)

	local function bindViewportResize()
		local cam = workspace.CurrentCamera
		if not cam then
			return
		end
		cam:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			if r.panel.Visible then
				applyPanelLayout(r.panel)
			end
		end)
	end

	bindViewportResize()
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bindViewportResize)

	openDialogue.OnClientEvent:Connect(function(data)
		local payload: DialoguePayload

		if type(data) == "table" then
			payload = data :: DialoguePayload
		else
			payload = legacyPayloadFromState(data)
		end

		applyPanelLayout(r.panel)
		applyPayload(r, payload)
		r.clickCatcher.Visible = true
		r.panel.Visible = true
	end)

	print("[Dialogue] Started.")
end

return M