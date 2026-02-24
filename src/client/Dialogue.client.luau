-- src/client/Dialogue.client.luau
--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = Shared:WaitForChild("Remotes")
local openDialogue = Remotes:WaitForChild("OpenDialogue")

local player = Players.LocalPlayer

-- Assets
local WOOD_ICON = "rbxassetid://85144837910297"
local BETTER_AXE_ICON = "rbxassetid://88097304181361"
local REQUIRED_WOOD = 10

-- ========= UI ROOT =========
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "DialogueGui"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = false
screenGui.DisplayOrder = 300
screenGui.Parent = player:WaitForChild("PlayerGui")

-- Invisible click-catcher (NO grey overlay)
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

-- Main panel
local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.Parent = screenGui
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.BackgroundTransparency = 1
panel.Visible = false
panel.ZIndex = 10

-- ========= PANEL BODY =========
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

local grad = Instance.new("UIGradient")
grad.Rotation = 90
grad.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0.0, Color3.fromRGB(238, 228, 198)),
	ColorSequenceKeypoint.new(0.55, Color3.fromRGB(214, 198, 158)),
	ColorSequenceKeypoint.new(1.0, Color3.fromRGB(194, 173, 133)),
})
grad.Parent = bodyFrame

-- Slight “paper variation”
local paperShade = Instance.new("Frame")
paperShade.Parent = bodyFrame
paperShade.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
paperShade.BackgroundTransparency = 0.97
paperShade.BorderSizePixel = 0
paperShade.Size = UDim2.new(1, 0, 1, 0)
paperShade.ZIndex = 12

local paperGrad = Instance.new("UIGradient")
paperGrad.Rotation = 25
paperGrad.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0.0, 0.94),
	NumberSequenceKeypoint.new(0.5, 0.985),
	NumberSequenceKeypoint.new(1.0, 0.93),
})
paperGrad.Parent = paperShade

-- Outer stroke
local stroke = Instance.new("UIStroke")
stroke.Thickness = 2
stroke.Color = Color3.fromRGB(70, 58, 38)
stroke.Transparency = 0.20
stroke.Parent = bodyFrame

-- Inner border
local INNER_INSET = 6

local inner = Instance.new("Frame")
inner.Name = "InnerBorder"
inner.Parent = bodyFrame
inner.BackgroundTransparency = 1
inner.BorderSizePixel = 0
inner.Position = UDim2.fromOffset(INNER_INSET, INNER_INSET)
inner.Size = UDim2.new(1, -2 * INNER_INSET, 1, -2 * INNER_INSET)
inner.ZIndex = 13

local innerStroke = Instance.new("UIStroke")
innerStroke.Thickness = 1
innerStroke.Color = Color3.fromRGB(95, 77, 47)
innerStroke.Transparency = 0.55
innerStroke.Parent = inner

local innerCorner = Instance.new("UICorner")
innerCorner.CornerRadius = UDim.new(0, 14)
innerCorner.Parent = inner

-- Wooden trims (decor only)
local TRIM_W = 12
local TRIM_MARGIN = 6

local function makeWoodTrim(side: "Left" | "Right"): Frame
	local trim = Instance.new("Frame")
	trim.Name = side .. "Trim"
	trim.Parent = bodyFrame
	trim.BorderSizePixel = 0
	trim.BackgroundColor3 = Color3.fromRGB(86, 60, 33)
	trim.BackgroundTransparency = 0.25
	trim.ZIndex = 14

	if side == "Left" then
		trim.Position = UDim2.fromOffset(TRIM_MARGIN, TRIM_MARGIN)
		trim.Size = UDim2.new(0, TRIM_W, 1, -2 * TRIM_MARGIN)
	else
		trim.Position = UDim2.new(1, -TRIM_MARGIN - TRIM_W, 0, TRIM_MARGIN)
		trim.Size = UDim2.new(0, TRIM_W, 1, -2 * TRIM_MARGIN)
	end

	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 10)
	c.Parent = trim

	local g = Instance.new("UIGradient")
	g.Rotation = (side == "Left") and 0 or 180
	g.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0.0, Color3.fromRGB(112, 80, 44)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(86, 60, 33)),
		ColorSequenceKeypoint.new(1.0, Color3.fromRGB(62, 43, 24)),
	})
	g.Parent = trim

	local s = Instance.new("UIStroke")
	s.Thickness = 1
	s.Color = Color3.fromRGB(30, 20, 10)
	s.Transparency = 0.70
	s.Parent = trim

	return trim
end

makeWoodTrim("Left")
makeWoodTrim("Right")

-- ========= CONTENT CONTAINER (THIS is what we pad) =========
local content = Instance.new("Frame")
content.Name = "Content"
content.Parent = bodyFrame
content.BackgroundTransparency = 1
content.BorderSizePixel = 0
content.Position = UDim2.fromOffset(0, 0)
content.Size = UDim2.new(1, 0, 1, 0)
content.ZIndex = 20

-- ✅ BIGGER padding so content never touches strokes/trims
-- Must be > TRIM_MARGIN + TRIM_W (+ buffer)
local SIDE_PAD = 44
local TOP_PAD = 26
local BOTTOM_PAD = 22

