local M = {}

function M.initialize()
	-- Only lifecycle events that allow writes call this; on_load must not mutate storage.
	storage.rules = storage.rules or { schema_version = 1 }
	storage.violations = storage.violations or {}
	storage.overlays = storage.overlays or { players = {}, forced = {}, entries = {}, objects = {} }
	storage.resource_patches = storage.resource_patches
		or { schema_version = 1, next_id = 1, patches = {}, cells = {}, aliases = {} }
	storage.spawn_patches = storage.spawn_patches or { schema_version = 1, windows = {} }
end

return M
