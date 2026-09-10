local M = {}

function M.debug(message)
	if settings.global["factorio-rules-debug"].value then
		log("[factorio-rules] " .. message)
	end
end

return M
