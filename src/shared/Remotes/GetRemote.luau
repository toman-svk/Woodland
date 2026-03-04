--!strict
-- src/shared/Remotes/GetRemote.luau
-- Small helper to reliably fetch remotes from ReplicatedStorage.Shared.Remotes

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = Shared:WaitForChild("Remotes")

export type RemoteClass =
	"RemoteEvent"
	| "RemoteFunction"
	| "BindableEvent"
	| "BindableFunction"

local function isExpectedClass(inst: Instance, expected: RemoteClass): boolean
	if expected == "RemoteEvent" then
		return inst:IsA("RemoteEvent")
	elseif expected == "RemoteFunction" then
		return inst:IsA("RemoteFunction")
	elseif expected == "BindableEvent" then
		return inst:IsA("BindableEvent")
	elseif expected == "BindableFunction" then
		return inst:IsA("BindableFunction")
	end
	return false
end

local function GetRemote<T>(name: string, expectedClass: RemoteClass?): T
	local inst = Remotes:WaitForChild(name)

	if expectedClass ~= nil then
		if not isExpectedClass(inst, expectedClass) then
			error(
				("[GetRemote] '%s' exists but is %s (expected %s). Path=%s"):format(
					name,
					inst.ClassName,
					expectedClass,
					inst:GetFullName()
				)
			)
		end
	end

	return inst :: any
end

return GetRemote