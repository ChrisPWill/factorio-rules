local M = {}

function M.initialize()
	-- Only lifecycle events that allow writes call this; on_load must not mutate storage.
	storage.rules = storage.rules or { schema_version = 1 }
	storage.violations = storage.violations or {}
	storage.overlays = storage.overlays or { players = {}, forced = {}, entries = {}, objects = {} }
end

return M
