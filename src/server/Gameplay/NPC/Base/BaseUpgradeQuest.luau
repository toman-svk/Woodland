--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = Shared:WaitForChild("Remotes")
local GetRemote = require(Remotes:WaitForChild("GetRemote"))

local questCompleteRemote    = GetRemote("QuestComplete",    "RemoteEvent") :: RemoteEvent
local showNotificationRemote = GetRemote("ShowNotification", "RemoteEvent") :: RemoteEvent

local BaseUpgradeService = require(
	ServerScriptService
		:WaitForChild("Server")
		:WaitForChild("Gameplay")
		:WaitForChild("Systems")
		:WaitForChild("BaseUpgradeService")
)

type DialogueContext = {
	npcId: string,
	dialogueId: string,
}

type DialogueActions = {
	showAccept: boolean,
	showDecline: boolean,
	acceptText: string?,
	declineText: string?,
}

type DialogueLine = {
	icon: string,
	text: string,
}

type DialoguePayload = {
	context: DialogueContext,
	title: string,
	body: string,
	requirement: DialogueLine?,
	reward: DialogueLine?,
	actions: DialogueActions,
}

export type BaseUpgradeQuestType = {
	BuildPayload: (player: Player) -> DialoguePayload,
	HandleChoice: (player: Player, choice: string) -> DialoguePayload?,
	ClearPlayer: (player: Player) -> (),
}

local REQUIRED_WOOD = 0
local BUILD_DURATION_SECONDS = 10

local WOOD_ICON = "rbxassetid://85144837910297"
local BASE_ICON = "rbxassetid://0"

local acceptedByPlayer: {[Player]: boolean} = {}

local function getWoodValue(player: Player): IntValue?
	local inv = player:FindFirstChild("Inventory")
	if not (inv and inv:IsA("Folder")) then
		return nil
	end

	local wood = inv:FindFirstChild("Wood")
	if wood and wood:IsA("IntValue") then
		return wood
	end

	return nil
end

local function formatRemaining(secondsLeft: number): string
	local safe = math.max(0, secondsLeft)
	local minutes = math.floor(safe / 60)
	local seconds = safe % 60
	return string.format("%d:%02d", minutes, seconds)
end

local function makePayload(data: {
	title: string,
	body: string,
	requirement: DialogueLine?,
	reward: DialogueLine?,
	actions: DialogueActions,
}): DialoguePayload
	return {
		context = {
			npcId = "Base",
			dialogueId = "Base_Upgrade_Lv1",
		},
		title = data.title,
		body = data.body,
		requirement = data.requirement,
		reward = data.reward,
		actions = data.actions,
	}
end

local function BuildPayload(player: Player): DialoguePayload
	local currentLevel = BaseUpgradeService.GetLevel()

	if BaseUpgradeService.IsUpgradeInProgress() then
		local endTime = BaseUpgradeService.GetUpgradeEndTime()
		local secondsLeft = if type(endTime) == "number" then math.max(0, endTime - os.time()) else 0

		return makePayload({
			title = "Village Base",
			body = ("Construction in progress.\nTime remaining: %s"):format(formatRemaining(secondsLeft)),
			requirement = nil,
			reward = {
				icon = BASE_ICON,
				text = "Upgrade in progress",
			},
			actions = {
				showAccept = false,
				showDecline = true,
				acceptText = nil,
				declineText = "Close",
			},
		})
	end

	if currentLevel >= 2 then
		return makePayload({
			title = "Village Base",
			body = "The base is already upgraded.",
			requirement = nil,
			reward = {
				icon = BASE_ICON,
				text = "Current level: 2",
			},
			actions = {
				showAccept = false,
				showDecline = true,
				acceptText = nil,
				declineText = "Close",
			},
		})
	end

	if not acceptedByPlayer[player] then
		return makePayload({
			title = "Village Base",
			body = "Bring 50 Wood and we will reinforce the house and improve the village base.\nConstruction will take 1 minute.",
			requirement = {
				icon = WOOD_ICON,
				text = "Need: 50 Wood",
			},
			reward = {
				icon = BASE_ICON,
				text = "Reward: Upgraded House + Fence",
			},
			actions = {
				showAccept = true,
				showDecline = true,
				acceptText = "Accept",
				declineText = "Later",
			},
		})
	end

	local wood = getWoodValue(player)
	local currentWood = if wood then wood.Value else 0

	if currentWood >= REQUIRED_WOOD then
		return makePayload({
			title = "Village Base",
			body = "You brought enough wood. Deliver it and construction will begin.",
			requirement = {
				icon = WOOD_ICON,
				text = "Deliver: 50 Wood",
			},
			reward = {
				icon = BASE_ICON,
				text = "Reward: Upgraded House + Fence",
			},
			actions = {
				showAccept = true,
				showDecline = true,
				acceptText = "Deliver",
				declineText = "Later",
			},
		})
	end

	return makePayload({
		title = "Village Base",
		body = ("We still need %d more wood to reinforce the house."):format(REQUIRED_WOOD - currentWood),
		requirement = {
			icon = WOOD_ICON,
			text = ("Need: %d / %d Wood"):format(currentWood, REQUIRED_WOOD),
		},
		reward = {
			icon = BASE_ICON,
			text = "Reward: Upgraded House + Fence",
		},
		actions = {
			showAccept = false,
			showDecline = true,
			acceptText = nil,
			declineText = "Close",
		},
	})
end

local function HandleChoice(player: Player, choice: string): DialoguePayload?
	if choice == "Decline" then
		return nil
	end

	if choice ~= "Accept" then
		return nil
	end

	if BaseUpgradeService.IsUpgradeInProgress() then
		return BuildPayload(player)
	end

	if BaseUpgradeService.GetLevel() >= 2 then
		return nil
	end

	if not acceptedByPlayer[player] then
		acceptedByPlayer[player] = true

		questCompleteRemote:FireClient(player, {
			effect = "QuestAccepted",
		})

		return nil
	end

	local wood = getWoodValue(player)
	if not wood or wood.Value < REQUIRED_WOOD then
		return BuildPayload(player)
	end

	wood.Value -= REQUIRED_WOOD

	-- Block the upgrade if trees are still standing inside / on the fence line.
	local blockingTrees = BaseUpgradeService.GetFenceBlockingTreeCount()
	if blockingTrees > 0 then
		showNotificationRemote:FireClient(player, {
			message  = ("Chop down the %d tree(s) inside the base area before upgrading!"):format(blockingTrees),
			duration = 5,
		})
		return nil
	end

	local ok = BaseUpgradeService.StartTimedUpgrade(2, BUILD_DURATION_SECONDS)
	if ok then
		questCompleteRemote:FireClient(player, {
			effect = "QuestStarted",
		})
	end

	return nil
end

local function ClearPlayer(player: Player)
	acceptedByPlayer[player] = nil
end

local BaseUpgradeQuest: BaseUpgradeQuestType = {
	BuildPayload = BuildPayload,
	HandleChoice = HandleChoice,
	ClearPlayer = ClearPlayer,
}

return BaseUpgradeQuest