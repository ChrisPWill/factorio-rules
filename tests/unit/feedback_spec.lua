local Feedback = require("runtime.feedback")

local function result(outcome, id)
	return {
		outcome = outcome,
		rule_id = id,
		reason = id .. " reason",
		actions = { { rule_id = id, action = { type = "test:ping" } } },
	}
end

local function context(actor)
	return {
		domain = "construction",
		kind = "entity-built",
		surface = { index = 1, name = "nauvis" },
		force = { index = 2, name = "player" },
		actor = actor,
		metadata = { tick = 10 },
		payload = { source = "player" },
	}
end

return {
	{
		name = "routes player and force feedback with rule details",
		run = function()
			local players, forces = {}, {}
			local feedback = Feedback.new({
				history_limit = function()
					return 0
				end,
				notify_player = function(index, message)
					players[#players + 1] = { index, message }
				end,
				notify_force = function(index, message)
					forces[#forces + 1] = { index, message }
				end,
			})
			feedback:emit(
				result("deny", "test:manual"),
				context({
					kind = "player",
					player_index = 3,
				})
			)
			feedback:emit(result("warn", "test:robot"), context({ kind = "robot" }))
			assert(players[1][1] == 3 and players[1][2]:find("test:manual", 1, true))
			assert(forces[1][1] == 2 and forces[1][2]:find("test:robot", 1, true))
		end,
	},
	{
		name = "bounds history and can disable it",
		run = function()
			local history, limit = {}, 2
			local feedback = Feedback.new({
				history = function()
					return history
				end,
				history_limit = function()
					return limit
				end,
			})
			for _, id in ipairs({ "test:one", "test:two", "test:three" }) do
				feedback:emit(result("deny", id), context())
			end
			assert(#history == 2 and history[1].rule_id == "test:two")
			limit = 0
			feedback:emit(result("deny", "test:four"), context())
			assert(#history == 2)
		end,
	},
	{
		name = "dispatches secondary actions outside rollback",
		run = function()
			local dispatched
			local feedback = Feedback.new({
				history_limit = function()
					return 0
				end,
				actions = {
					["test:ping"] = function(action, entry, _, boundary)
						dispatched = { action = action, entry = entry, boundary = boundary }
					end,
				},
			})
			local boundary = { entity = "raw" }
			feedback:emit(result("deny", "test:action"), context(), boundary)
			assert(dispatched.action.type == "test:ping")
			assert(dispatched.entry.rule_id == "test:action")
			assert(dispatched.boundary == boundary)
		end,
	},
}
