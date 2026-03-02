--!strict
-- ServerScriptService/Server/Systems/TreeWiggle
-- Simple "whole object" wiggle using PivotTo (works even if anchored)

local TreeWiggle = {}

local DEBUG = false

local function log(...)
	if DEBUG then
		print("[TreeWiggle]", ...)
	end
end

-- How strong / long the wiggle is
local MAX_DEG = 4
local UP_TIME = 0.06
local DOWN_TIME = 0.10

local function getPivotInstance(treeTarget: Instance): Model?
	if treeTarget:IsA("Model") then
		return treeTarget
	end
	-- If we got a part (rare), try its model
	local model = treeTarget:FindFirstAncestorOfClass("Model")
	return model
end

function TreeWiggle.Wiggle(treeTarget: Instance)
	local model = getPivotInstance(treeTarget)
	if not model then
		return
	end

	-- Prevent overlapping wiggles
	if model:GetAttribute("Wiggling") == true then
		return
	end
	model:SetAttribute("Wiggling", true)

	-- Ensure pivot is stable
	-- (If PrimaryPart isn't set, PivotTo still works; Roblox uses a computed pivot)
	local base = model:GetPivot()

	local angle = math.rad(math.random(2, MAX_DEG))
	local dir = (math.random(0, 1) == 0) and -1 or 1
	local rot = CFrame.Angles(0, 0, dir * angle) -- small tilt

	log("wiggle", model.Name)

	task.spawn(function()
		local t0 = os.clock()

		-- Ease to rotated
		while true do
			local a = (os.clock() - t0) / UP_TIME
			if a >= 1 then break end
			local t = CFrame.new():Lerp(rot, a)
			model:PivotTo(base * t)
			task.wait()
		end
		model:PivotTo(base * rot)

		-- Ease back to base
		t0 = os.clock()
		while true do
			local a = (os.clock() - t0) / DOWN_TIME
			if a >= 1 then break end
			local t = rot:Lerp(CFrame.new(), a)
			model:PivotTo(base * t)
			task.wait()
		end

		model:PivotTo(base)
		model:SetAttribute("Wiggling", false)
	end)
end

return TreeWiggle