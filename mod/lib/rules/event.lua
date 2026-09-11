local M = {}

function M.key(event)
	return event.domain .. "\0" .. event.kind
end

return M
