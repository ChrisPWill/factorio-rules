local M = {}

function M.initialize()
	-- Only lifecycle events that allow writes call this; on_load must not mutate storage.
	storage.rules = storage.rules or { schema_version = 1 }
end

return M
