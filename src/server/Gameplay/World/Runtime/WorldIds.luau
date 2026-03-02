--!strict
-- src/server/Gameplay/World/Runtime/WorldIds.luau
-- helpers: solo_<uid>, guid world ids, validation

local HttpService = game:GetService("HttpService")

local WorldIds = {}

export type WorldKind = "Solo" | "Guid"

export type ParsedWorldId = {
	kind: WorldKind,
	ownerUserId: number?, -- only for Solo
	raw: string,
}

local SOLO_PREFIX = "solo_"
local GUID_PREFIX = "world_"

function WorldIds.Solo(userId: number): string
	return SOLO_PREFIX .. tostring(userId)
end

function WorldIds.NewGuid(): string
	-- world_<GUID> (no braces)
	return GUID_PREFIX .. HttpService:GenerateGUID(false)
end

function WorldIds.IsSolo(worldId: string): boolean
	return string.sub(worldId, 1, #SOLO_PREFIX) == SOLO_PREFIX
end

function WorldIds.IsGuid(worldId: string): boolean
	return string.sub(worldId, 1, #GUID_PREFIX) == GUID_PREFIX
end

function WorldIds.Parse(worldId: string): ParsedWorldId?
	if WorldIds.IsSolo(worldId) then
		local num = tonumber(string.sub(worldId, #SOLO_PREFIX + 1))
		if not num then
			return nil
		end
		return {
			kind = "Solo",
			ownerUserId = num,
			raw = worldId,
		}
	end

	if WorldIds.IsGuid(worldId) then
		-- we don’t fully validate GUID format here; optional
		return {
			kind = "Guid",
			ownerUserId = nil,
			raw = worldId,
		}
	end

	return nil
end

function WorldIds.IsValid(worldId: string): boolean
	return WorldIds.Parse(worldId) ~= nil
end

return WorldIds