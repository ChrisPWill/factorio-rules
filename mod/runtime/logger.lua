local M = {}

function M.new(settings, write)
	assert(type(settings) == "table", "Factorio settings are required")
	assert(type(write) == "function", "Factorio log function is required")
	return {
		debug = function(message)
			if settings.global["factorio-rules-debug"].value then
				write("[factorio-rules] " .. message)
			end
		end,
	}
end

return M
