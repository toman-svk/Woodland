--!strict
-- src/server/Spells.server.luau

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = Shared:WaitForChild("Remotes")
local CastSpell = Remotes:WaitForChild("CastSpell") :: RemoteEvent

-- ===== Tuning =====
local COOLDOWN = 1.0
local RANGE = 12
local DAMAGE = 10

local lastCast: {[Player]: number} = {}

local function getCharHumRoot(player: Player): (Model?, Humanoid?, BasePart?)
	local character = player.Character
	if not character then return nil, nil, nil end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return character, nil, nil end

	local root = character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return character, humanoid, nil
	end

	return character, humanoid, root
end

local function isAlive(h: Humanoid?): boolean
	return h ~= nil and h.Health > 0
end

local function canCast(player: Player): boolean
	local now = os.clock()
	local t = lastCast[player]
	if t and (now - t) < COOLDOWN then
		return false
	end
	lastCast[player] = now
	return true
end

local function raycastForward(character: Model, root: BasePart): RaycastResult?
	local origin = root.Position + Vector3.new(0, 1.5, 0)
	local direction = root.CFrame.LookVector * RANGE

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }

	return workspace:Raycast(origin, direction, params)
end

local function tryDamageFromResult(caster: Player, result: RaycastResult)
	local hit = result.Instance
	if not hit then return end

	local model = hit:FindFirstAncestorOfClass("Model")
	if not model then return end

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end

	-- Prevent self-damage
	local casterChar = caster.Character
	if casterChar and model == casterChar then
		return
	end

	-- Basic damage
	humanoid:TakeDamage(DAMAGE)
end

CastSpell.OnServerEvent:Connect(function(player: Player, payload: any)
	-- Validate payload shape (light)
	if typeof(payload) ~= "table" then
		return
	end

	if not canCast(player) then
		return
	end

	local character, humanoid, root = getCharHumRoot(player)
	if not character or not isAlive(humanoid) or not root then
		return
	end

	-- For now we ignore spellId; later you can branch per spell
	local result = raycastForward(character, root)
	if not result then
		return
	end

	tryDamageFromResult(player, result)
end)

Players.PlayerRemoving:Connect(function(plr)
	lastCast[plr] = nil
end)