--!strict
-- src/client/CrouchSlide.client.luau

local UIS = game:GetService("UserInputService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer

-- TUNING
local NORMAL_SPEED = 16
local CROUCH_SPEED = 10
local CROUCH_KEY = Enum.KeyCode.C

local SLIDE_DURATION = 0.35
local SLIDE_SPEED = 45
local SLIDE_COOLDOWN = 1.0
local MOVE_THRESHOLD = 0.08

-- Visible crouch
local CROUCH_HIPHEIGHT_DELTA = 1.2

-- State
local humanoid: Humanoid? = nil
local root: BasePart? = nil
local isCrouching = false
local sliding = false
local lastSlideTime = -999.0
local baseHipHeight = 2.0

local slideConn: RBXScriptConnection? = nil

local function log(...)
	print("[CrouchSlide]", ...)
end

local function disconnectSlide()
	local c = slideConn
	if c then
		c:Disconnect()
		slideConn = nil
	end
end

local function bindCharacter(char: Model)
	-- Prefer FindFirstChildOfClass for correct typing
	local hum = char:FindFirstChildOfClass("Humanoid")
	local hrp = char:FindFirstChild("HumanoidRootPart")

	if not hum then
		log("bindCharacter: Humanoid missing (char not ready yet?)")
		return
	end
	if not hrp or not hrp:IsA("BasePart") then
		log("bindCharacter: HumanoidRootPart missing (char not ready yet?)")
		return
	end

	humanoid = hum
	root = hrp

	isCrouching = false
	sliding = false
	lastSlideTime = -999.0

	baseHipHeight = hum.HipHeight
	hum.WalkSpeed = NORMAL_SPEED

	disconnectSlide()

	log("Bound character:", char.Name, "HipHeight=", baseHipHeight)
end

if player.Character then
	bindCharacter(player.Character)
end

player.CharacterAdded:Connect(function(char)
	-- small defer helps because CharacterAdded can fire before parts exist
	task.defer(function()
		bindCharacter(char)
	end)
end)

local function applyCrouchVisual()
	local hum = humanoid
	if not hum then
		return
	end

	if isCrouching then
		hum.HipHeight = math.max(0, baseHipHeight - CROUCH_HIPHEIGHT_DELTA)
	else
		hum.HipHeight = baseHipHeight
	end
end

local function applySpeed()
	local hum = humanoid
	if not hum then
		return
	end
	if sliding then
		return
	end

	hum.WalkSpeed = isCrouching and CROUCH_SPEED or NORMAL_SPEED
end

local function toggleCrouch()
	local hum = humanoid
	if not hum then
		return
	end
	if sliding then
		log("toggleCrouch blocked: sliding")
		return
	end

	isCrouching = not isCrouching
	applyCrouchVisual()
	applySpeed()

	log("CROUCH TOGGLE =>", isCrouching, "WalkSpeed=", hum.WalkSpeed, "HipHeight=", hum.HipHeight)
end

local function endSlide()
	disconnectSlide()

	local hum = humanoid
	if not hum then
		return
	end

	sliding = false

	-- After slide, stay crouched
	isCrouching = true
	applyCrouchVisual()
	applySpeed()

	-- Restore humanoid control
	if hum:GetState() == Enum.HumanoidStateType.Physics then
		hum:ChangeState(Enum.HumanoidStateType.Running)
	end

	log("SLIDE END. crouching=", isCrouching, "WalkSpeed=", hum.WalkSpeed)
end

local function startSlide()
	local hum = humanoid
	local r = root
	if not hum or not r then
		return
	end
	if sliding then
		return
	end

	local now = os.clock()
	local cdLeft = SLIDE_COOLDOWN - (now - lastSlideTime)
	if cdLeft > 0 then
		log(("Slide blocked: cooldown %.2fs left"):format(cdLeft))
		return
	end

	if hum.MoveDirection.Magnitude <= MOVE_THRESHOLD then
		log("Slide blocked: not moving")
		return
	end

	sliding = true
	lastSlideTime = now

	-- Slide implies crouch, but DON'T lower hipheight during the slide
	isCrouching = true
	hum.HipHeight = baseHipHeight

	-- Keep some motion, don't set to 0
	hum.WalkSpeed = 2

	-- Let physics/velocity drive motion briefly
	hum:ChangeState(Enum.HumanoidStateType.Physics)

	-- Determine direction
	local dir = hum.MoveDirection
	dir = Vector3.new(dir.X, 0, dir.Z)
	if dir.Magnitude < 0.001 then
		local look = r.CFrame.LookVector
		dir = Vector3.new(look.X, 0, look.Z)
	end
	if dir.Magnitude < 0.001 then
		-- super edge case: still no direction
		endSlide()
		return
	end
	dir = dir.Unit

	log("SLIDE START. speed=", SLIDE_SPEED)

	local startTime = os.clock()
	disconnectSlide()
	slideConn = RunService.Heartbeat:Connect(function()
		local r2 = root
		if not sliding or not r2 then
			return
		end

		local t = os.clock() - startTime
		if t >= SLIDE_DURATION then
			endSlide()
			return
		end

		local v = r2.AssemblyLinearVelocity
		r2.AssemblyLinearVelocity = Vector3.new(dir.X * SLIDE_SPEED, v.Y, dir.Z * SLIDE_SPEED)
	end)
end

UIS.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end

	local hum = humanoid
	if not hum then
		log("Input ignored: humanoid not ready")
		return
	end

	if input.KeyCode == CROUCH_KEY then
		if hum.MoveDirection.Magnitude > MOVE_THRESHOLD then
			startSlide()
		else
			toggleCrouch()
		end
	end
end)