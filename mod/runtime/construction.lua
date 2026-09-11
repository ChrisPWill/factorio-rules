local M = {}

local function public_result(result)
	return {
		outcome = result.outcome,
		rule_id = result.rule_id,
		reason = result.reason,
		matched_rule_ids = result.matched_rule_ids,
	}
end

function M.new(options)
	assert(type(options) == "table", "construction options must be a table")
	assert(type(options.adapters) == "table", "construction adapters are required")
	assert(type(options.compiler) == "table", "construction compiler is required")
	assert(type(options.evaluator) == "table", "construction evaluator is required")
	local ghost_policy = options.ghost_policy or "evaluate"
	assert(ghost_policy == "evaluate" or ghost_policy == "ignore", "invalid ghost policy")
	local enforcer = {}

	function enforcer.handle(_self, source, event)
		if type(event) ~= "table" or not event.entity or event.entity.valid == false then
			return { outcome = "ignored", reason = "invalid-event" }, nil, nil
		end
		local context, boundary, adapter_errors = options.adapters:adapt(source, event)
		if not context then
			return nil, boundary, adapter_errors
		end
		if context.payload.entity.type == "entity-ghost" and ghost_policy == "ignore" then
			return {
				outcome = "allow",
				reason = "ghost-ignored",
				matched_rule_ids = {},
				actions = {},
			},
				boundary,
				nil
		end
		local candidates = options.compiler:candidates(context)
		if #candidates == 0 then
			return { outcome = "allow", matched_rule_ids = {}, actions = {} }, boundary, nil
		end
		local result, evaluation_error = options.evaluator:evaluate(candidates, context)
		if not result then
			return nil, boundary, { evaluation_error }
		end
		if options.record then
			options.record(public_result(result), context)
		end
		if result.outcome == "deny" and options.reject then
			options.reject(boundary, result, context)
		end
		return result, boundary, nil
	end

	return enforcer
end

local function register_event(script_api, event_id, source, enforcer)
	script_api.on_event(event_id, function(event)
		local result, _, errors = enforcer:handle(source, event)
		if errors then
			error(table.concat(errors, "; "))
		end
		return result
	end)
end

function M.register_player_event(script_api, defines_api, enforcer)
	assert(script_api and type(script_api.on_event) == "function")
	assert(defines_api.events and defines_api.events.on_built_entity)
	register_event(script_api, defines_api.events.on_built_entity, "on_built_entity", enforcer)
end

function M.register_construction_events(script_api, defines_api, enforcer)
	assert(script_api and type(script_api.on_event) == "function")
	assert(defines_api and defines_api.events)
	local events = {
		{ "on_built_entity", "on_built_entity" },
		{ "on_robot_built_entity", "on_robot_built_entity" },
		{ "script_raised_built", "script_raised_built" },
		{ "script_raised_revive", "script_raised_revive" },
	}
	for _, entry in ipairs(events) do
		local event_id = defines_api.events[entry[1]]
		if event_id then
			register_event(script_api, event_id, entry[2], enforcer)
		end
	end
end

return M
