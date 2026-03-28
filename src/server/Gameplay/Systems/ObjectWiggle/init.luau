--!strict
-- src/server/Gameplay/Systems/ObjectWiggle/init.luau
--
-- Universal "hit reaction" wiggle for any Model in the game.
-- Originally only used for trees (TreeWiggle). Now reusable for skeletons,
-- crystals, barrels — anything you want to visually react when struck.
--
-- ── HOW IT WORKS ────────────────────────────────────────────────────────────
-- Every Model in Roblox has a "pivot" — a CFrame (position + orientation)
-- that describes where the model's centre/root is in the world.
--
--   model:GetPivot()   → returns the current pivot CFrame
--   model:PivotTo(cf)  → instantly moves the ENTIRE model so its pivot lands
--                        at `cf`. All parts move together, even if anchored.
--
-- We capture the model's current pivot, then run a two-phase animation loop:
--
--   Phase 1 (UP_TIME seconds)  : tilt from neutral → max angle
--   Phase 2 (DOWN_TIME seconds): tilt from max angle → neutral
--
-- Each phase runs inside task.spawn so it never blocks the calling thread.
-- The "Wiggling" attribute prevents a second hit from starting a new wiggle
-- while one is already playing (avoids jittery overlapping animations).
--
-- ── WHY LERP CFRAMES? ───────────────────────────────────────────────────────
-- CFrame:Lerp(other, alpha) blends smoothly between two CFrames.
--   alpha=0  → 100% original
--   alpha=1  → 100% target
--   alpha=0.5 → halfway
-- By driving alpha from 0→1 each frame we get a smooth easing effect.
-- We multiply the base CFrame by the rotation offset so the tilt happens
-- relative to the object's current orientation, not world axes.
--
-- ── USAGE ───────────────────────────────────────────────────────────────────
--   local ObjectWiggle = require(...)
--
--   -- Simple call (uses Default preset):
--   ObjectWiggle.Wiggle(someModel)
--
--   -- With a built-in preset:
--   ObjectWiggle.Wiggle(someModel, ObjectWiggle.Presets.Tree)
--   ObjectWiggle.Wiggle(skeleton,  ObjectWiggle.Presets.Skeleton)
--   ObjectWiggle.Wiggle(crystal,   ObjectWiggle.Presets.Crystal)
--
--   -- Fully custom params (any field is optional):
--   ObjectWiggle.Wiggle(someModel, { maxDeg = 10, upTime = 0.04 })
-- ────────────────────────────────────────────────────────────────────────────

local ObjectWiggle = {}

-- ── Debug flag ───────────────────────────────────────────────────────────────
-- Set to true to see a print every time Wiggle() is called.
local DEBUG = false

local function log(...)
	if DEBUG then
		print("[ObjectWiggle]", ...)
	end
end

-- ── WiggleParams type ────────────────────────────────────────────────────────
-- All fields are optional. Any field you don't supply falls back to the
-- defaults defined in DEFAULT_PARAMS below.
--
-- maxDeg   : how many degrees the object tilts at peak. Bigger = more dramatic.
-- minDeg   : minimum tilt (randomised between min and max each call).
-- upTime   : seconds to reach peak tilt  (fast = snappy hit feel).
-- downTime : seconds to return to neutral (slow = gentle settling).
export type WiggleParams = {
	maxDeg: number?,
	minDeg: number?,
	upTime: number?,
	downTime: number?,
}

-- ── Defaults ─────────────────────────────────────────────────────────────────
-- Used as the fallback for any field not supplied by the caller.
local DEFAULT_PARAMS: WiggleParams = {
	maxDeg   = 4,
	minDeg   = 2,
	upTime   = 0.06,
	downTime = 0.10,
}

