local M = {}

function M.new(get_player)
	assert(type(get_player) == "function", "player provider is required")
	local permissions = {}

	function permissions.can_edit(_self, player_index)
		local player = get_player(player_index)
		return player ~= nil and player.admin == true
	end

	function permissions.authorize(_self, context)
		if context and context.origin == "remote" then
			return true
		end
		if context and permissions:can_edit(context.player_index) then
			return true
		end
		return false, { { field = "authorization", message = "only an admin can edit rules" } }
	end

	return permissions
end

return M
