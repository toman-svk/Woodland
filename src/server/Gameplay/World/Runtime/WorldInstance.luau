--!strict
-- src/server/Gameplay/World/Runtime/WorldInstance.luau
-- per-server world runtime state (seed, save, folders)

local WorldInstance = {}
WorldInstance.__index = WorldInstance

export type WorldSave = {
	seed: number,
	-- later:
	-- diffs: { choppedTrees: {[string]: boolean}, minedGems: {[string]: boolean} },
}

export type WorldInstance = {
	WorldId: string,
	OwnerUserId: number?,
	Seed: number,

	Root: Folder,      -- workspace container for this world
	Generated: Folder, -- root/Generated (or whatever you use)
	Origin: Vector3,

	Save: WorldSave,

	CreatedAt: number,
	Dirty: boolean,

	MarkDirty: (self: WorldInstance) -> (),
	SetDirty: (self: WorldInstance, dirty: boolean) -> (),
}

function WorldInstance.new(worldId: string, ownerUserId: number?, root: Folder, generated: Folder, origin: Vector3, save: WorldSave): WorldInstance
	local self = setmetatable({}, WorldInstance) :: any

	self.WorldId = worldId
	self.OwnerUserId = ownerUserId
	self.Seed = save.seed

	self.Root = root
	self.Generated = generated
	self.Origin = origin

	self.Save = save

	self.CreatedAt = os.clock()
	self.Dirty = false

	return self
end

function WorldInstance:MarkDirty()
	self.Dirty = true
end

function WorldInstance:SetDirty(dirty: boolean)
	self.Dirty = dirty
end

return WorldInstance