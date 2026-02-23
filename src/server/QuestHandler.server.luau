-- ServerScriptService/Server/QuestHandler.server.lua
--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = Shared:WaitForChild("Remotes")
local OpenDialogue = Remotes:WaitForChild("OpenDialogue")

local REQUIRED_WOOD = 10

-- Track per-player completion (in-memory; later you can persist via DataStore)
local questDone: {[Player]: boolean} = {}

local function getNumberValue(container: Instance?, name: string): NumberValue?
	if not container then
		return nil
	end

	local v = container:FindFirstChild(name)
	if v and v:IsA("NumberValue") then
		return v
	end

	return nil
end

local function getWoodValue(player: Player): NumberValue?
	-- Primary source in your project: Inventory folder
	local inv = player:FindFirstChild("Inventory")
	local wood = getNumberValue(inv, "Wood")
	if wood then
		return wood
	end

	-- Optional fallbacks (won't hurt if you later change structure)
	local leaderstats = player:FindFirstChild("leaderstats")
	wood = getNumberValue(leaderstats, "Wood")
	if wood then
		return wood
	end

	local stats = player:FindFirstChild("Stats")
	wood = getNumberValue(stats, "Wood")
	if wood then
		return wood
	end

	return nil
end

local function bindPrompt(prompt: ProximityPrompt)
	-- Avoid double-binding (important with regenerating folders / live edit)
	if prompt:GetAttribute("QuestBound") then
		return
	end
	prompt:SetAttribute("QuestBound", true)

	prompt.Triggered:Connect(function(player: Player)
		print("[QuestHandler] Prompt triggered:", prompt:GetFullName(), "by", player.Name)

		local wood = getWoodValue(player)
		if not wood then
			warn("[QuestHandler] No Inventory/leaderstats/Stats Wood value found for", player.Name)
			OpenDialogue:FireClient(player, "NoWoodStat")
			return
		end

		if questDone[player] then
			OpenDialogue:FireClient(player, "AlreadyDone")
			return
		end

		if wood.Value >= REQUIRED_WOOD then
			wood.Value -= REQUIRED_WOOD
			questDone[player] = true

			-- Later: give BetterAxe here
			OpenDialogue:FireClient(player, "QuestComplete")
		else
			OpenDialogue:FireClient(player, "QuestNotDone")
		end
	end)
end

local function bindAllPromptsUnderGenerated()
	local generated = workspace:WaitForChild("Generated")

	-- Bind existing prompts
	for _, inst in ipairs(generated:GetDescendants()) do
		if inst:IsA("ProximityPrompt") then
			bindPrompt(inst)
		end
	end

	-- Bind prompts added later (important if you rebuild Generated)
	generated.DescendantAdded:Connect(function(inst)
		if inst:IsA("ProximityPrompt") then
			bindPrompt(inst)
		end
	end)
end

Players.PlayerRemoving:Connect(function(player: Player)
	questDone[player] = nil
end)

bindAllPromptsUnderGenerated()
print("[QuestHandler] Bound prompts under workspace.Generated")