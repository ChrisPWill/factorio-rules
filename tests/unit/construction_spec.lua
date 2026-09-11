local Construction = require("runtime.construction")

local function entity()
	return { valid = true }
end

local function setup(candidates, outcome, ghost_policy)
	local recorded, rejected = {}, {}
	local adapters = {
		adapt = function(_, _source, event)
			assert(event.entity)
			return {
				payload = { entity = event.entity },
				domain = "construction",
				kind = "entity-built",
			}, {
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
		ghost_policy = ghost_policy,
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
	{
		name = "evaluates robot builds through the same path",
		run = function()
			local enforcer, recorded = setup({ {} }, "deny")
			local result = assert(enforcer:handle("on_robot_built_entity", { entity = entity() }))
			assert(result.outcome == "deny" and #recorded == 1)
		end,
	},
	{
		name = "can ignore ghosts explicitly while evaluating completed entities",
		run = function()
			local ghost = { valid = true, type = "entity-ghost" }
			local enforcer, recorded = setup({ {} }, "deny")
			local result = assert(enforcer:handle("script_raised_built", { entity = ghost }))
			assert(result.outcome == "deny")
			local ignoring, ignored_recorded = setup({ {} }, "deny", "ignore")
			result = assert(ignoring:handle("script_raised_built", { entity = ghost }))
			assert(result.outcome == "allow")
			assert(#recorded == 1 and #ignored_recorded == 0)
		end,
	},
	{
		name = "registers all construction event sources",
		run = function()
			local registered = {}
			local script_api = {
				on_event = function(id)
					registered[#registered + 1] = id
				end,
			}
			Construction.register_construction_events(script_api, {
				events = {
					on_built_entity = 1,
					on_robot_built_entity = 2,
					script_raised_built = 3,
					script_raised_revive = 4,
				},
			}, {
				handle = function()
					return { outcome = "allow" }
				end,
			})
			assert(#registered == 4)
		end,
	},
	{
		name = "deduplicates cooperative and script-raised enforcement in the same tick",
		run = function()
			local enforcer, recorded, rejected = setup({ {} }, "deny")
			local subject = {
				valid = true,
				type = "assembling-machine",
				name = "assembling-machine-1",
				unit_number = 17,
				position = { x = 4, y = 5 },
				surface = { index = 1 },
			}
			local api = Construction.cooperative_interface(enforcer, function()
				return 50
			end)
			local first = assert(api.enforce_construction(subject))
			local duplicate = assert(enforcer:handle("script_raised_built", {
				entity = subject,
				tick = 50,
			}))
			assert(first.outcome == "deny")
			assert(duplicate.outcome == "ignored" and duplicate.reason == "duplicate-event")
			assert(#recorded == 1 and #rejected == 1)
		end,
	},
}
