--!strict
-- src/server/Gameplay/NPC/Blacksmith/BlacksmithQuest.luau

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = Shared:WaitForChild("Remotes")
local GetRemote = require(Remotes:WaitForChild("GetRemote"))

local questCompleteRemote = GetRemote("QuestComplete", "RemoteEvent") :: RemoteEvent

local BlacksmithQuest = {}

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

export type DialogueContext = {
	npcId: string?,
	dialogueId: string?,
}

export type DialoguePayload = {
	title: string?,
	body: string?,
	requirement: DialogueRow?,
	reward: DialogueRow?,
	actions: DialogueActions?,
	context: DialogueContext?,
}

local WOOD_ICON = "rbxassetid://85144837910297"
local BETTER_AXE_ICON = "rbxassetid://88097304181361"
local REQUIRED_WOOD = 10

type NumericValue = IntValue | NumberValue

local questAccepted: {[Player]: boolean} = {}
local questCompleted: {[Player]: boolean} = {}

local function displayName(player: Player): string
	return (player.DisplayName ~= "" and player.DisplayName) or player.Name
end

local function getNumericValue(container: Instance?, name: string): NumericValue?
	if not container then
		return nil
	end

	local v = container:FindFirstChild(name)
	if v and (v:IsA("IntValue") or v:IsA("NumberValue")) then
		return v :: NumericValue
	end

	return nil
end

local function getWoodValue(player: Player): NumericValue?
	local inv = player:FindFirstChild("Inventory")
	local wood = getNumericValue(inv, "Wood")
	if wood then
		return wood
	end

	local leaderstats = player:FindFirstChild("leaderstats")
	wood = getNumericValue(leaderstats, "Wood")
	if wood then
		return wood
	end

	local stats = player:FindFirstChild("Stats")
	wood = getNumericValue(stats, "Wood")
	if wood then
		return wood
	end

	return nil
end

local function baseContext(): DialogueContext
	return {
		npcId = "Blacksmith",
		dialogueId = "Blacksmith_WoodQuest",
	}
end

local function payload(data: DialoguePayload): DialoguePayload
	return {
		title = data.title,
		body = data.body,
		requirement = data.requirement,
		reward = data.reward,
		actions = data.actions,
		context = data.context or baseContext(),
	}
end

function BlacksmithQuest.BuildPayload(player: Player): DialoguePayload
	local name = displayName(player)

	if questCompleted[player] then
		return payload({
			title = "John — Blacksmith",
			body =
				("Good to see you again, %s!\n\n"):format(name)
				.. "Your improved axe should serve you well. If you need more upgrades later, come back with materials.",
			reward = {
				icon = BETTER_AXE_ICON,
				text = "Reward already claimed",
			},
			actions = {
				showAccept = false,
				showDecline = false,
			},
		})
	end

	if not questAccepted[player] then
		return payload({
			title = "John — Blacksmith",
			body =
				("Welcome to Woodland, %s!\n\n"):format(name)
				.. "I’m John, the local blacksmith. My forge is running cold and I need wood to keep the furnace alive.\n"
				.. "Bring me enough and I’ll reinforce your axe so it bites deeper into the trees.\n\n"
				.. "Will you help me?",
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
		})
	end

	local wood = getWoodValue(player)
	if not wood then
		return payload({
			title = "John — Blacksmith",
			body =
				("Hmm… %s, I can’t see your wood count yet.\n\n"):format(name)
				.. "Try chopping a tree first — then come back and we’ll talk upgrades.",
			reward = {
				icon = BETTER_AXE_ICON,
				text = "Reward: Better Axe",
			},
			actions = {
				showAccept = false,
				showDecline = false,
			},
		})
	end

	if wood.Value >= REQUIRED_WOOD then
		return payload({
			title = "John — Blacksmith",
			body =
				("Excellent work, %s!\n\n"):format(name)
				.. "You brought enough wood to keep the furnace roaring.\n"
				.. "I can forge your improved axe now.",
			requirement = {
				icon = WOOD_ICON,
				text = ("Deliver: %d Wood"):format(REQUIRED_WOOD),
			},
			reward = {
				icon = BETTER_AXE_ICON,
				text = "Reward: Better Axe",
			},
			actions = {
				showAccept = true,
				showDecline = true,
				acceptText = "Deliver",
				declineText = "Later",
			},
		})
	end

	return payload({
		title = "John — Blacksmith",
		body =
			("Welcome back, %s.\n\n"):format(name)
			.. ("You still need %d more wood before I can improve your axe."):format(REQUIRED_WOOD - wood.Value),
		requirement = {
			icon = WOOD_ICON,
			text = ("Need: %d / %d Wood"):format(wood.Value, REQUIRED_WOOD),
		},
		reward = {
			icon = BETTER_AXE_ICON,
			text = "Reward: Better Axe",
		},
		actions = {
			showAccept = false,
			showDecline = true,
			declineText = "Close",
		},
	})
end

function BlacksmithQuest.HandleChoice(player: Player, choice: string): DialoguePayload?
	if questCompleted[player] then
		return payload({
			title = "John — Blacksmith",
			body = "You already completed my request.",
			actions = {
				showAccept = false,
				showDecline = false,
			},
		})
	end

	if choice == "Decline" then
		-- close only, no extra dialogue
		return nil
	end

	if choice ~= "Accept" then
		return nil
	end

	-- First-time quest acceptance:
	-- mark as accepted, play blue glow, close dialogue
	if not questAccepted[player] then
		questAccepted[player] = true

        print("[BlacksmithQuest] Fire accepted FX to", player.Name)
        questCompleteRemote:FireClient(player, {
            effect = "BlacksmithQuestAccepted",
        })


		return nil
	end

	local wood = getWoodValue(player)
	if not wood then
		return payload({
			title = "John — Blacksmith",
			body = "I still can't detect your wood count. Try again in a moment.",
			actions = {
				showAccept = false,
				showDecline = false,
			},
		})
	end

	if wood.Value < REQUIRED_WOOD then
		return payload({
			title = "John — Blacksmith",
			body = ("You still need %d more wood."):format(REQUIRED_WOOD - wood.Value),
			requirement = {
				icon = WOOD_ICON,
				text = ("Need: %d / %d Wood"):format(wood.Value, REQUIRED_WOOD),
			},
			reward = {
				icon = BETTER_AXE_ICON,
				text = "Reward: Better Axe",
			},
			actions = {
				showAccept = false,
				showDecline = false,
			},
		})
	end

	-- Delivery / completion:
	-- consume wood, mark complete, play green glow, close dialogue
	wood.Value -= REQUIRED_WOOD
	questCompleted[player] = true

    print("[BlacksmithQuest] Fire complete FX to", player.Name)
    questCompleteRemote:FireClient(player, {
        effect = "BlacksmithQuestComplete",
    })
	-- TODO: grant improved axe here later

	return nil
end

function BlacksmithQuest.ClearPlayer(player: Player)
	questAccepted[player] = nil
	questCompleted[player] = nil
end

return BlacksmithQuest