--!strict
-- src/server/Gameplay/Systems/CombatService/init.luau

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local WorldService = require(
	ServerScriptService:WaitForChild("Server")
		:WaitForChild("Gameplay")
		:WaitForChild("World")
		:WaitForChild("Runtime")
		:WaitForChild("WorldService")
)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = Shared:WaitForChild("Remotes")

local CombatAttack = Remotes:WaitForChild("CombatAttack") :: RemoteEvent
local CombatHit = Remotes:WaitForChild("CombatHit") :: RemoteEvent

local ObjectWiggle = require(
	ServerScriptService:WaitForChild("Server")
		:WaitForChild("Gameplay")
		:WaitForChild("Systems")
		:WaitForChild("ObjectWiggle")
)

local CombatService = {}

local started = false
local attackCooldowns: {[Player]: number} = {}

local ATTACK_COOLDOWN = 0.45
local DEFAULT_RANGE = 7

-- Damage dealt per weapon type.
-- Damage is resolved SERVER-SIDE so clients cannot spoof it.
-- Key = exact tool name; value = damage amount.
local TOOL_DAMAGE: { [string]: number } = {
	Sword    = 10,
	Axe      = 7,
	Pickaxe  = 7,
	Hammer   = 7,
	Torch    = 7,
}
local UNARMED_DAMAGE = 5  -- bare-hand damage when no tool is equipped

-- Sound played on the skeleton when it is hit.
-- Because this Sound is created and played SERVER-SIDE on a part inside
-- the skeleton model, Roblox automatically replicates the playback to
-- all nearby clients as positional 3D audio — no extra remotes needed.
local HIT_SOUND_ID = "rbxassetid://123129904315504"

local function getCharacterRoot(model: Model): BasePart?
	local hrp = model:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:IsA("BasePart") then
		return hrp
	end
	return nil
end

local function getHumanoid(model: Model): Humanoid?
	return model:FindFirstChildOfClass("Humanoid")
end

local function getEquippedTool(player: Player): Tool?
	local char = player.Character
	if not char then
		return nil
	end

	for _, child in ipairs(char:GetChildren()) do
		if child:IsA("Tool") then
			return child
		end
	end
	return nil
end

local function getToolDamageAndRange(player: Player): (number, number)
	local tool = getEquippedTool(player)
	if not tool then
		-- No tool equipped → unarmed punch
		return UNARMED_DAMAGE, DEFAULT_RANGE
	end

	-- Look up damage by tool name; fall back to unarmed if tool isn't listed
	local damage = TOOL_DAMAGE[tool.Name] or UNARMED_DAMAGE
	return damage, DEFAULT_RANGE
end

local function isAliveEnemy(model: Instance): boolean
	if not model:IsA("Model") then
		return false
	end
	if model:GetAttribute("IsEnemy") ~= true then
		return false
	end

	local hum = getHumanoid(model)
	if not hum or hum.Health <= 0 then
		return false
	end

	return true
end

local function getEnemiesFolder(): Folder?
	if typeof(WorldService.GetCurrentWorld) ~= "function" then
		return nil
	end

	local world = WorldService.GetCurrentWorld()
	if not world then
		return nil
	end

	local enemies = world.generated:FindFirstChild("Enemies")
	if enemies and enemies:IsA("Folder") then
		return enemies
	end

	return nil
end

local function getNearestEnemyInRange(origin: Vector3, range: number): Model?
	local enemiesFolder = getEnemiesFolder()
	if not enemiesFolder then
		return nil
	end

	local best: Model? = nil
	local bestDist = range

	for _, inst in ipairs(enemiesFolder:GetChildren()) do
		if isAliveEnemy(inst) then
			local enemy = inst :: Model
			local root = getCharacterRoot(enemy)
			if root then
				local dist = (root.Position - origin).Magnitude
				if dist <= bestDist then
					best = enemy
					bestDist = dist
				end
			end
		end
	end

	return best
end

-- Plays a one-shot hit sound on the enemy's HumanoidRootPart.
-- We create a fresh Sound each time rather than reusing one, so rapid hits
-- can overlap and play simultaneously (otherwise a second hit would restart
-- the same Sound instance, cutting off the first).
-- The Sound is parented to the HRP so its 3D position follows the skeleton.
-- task.delay cleans it up after 3 seconds — well after any hit sound finishes.
local function playHitSound(enemy: Model)
	local hrp = getCharacterRoot(enemy)
	if not hrp then return end

	local sound = Instance.new("Sound")
	sound.SoundId        = HIT_SOUND_ID
	sound.Volume         = 0.8
	sound.RollOffMaxDistance = 60   -- audible up to 60 studs away
	sound.Parent         = hrp

	sound:Play()

	task.delay(3, function()
		if sound.Parent then
			sound:Destroy()
		end
	end)
end

local function killEnemy(enemy: Model)
	local hum = getHumanoid(enemy)
	if hum then
		hum.Health = 0
	end

	task.delay(2, function()
		if enemy.Parent then
			enemy:Destroy()
		end
	end)
end

local function onAttack(player: Player)
	local now = os.clock()
	local last = attackCooldowns[player] or 0
	if now - last < ATTACK_COOLDOWN then
		return
	end
	attackCooldowns[player] = now

	local char = player.Character
	if not char then
		return
	end

	local hum = getHumanoid(char)
	local root = getCharacterRoot(char)
	if not hum or hum.Health <= 0 or not root then
		return
	end

	local damage, range = getToolDamageAndRange(player)
	local target = getNearestEnemyInRange(root.Position, range)
	if not target then
		return
	end

	local targetHum = getHumanoid(target)
	if not targetHum then
		return
	end

	targetHum:TakeDamage(damage)

	-- Visual + audio feedback on the enemy.
	playHitSound(target)
	ObjectWiggle.Wiggle(target, ObjectWiggle.Presets.Skeleton)

	-- Fire to ALL clients so everyone nearby sees the floating damage number.
	-- We include `player` (the attacker) as the first argument so each client
	-- can check whether they were the one who landed the hit — used by
	-- ComboCounter.luau to only increment the LOCAL player's combo display.
	CombatHit:FireAllClients(player, target, damage)

	if targetHum.Health <= 0 then
		killEnemy(target)
	end
end

function CombatService.Start()
	if started then
		return
	end
	started = true

	CombatAttack.OnServerEvent:Connect(onAttack)

	Players.PlayerRemoving:Connect(function(player)
		attackCooldowns[player] = nil
	end)

	print("[CombatService] Started.")
end

return CombatService