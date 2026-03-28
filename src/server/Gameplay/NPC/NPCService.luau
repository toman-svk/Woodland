--!strict
-- src/server/Gameplay/NPC/NPCService.luau

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ServerScriptService = game:GetService("ServerScriptService")

local WorldService = require(
	ServerScriptService
		:WaitForChild("Server")
		:WaitForChild("Gameplay")
		:WaitForChild("World")
		:WaitForChild("Runtime")
		:WaitForChild("WorldService")
)

local npcFolder = script.Parent

local blacksmithFolder = npcFolder:WaitForChild("Blacksmith")
local baseFolder = npcFolder:WaitForChild("Base")

local blacksmithControllerModule = blacksmithFolder:WaitForChild("BlacksmithController")
if not blacksmithControllerModule:IsA("ModuleScript") then
	error("[NPCService] BlacksmithController is not a ModuleScript")
end

local blacksmithQuestModule = blacksmithFolder:WaitForChild("BlacksmithQuest")
if not blacksmithQuestModule:IsA("ModuleScript") then
	error("[NPCService] BlacksmithQuest is not a ModuleScript")
end

local baseUpgradeQuestModule = baseFolder:WaitForChild("BaseUpgradeQuest")
if not baseUpgradeQuestModule:IsA("ModuleScript") then
	error("[NPCService] BaseUpgradeQuest is not a ModuleScript")
end

type BlacksmithControllerType = {
	Start: (generated: Folder) -> (),
}

type QuestModuleType = {
	BuildPayload: (player: Player) -> any,
	HandleChoice: (player: Player, choice: string) -> any,
	ClearPlayer: (player: Player) -> (),
}

type QuestDefinition = {
	npcId: string,
	buildPayload: (player: Player) -> any,
	handleChoice: (player: Player, choice: string) -> any,
	clearPlayer: (player: Player) -> (),
}

local BlacksmithController: BlacksmithControllerType = require(blacksmithControllerModule)
local BlacksmithQuest: QuestModuleType = require(blacksmithQuestModule)
local BaseUpgradeQuest: QuestModuleType = require(baseUpgradeQuestModule)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = Shared:WaitForChild("Remotes")
local GetRemote = require(Remotes:WaitForChild("GetRemote"))

local OpenDialogue = GetRemote("OpenDialogue", "RemoteEvent") :: RemoteEvent
local DialogueChoice = GetRemote("DialogueChoice", "RemoteEvent") :: RemoteEvent

local NPCService = {}
local started = false

local QUESTS: {[string]: QuestDefinition} = {
	Blacksmith_WoodQuest = {
		npcId = "Blacksmith",
		buildPayload = function(player: Player)
			return BlacksmithQuest.BuildPayload(player)
		end,
		handleChoice = function(player: Player, choice: string)
			return BlacksmithQuest.HandleChoice(player, choice)
		end,
		clearPlayer = function(player: Player)
			BlacksmithQuest.ClearPlayer(player)
		end,
	},
	Base_Upgrade_Lv1 = {
		npcId = "Base",
		buildPayload = function(player: Player)
			return BaseUpgradeQuest.BuildPayload(player)
		end,
		handleChoice = function(player: Player, choice: string)
			return BaseUpgradeQuest.HandleChoice(player, choice)
		end,
		clearPlayer = function(player: Player)
			BaseUpgradeQuest.ClearPlayer(player)
		end,
	},
}

local function getGeneratedFolder(): Folder?
	local getWorldId = WorldService.GetWorldId
	if not getWorldId then
		return nil
	end

	local worldId = getWorldId()
	if not worldId then
		return nil
	end

	local worldsFolder = Workspace:FindFirstChild("Worlds")
	if not (worldsFolder and worldsFolder:IsA("Folder")) then
		return nil
	end

	local worldRoot = worldsFolder:FindFirstChild(worldId)
	if not (worldRoot and worldRoot:IsA("Folder")) then
		return nil
	end

	local generated = worldRoot:FindFirstChild("Generated")
	if generated and generated:IsA("Folder") then
		return generated
	end

	return nil
end

local function getPromptDialogueId(prompt: ProximityPrompt): string?
	local value = prompt:GetAttribute("DialogueId")
	if type(value) == "string" and value ~= "" then
		return value
	end
	return nil
