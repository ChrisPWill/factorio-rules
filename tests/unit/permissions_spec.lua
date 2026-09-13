local Permissions = require("runtime.permissions")

return {
	{
		name = "allows admins and trusted remote calls but rejects regular players",
		run = function()
			local players = { [1] = { admin = true }, [2] = { admin = false } }
			local permissions = Permissions.new(function(index)
				return players[index]
			end)
			assert(permissions:can_edit(1))
			assert(not permissions:can_edit(2))
			assert(permissions:authorize({ origin = "gui", player_index = 1 }))
			local allowed, errors = permissions:authorize({ origin = "gui", player_index = 2 })
			assert(not allowed and errors[1].field == "authorization")
			assert(permissions:authorize({ origin = "remote" }))
		end,
	},
}
