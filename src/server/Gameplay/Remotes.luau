-- creates Shared remotes used in gameplay--!strict
-- src/server/Gameplay/Remotes.luau
-- Server-side registry for RemoteEvents stored in ReplicatedStorage/Shared/Remotes

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = {}

local function ensureFolder(parent: Instance, name: string): Folder
	local f = parent:FindFirstChild(name)
	if f and f:IsA("Folder") then
		return f
	end
	local nf = Instance.new("Folder")
	nf.Name = name
	nf.Parent = parent
	return nf
end

local function ensureRemoteEvent(parent: Instance, name: string): RemoteEvent
	local inst = parent:FindFirstChild(name)
	if inst and inst:IsA("RemoteEvent") then
		return inst
	end
	local ev = Instance.new("RemoteEvent")
	ev.Name = name
	ev.Parent = parent
	return ev
end

local function ensureRemoteFunction(parent: Instance, name: string): RemoteFunction
	local inst = parent:FindFirstChild(name)
	if inst and inst:IsA("RemoteFunction") then
		return inst
	end
	local fn = Instance.new("RemoteFunction")
	fn.Name = name
	fn.Parent = parent
	return fn
end

-- Your structure:
-- ReplicatedStorage
--   Shared
--     Remotes
local shared = ensureFolder(ReplicatedStorage, "Shared")
local remotesFolder = ensureFolder(shared, "Remotes")

-- ✅ Put all remotes you want to standardize here:
Remotes.CastSpell = ensureRemoteEvent(remotesFolder, "CastSpell")
Remotes.OpenDialogue = ensureRemoteEvent(remotesFolder, "OpenDialogue")
Remotes.QuestComplete = ensureRemoteEvent(remotesFolder, "QuestComplete")

Remotes.CombatAttack = ensureRemoteEvent(remotesFolder, "CombatAttack")
Remotes.CombatHit = ensureRemoteEvent(remotesFolder, "CombatHit")

Remotes.PlaceBuilding = ensureRemoteEvent(remotesFolder, "PlaceBuilding")

Remotes.PickupFX = ensureRemoteEvent(remotesFolder, "PickupFX")
Remotes.SprintToggle = ensureRemoteEvent(remotesFolder, "SprintToggle")

-- RemoteFunction (outside /Remotes in your current structure)
Remotes.GameConfig = ensureRemoteFunction(shared, "GameConfig")

return Remotes