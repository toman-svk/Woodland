-- src/server/SprintMana.server.luau

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local sprintEvent = Shared:WaitForChild("SprintToggle")

--========================
-- TUNING
--========================
local NORMAL_SPEED = 16
local SPRINT_SPEED = 28

local DRAIN_PER_SECOND = 12
local REGEN_PER_SECOND = 8
local REGEN_COOLDOWN = 1.0
local MIN_MANA_TO_SPRINT = 1

local TICK = 0.2
local MOVEMENT_THRESHOLD = 0.1   -- how much MoveDirection magnitude counts as moving

--========================
-- State
--========================
local sprinting = {}        -- [player] = true/false
local lastSprintEnd = {}    -- [player] = time sprint stopped

--========================
-- Helpers
--========================
local function getStats(player)
	local stats = player:FindFirstChild("Stats")
	if not stats then return nil end

	local mana = stats:FindFirstChild("Mana")
	local maxMana = stats:FindFirstChild("MaxMana")
	if not (mana and maxMana) then return nil end

	return mana, maxMana
end

local function getHumanoid(player)
	local char = player.Character
	if not char then return nil end
	return char:FindFirstChildOfClass("Humanoid")
end

local function isActuallyMoving(humanoid)
	if not humanoid then return false end
	return humanoid.MoveDirection.Magnitude > MOVEMENT_THRESHOLD
end

local function setWalkSpeed(player, speed)
	local hum = getHumanoid(player)
	if hum then
		hum.WalkSpeed = speed
	end
end

--========================
-- Sprint toggle from client
--========================
sprintEvent.OnServerEvent:Connect(function(player, wantsSprint)
	local mana, maxMana = getStats(player)
	if not mana then return end

	if wantsSprint then
		if mana.Value >= MIN_MANA_TO_SPRINT then
			sprinting[player] = true
			setWalkSpeed(player, SPRINT_SPEED)
		else
			sprinting[player] = false
			lastSprintEnd[player] = os.clock()
			setWalkSpeed(player, NORMAL_SPEED)
			sprintEvent:FireClient(player, false)
		end
	else
		if sprinting[player] then
			sprinting[player] = false
			lastSprintEnd[player] = os.clock()
			setWalkSpeed(player, NORMAL_SPEED)
		end
	end
end)

--========================
-- Drain + Regen Loop
--========================
task.spawn(function()
	while true do
		task.wait(TICK)
		local now = os.clock()

		for _, player in ipairs(Players:GetPlayers()) do
			local mana, maxMana = getStats(player)
			local humanoid = getHumanoid(player)

			if not (mana and maxMana and humanoid) then
				continue
			end

			-- Clamp mana
			if mana.Value > maxMana.Value then
				mana.Value = maxMana.Value
			elseif mana.Value < 0 then
				mana.Value = 0
			end

			if sprinting[player] then
				-- Only drain if actually moving
				if isActuallyMoving(humanoid) then
					local drain = DRAIN_PER_SECOND * TICK
					mana.Value = math.max(0, mana.Value - drain)

					if mana.Value <= 0 then
						sprinting[player] = false
						lastSprintEnd[player] = now
						setWalkSpeed(player, NORMAL_SPEED)
						sprintEvent:FireClient(player, false)
					end
				end
			else
				-- Regen after cooldown
				local endTime = lastSprintEnd[player]
				local cooldownOver = (not endTime) or ((now - endTime) >= REGEN_COOLDOWN)

				if cooldownOver and mana.Value < maxMana.Value then
					local regen = REGEN_PER_SECOND * TICK
					mana.Value = math.min(maxMana.Value, mana.Value + regen)
				end
			end
		end
	end
end)

Players.PlayerRemoving:Connect(function(player)
	sprinting[player] = nil
	lastSprintEnd[player] = nil
end)
