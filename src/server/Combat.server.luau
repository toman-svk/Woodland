-- ServerScriptService/Combat.server.lua

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local attackEvent = Shared:WaitForChild("CombatAttack")
local hitEvent = Shared:WaitForChild("CombatHit")

-- TUNING
local ATTACK_COOLDOWN = 0.5
local ATTACK_RANGE = 6
local ATTACK_ARC_DOT = 0.25 -- cone in front
local DAMAGE = 15
local MANA_COST = 12

local lastAttackTime = {} -- [player] = time

local function getStats(player)
	local stats = player:FindFirstChild("Stats")
	if not stats then return nil end
	local mana = stats:FindFirstChild("Mana")
	local maxMana = stats:FindFirstChild("MaxMana")
	if not (mana and maxMana) then return nil end
	return mana, maxMana
end

local function getCharacterParts(player)
	local char = player.Character
	if not char then return nil end
	local root = char:FindFirstChild("HumanoidRootPart")
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not (root and hum) then return nil end
	return char, root, hum
end

local function findTarget(player, root)
	local origin = root.Position
	local forward = root.CFrame.LookVector

	local bestModel: Model? = nil
	local bestHum: Humanoid? = nil
	local bestDist = math.huge

	for _, model in ipairs(workspace:GetChildren()) do
		if model:IsA("Model") and model ~= player.Character then
			local hum = model:FindFirstChildOfClass("Humanoid")
			local hrp = model:FindFirstChild("HumanoidRootPart")
			if hum and hrp and hum.Health > 0 then
				local delta = hrp.Position - origin
				local dist = delta.Magnitude
				if dist <= ATTACK_RANGE and dist < bestDist then
					local dir = delta.Unit
					local dot = forward:Dot(dir)
					if dot >= ATTACK_ARC_DOT then
						bestModel = model
						bestHum = hum
						bestDist = dist
					end
				end
			end
		end
	end

	return bestModel, bestHum
end

attackEvent.OnServerEvent:Connect(function(player)
	local now = os.clock()
	if now - (lastAttackTime[player] or 0) < ATTACK_COOLDOWN then
		return
	end
	lastAttackTime[player] = now

	local mana, maxMana = getStats(player)
	if not mana then return end
	if not mana then return end
	mana = mana

	local char, root, hum = getCharacterParts(player)
	if not char or hum.Health <= 0 then return end

	if mana.Value < MANA_COST then
		return
	end

	local targetModel, targetHum = findTarget(player, root)
	if not targetModel or not targetHum then
		return
	end

	-- Apply mana cost + damage
	mana.Value = math.max(0, mana.Value - MANA_COST)
	targetHum:TakeDamage(DAMAGE)

	-- Broadcast to all clients so everyone sees damage numbers
	hitEvent:FireAllClients(targetModel, DAMAGE)
end)

Players.PlayerRemoving:Connect(function(player)
	lastAttackTime[player] = nil
end)