-- ── Presets ──────────────────────────────────────────────────────────────────
-- Named parameter sets for the objects we know about.
-- You can add more presets here as the game grows without changing any
-- call sites — just pass ObjectWiggle.Presets.MyNewThing where you need it.
ObjectWiggle.Presets = {

	-- Trees: moderate tilt, quick snap, slow settle (feels heavy).
	Tree = {
		maxDeg   = 4,
		minDeg   = 2,
		upTime   = 0.06,
		downTime = 0.10,
	},

	-- Skeletons: more dramatic tilt (they're light/bony), faster recovery.
	Skeleton = {
		maxDeg   = 8,
		minDeg   = 4,
		upTime   = 0.05,
		downTime = 0.12,
	},

	-- Crystals / ore nodes: subtle, stiff wobble. They're rigid rock.
	Crystal = {
		maxDeg   = 2,
		minDeg   = 1,
		upTime   = 0.04,
		downTime = 0.16,
	},

}

-- ── Internal helpers ─────────────────────────────────────────────────────────

-- Resolves any Instance to the Model that should be wiggled.
-- If given a Model directly, return it.
-- If given a Part (e.g. a limb), walk up the tree to find its parent Model.
local function resolveModel(target: Instance): Model?
	if target:IsA("Model") then
		return target
	end
	-- FindFirstAncestorOfClass walks up the hierarchy until it finds a Model.
	return target:FindFirstAncestorOfClass("Model")
end

-- Merges caller-supplied params with the defaults so every field is always
-- a valid number inside the animation loop.
local function resolveParams(params: WiggleParams?): WiggleParams
	local p = params or {}
	return {
		maxDeg   = (p :: WiggleParams).maxDeg   or (DEFAULT_PARAMS.maxDeg   :: number),
		minDeg   = (p :: WiggleParams).minDeg   or (DEFAULT_PARAMS.minDeg   :: number),
		upTime   = (p :: WiggleParams).upTime   or (DEFAULT_PARAMS.upTime   :: number),
		downTime = (p :: WiggleParams).downTime or (DEFAULT_PARAMS.downTime :: number),
	}
end

-- ── Public API ───────────────────────────────────────────────────────────────

-- ObjectWiggle.Wiggle(target, params?)
--
-- Plays a one-shot tilt animation on the Model that contains `target`.
-- Safe to call from any server Script; never yields the caller.
--
-- Parameters:
--   target  : the Model (or any descendant Part) to wiggle.
--   params  : optional WiggleParams table, or one of ObjectWiggle.Presets.
function ObjectWiggle.Wiggle(target: Instance, params: WiggleParams?)
	local model = resolveModel(target)
	if not model then
		-- Nothing to wiggle (e.g. a stray Part with no parent Model).
		return
	end

	-- ── Guard: don't start a second wiggle while one is still running ──────
	-- GetAttribute returns nil if the attribute was never set, so we check
	-- for the value `true` specifically to be safe.
	if model:GetAttribute("Wiggling") == true then
		return
	end
	model:SetAttribute("Wiggling", true)

	-- Merge the caller's params with defaults.
	local p = resolveParams(params)

	-- Capture the model's current pivot in world space.
	-- This is the "rest pose" we animate away from and return to.
	local baseCFrame: CFrame = model:GetPivot()

	-- Pick a random tilt angle between minDeg and maxDeg, and a random side
	-- (left or right). `math.random(0, 1) == 0` is a coin flip.
	local angleDeg = math.random(
		math.floor(p.minDeg :: number),
		math.floor(p.maxDeg :: number)
	)
	local angleRad = math.rad(angleDeg)
	local side     = if math.random(0, 1) == 0 then -1 else 1

	-- Build the "peak" rotation offset as a CFrame.
	-- CFrame.Angles(rx, ry, rz) creates a pure rotation CFrame.
	-- We tilt on the Z axis so the object leans left/right.
	-- Multiplying baseCFrame * rotOffset applies the tilt relative to the
	-- object's own orientation (not world axes), which looks correct even if
	-- the model itself is rotated.
	local rotOffset: CFrame = CFrame.Angles(0, 0, side * angleRad)

	log("Wiggle:", model.Name, angleDeg .. "°", if side == 1 then "right" else "left")

	-- task.spawn runs the animation in a new thread so this function returns
	-- immediately. The caller is never blocked or delayed.
	task.spawn(function()
		-- ── PHASE 1: tilt toward peak ────────────────────────────────────
		-- We track how much time has passed since phase start (`t0`).
		-- `alpha` goes from 0 to 1 as time passes.
		local t0 = os.clock()

		while true do
			local elapsed = os.clock() - t0
			local alpha   = elapsed / (p.upTime :: number)

			if alpha >= 1 then
				break  -- phase complete
			end

			-- CFrame.new() is the identity CFrame (no translation, no rotation).
			-- Lerp from identity → rotOffset means we go from neutral → peak tilt.
			local currentOffset = CFrame.new():Lerp(rotOffset, alpha)

			-- Apply: base position * tilt offset = final world CFrame for this frame.
			model:PivotTo(baseCFrame * currentOffset)

			-- task.wait() with no argument yields for one frame (RunService.Heartbeat).
			-- This means the animation runs once per physics step (~60 fps on server).
			task.wait()
		end

		-- Snap to exact peak to avoid any sub-frame overshoot.
		model:PivotTo(baseCFrame * rotOffset)

		-- ── PHASE 2: settle back to neutral ──────────────────────────────
		t0 = os.clock()

		while true do
			local elapsed = os.clock() - t0
			local alpha   = elapsed / (p.downTime :: number)

			if alpha >= 1 then
				break
			end

			-- Lerp from rotOffset → identity: peak tilt → neutral.
			local currentOffset = rotOffset:Lerp(CFrame.new(), alpha)
			model:PivotTo(baseCFrame * currentOffset)

			task.wait()
		end

		-- Snap exactly back to the original rest pose. Without this, floating
		-- point rounding in the loop could leave the model very slightly tilted.
		model:PivotTo(baseCFrame)

		-- Release the lock so the next hit can trigger a wiggle again.
		model:SetAttribute("Wiggling", false)
	end)
end

return ObjectWiggle
