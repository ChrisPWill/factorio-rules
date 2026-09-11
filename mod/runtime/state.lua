local M = {}

local function new_resource_patches()
	return { schema_version = 1, next_id = 1, patches = {}, cells = {}, aliases = {} }
end

local function new_spawn_patches()
	return { schema_version = 1, windows = {} }
end

local INITIALIZERS = {
	rules = function()
		return { schema_version = 1 }
	end,
	violations = function()
		return {}
	end,
	overlays = function()
		return { players = {}, forced = {}, entries = {}, objects = {} }
	end,
	resource_patches = new_resource_patches,
	spawn_patches = new_spawn_patches,
	resource_discovery = function()
		return {
			schema_version = 1,
			queue = {},
			head = 1,
			queued = {},
			processed = {},
			active = false,
			validation_pending = false,
			validation_warnings = {},
		}
	end,
}

function M.initialize(target)
	-- Only lifecycle events that allow writes call this; on_load must not mutate storage.
	target = target or storage
	target.rules = target.rules or INITIALIZERS.rules()
	target.violations = target.violations or INITIALIZERS.violations()
	target.overlays = target.overlays or INITIALIZERS.overlays()
	target.resource_patches = target.resource_patches or INITIALIZERS.resource_patches()
	target.spawn_patches = target.spawn_patches or INITIALIZERS.spawn_patches()
	target.resource_discovery = target.resource_discovery or INITIALIZERS.resource_discovery()
	return target
end

function M.reset_resource_cache(target)
	target = target or storage
	target.resource_patches = new_resource_patches()
	target.spawn_patches = new_spawn_patches()
end

return M
