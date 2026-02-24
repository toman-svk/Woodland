-- ServerScriptService/Server/QuestHandler.server.lua
--!strict

--testcomment

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = Shared:WaitForChild("Remotes")
local OpenDialogue = Remotes:WaitForChild("OpenDialogue")

local REQUIRED_WOOD = 10

type NumericValue = IntValue | NumberValue

-- Track per-player completion (in-memory; later you can persist via DataStore)
local questDone: {[Player]: boolean} = {}

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
	-- Primary source in your project: Inventory folder
	local inv = player:FindFirstChild("Inventory")
	local wood = getNumericValue(inv, "Wood")
	if wood then
		return wood
	end

	-- Optional fallbacks (won't hurt if you later change structure)
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

local function bindPrompt(prompt: ProximityPrompt)
	-- Avoid double-binding (important with regenerating folders / live edit)
	if prompt:GetAttribute("QuestBound") then
		return
	end
	prompt:SetAttribute("QuestBound", true)

	prompt.Triggered:Connect(function(player: Player)
		print("[QuestHandler] Prompt triggered:", prompt:GetFullName(), "by", player.Name)

		local inv = player:FindFirstChild("Inventory")
		if inv then
			local w = inv:FindFirstChild("Wood")
			if w then
				print("[QuestHandler] Inventory.Wood class:", w.ClassName, "value:", (w :: any).Value)
			else
				print("[QuestHandler] Inventory exists but Wood missing")
			end
		else
			print("[QuestHandler] Inventory missing on player")
		end

		local wood = getWoodValue(player)
		if not wood then
			warn("[QuestHandler] No Inventory/leaderstats/Stats numeric Wood value found for", player.Name)
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

			-- TODO: give BetterAxe here (optional)
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