local contentPadding = Instance.new("UIPadding")
contentPadding.Parent = content
contentPadding.PaddingTop = UDim.new(0, TOP_PAD)
contentPadding.PaddingBottom = UDim.new(0, BOTTOM_PAD)
contentPadding.PaddingLeft = UDim.new(0, SIDE_PAD)
contentPadding.PaddingRight = UDim.new(0, SIDE_PAD)

-- ========= HEADER =========
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

-- ========= BODY TEXT =========
local bodyText = Instance.new("TextLabel")
bodyText.Parent = content
bodyText.BackgroundTransparency = 1
bodyText.Position = UDim2.fromOffset(0, 52)
bodyText.Size = UDim2.new(1, 0, 1, -52 - 118)
bodyText.TextWrapped = true
bodyText.TextXAlignment = Enum.TextXAlignment.Left
bodyText.TextYAlignment = Enum.TextYAlignment.Top
bodyText.Font = Enum.Font.GothamMedium
bodyText.TextSize = 22
bodyText.TextColor3 = Color3.fromRGB(35, 28, 18)
bodyText.Text = ""
bodyText.ZIndex = 21

-- ========= FOOTER =========
local footer = Instance.new("Frame")
footer.Parent = content
footer.BackgroundTransparency = 1
footer.AnchorPoint = Vector2.new(0, 1)
footer.Position = UDim2.new(0, 0, 1, 0)
footer.Size = UDim2.new(1, 0, 0, 104)
footer.ZIndex = 21

local footerLayout = Instance.new("UIListLayout")
footerLayout.Parent = footer
footerLayout.FillDirection = Enum.FillDirection.Vertical
footerLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
footerLayout.VerticalAlignment = Enum.VerticalAlignment.Top
footerLayout.Padding = UDim.new(0, 10)
footerLayout.SortOrder = Enum.SortOrder.LayoutOrder

local function makeRow(iconId: string, text: string): Frame
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
	icon.Image = iconId
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
	txt.Text = text
	txt.ZIndex = 22

	return row
end

local reqRow = makeRow(WOOD_ICON, ("Need: %d Wood"):format(REQUIRED_WOOD))
reqRow.LayoutOrder = 1
reqRow.Parent = footer

local rewardRow = makeRow(BETTER_AXE_ICON, "Reward: Better Axe")
rewardRow.LayoutOrder = 2
rewardRow.Parent = footer

-- ========= RESPONSIVE LAYOUT =========
local function applyPanelLayout()
	local cam = workspace.CurrentCamera
	if not cam then return end
	local vp = cam.ViewportSize

	local insetTopLeft, insetBottomRight = GuiService:GetGuiInset()
	local topSafe = insetTopLeft.Y + 24
	local bottomSafe = insetBottomRight.Y + 160

	local availableH = math.max(240, math.floor(vp.Y - topSafe - bottomSafe))

	local w = math.clamp(math.floor(vp.X * 0.66), 520, 860)

	local targetRatio = 1.10 -- width/height
	local idealH = math.floor(w / targetRatio)
	local h = math.min(idealH, availableH)
	h = math.max(h, 420)

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

-- ========= Dialogue logic =========
local function displayName(): string
	return (player.DisplayName ~= "" and player.DisplayName) or player.Name
end

local function setDialogue(state: any)
	reqRow.Visible = true
	rewardRow.Visible = true

	local msg: string
	if state == "QuestNotDone" then
		msg =
			("Welcome to Woodland, %s!\n\n"):format(displayName())
			.. "I’m John, the local blacksmith. My forge is running cold and I need wood to keep the furnace alive.\n"
			.. "Bring me enough and I’ll reinforce your axe so it bites deeper into the trees."
	elseif state == "QuestComplete" then
		msg =
			("Excellent work, %s!\n\n"):format(displayName())
			.. "That wood will keep the furnace roaring. Here — take this improved axe.\n"
			.. "It’s balanced better and should make chopping feel much faster."
		reqRow.Visible = false
	elseif state == "AlreadyDone" then
		msg =
			("Good to see you again, %s!\n\n"):format(displayName())
			.. "Your improved axe should serve you well. If you need more upgrades later, come back with materials."
		reqRow.Visible = false
	elseif state == "NoWoodStat" then
		msg =
			("Hmm… %s, I can’t see your wood count yet.\n\n"):format(displayName())
			.. "Try chopping a tree first — then come back and we’ll talk upgrades."
		reqRow.Visible = false
		rewardRow.Visible = false
	else
		msg = ("[Unknown state: %s]"):format(tostring(state))
		reqRow.Visible = false
		rewardRow.Visible = false
	end

	bodyText.Text = msg
end

local function hide()
	panel.Visible = false
	clickCatcher.Visible = false
end

closeBtn.MouseButton1Click:Connect(hide)
clickCatcher.MouseButton1Click:Connect(hide)

UserInputService.InputBegan:Connect(function(input, gp)
	if gp then return end
	if not panel.Visible then return end
	if input.KeyCode == Enum.KeyCode.Escape then
		hide()
	end
end)

local function bindViewportResize()
	local cam = workspace.CurrentCamera
	if not cam then return end
	cam:GetPropertyChangedSignal("ViewportSize"):Connect(function()
		if panel.Visible then
			applyPanelLayout()
		end
	end)
end
bindViewportResize()
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bindViewportResize)

openDialogue.OnClientEvent:Connect(function(state)
	print("[Dialogue] state=", state)
	applyPanelLayout()
	clickCatcher.Visible = true
	panel.Visible = true
	setDialogue(state)
end)