end

local function getPromptNpcId(prompt: ProximityPrompt): string?
	local value = prompt:GetAttribute("NpcId")
	if type(value) == "string" and value ~= "" then
		return value
	end
	return nil
end

local function getLegacyPromptIds(prompt: ProximityPrompt): (string?, string?)
	local model = prompt:FindFirstAncestorOfClass("Model")
	if not model then
		return nil, nil
	end

	if model.Name == "Blacksmith" then
		return "Blacksmith", "Blacksmith_WoodQuest"
	end

	return nil, nil
end

local function resolvePromptQuest(prompt: ProximityPrompt): (string?, string?)
	local npcId = getPromptNpcId(prompt)
	local dialogueId = getPromptDialogueId(prompt)

	if npcId and dialogueId then
		return npcId, dialogueId
	end

	local legacyNpcId, legacyDialogueId = getLegacyPromptIds(prompt)
	if legacyNpcId and legacyDialogueId then
		return legacyNpcId, legacyDialogueId
	end

	return nil, nil
end

local function bindPrompt(prompt: ProximityPrompt)
	if prompt:GetAttribute("QuestBound") == true then
		return
	end
	prompt:SetAttribute("QuestBound", true)

	prompt.Triggered:Connect(function(player: Player)
		local npcId, dialogueId = resolvePromptQuest(prompt)

		if not dialogueId or not npcId then
			warn("[NPCService] Prompt missing NpcId/DialogueId and no legacy fallback:", prompt:GetFullName())
			return
		end

		local questDef = QUESTS[dialogueId]
		if not questDef then
			warn("[NPCService] No quest definition for DialogueId:", dialogueId)
			return
		end

		if questDef.npcId ~= npcId then
			warn(
				("[NPCService] Prompt attribute mismatch. DialogueId=%s expectedNpcId=%s actualNpcId=%s")
					:format(dialogueId, questDef.npcId, npcId)
			)
			return
		end

		print(
			"[NPCService] Prompt triggered:",
			prompt:GetFullName(),
			"by",
			player.Name,
			"npcId=",
			npcId,
			"dialogueId=",
			dialogueId
		)

		local payload = questDef.buildPayload(player)
		OpenDialogue:FireClient(player, payload)
	end)
end

local function bindAllPromptsUnderGenerated(generated: Folder)
	for _, inst in ipairs(generated:GetDescendants()) do
		if inst:IsA("ProximityPrompt") then
			bindPrompt(inst)
		end
	end

	generated.DescendantAdded:Connect(function(inst)
		if inst:IsA("ProximityPrompt") then
			bindPrompt(inst)
		end
	end)
end

function NPCService.Start()
	if started then
		return
	end
	started = true

	task.defer(function()
		local generated: Folder? = nil

		for _ = 1, 100 do
			generated = getGeneratedFolder()
			if generated then
				break
			end
			task.wait(0.1)
		end

		if not generated then
			warn("[NPCService] Could not find Generated folder for current world.")
			return
		end

		bindAllPromptsUnderGenerated(generated)
		BlacksmithController.Start(generated)

		print("[NPCService] Bound prompts under", generated:GetFullName())
	end)

	DialogueChoice.OnServerEvent:Connect(function(player: Player, data: any)
		if type(data) ~= "table" then
			return
		end

		local npcId = data.npcId
		local dialogueId = data.dialogueId
		local choice = data.choice

		if type(npcId) ~= "string" then
			return
		end

		if type(dialogueId) ~= "string" then
			return
		end

		if type(choice) ~= "string" then
			return
		end

		local questDef = QUESTS[dialogueId]
		if not questDef then
			warn("[NPCService] DialogueChoice for unknown DialogueId:", dialogueId)
			return
		end

		if questDef.npcId ~= npcId then
			warn(
				("[NPCService] DialogueChoice npcId mismatch. DialogueId=%s expectedNpcId=%s actualNpcId=%s")
					:format(dialogueId, questDef.npcId, npcId)
			)
			return
		end

		local payload = questDef.handleChoice(player, choice)
		if payload ~= nil then
			OpenDialogue:FireClient(player, payload)
		end
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		for _, questDef in pairs(QUESTS) do
			questDef.clearPlayer(player)
		end
	end)
end

return NPCService