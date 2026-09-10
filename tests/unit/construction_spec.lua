local Construction = require("runtime.construction")

local function entity()
	return { valid = true }
end

local function setup(candidates, outcome)
	local recorded, rejected = {}, {}
	local adapters = {
		adapt = function(_, source, event)
			assert(source == "on_built_entity" and event.entity)
			return { payload = {}, domain = "construction", kind = "entity-built" }, {
				entity = event.entity,
			}
		end,
	}
	local compiler = {
		candidates = function(_, context)
			assert(context.domain == "construction")
			return candidates
		end,
	}
	local evaluator = {
		evaluate = function(_, rules)
			assert(rules == candidates)
			return {
				outcome = outcome,
				rule_id = "test:rule",
				reason = "test reason",
				matched_rule_ids = { "test:rule" },
				actions = {},
			}
		end,
	}
	local enforcer = Construction.new({
		adapters = adapters,
		compiler = compiler,
		evaluator = evaluator,
		record = function(result)
			recorded[#recorded + 1] = result
		end,
		reject = function(boundary, result)
			rejected[#rejected + 1] = { boundary = boundary, result = result }
		end,
	})
	return enforcer, recorded, rejected
end

return {
	{
		name = "allows early when no compiled candidates exist",
		run = function()
			local enforcer, recorded, rejected = setup({}, "deny")
			local result = assert(enforcer:handle("on_built_entity", { entity = entity() }))
			assert(result.outcome == "allow" and #recorded == 0 and #rejected == 0)
		end,
	},
	{
		name = "records and rejects a denied player build",
		run = function()
			local enforcer, recorded, rejected = setup({ {} }, "deny")
			local result, boundary =
				assert(enforcer:handle("on_built_entity", { entity = entity() }))
			assert(result.outcome == "deny" and #recorded == 1 and #rejected == 1)
			assert(recorded[1].rule_id == "test:rule" and rejected[1].boundary == boundary)
		end,
	},
	{
		name = "registers the player construction event",
		run = function()
			local event_id, callback
			local script_api = {
				on_event = function(id, handler)
					event_id, callback = id, handler
				end,
			}
			local enforcer = {
				handle = function()
					return { outcome = "allow" }
				end,
			}
			Construction.register_player_event(
				script_api,
				{ events = { on_built_entity = 42 } },
				enforcer
			)
			assert(event_id == 42 and callback({ entity = entity() }).outcome == "allow")
		end,
	},
}
