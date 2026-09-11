local M = {}

local SCRIPT_SOURCES = {
	script_raised_built = true,
	script_raised_revive = true,
}

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
	local processed_tick, processed = nil, {}
	local enforcer = {}

	function enforcer.handle(_self, source, event)
		if type(event) ~= "table" or not event.entity or event.entity.valid == false then
			return { outcome = "ignored", reason = "invalid-event" }, nil, nil
		end
		local duplicate_key
		if SCRIPT_SOURCES[source] and type(event.tick) == "number" then
			if processed_tick ~= event.tick then
				processed_tick, processed = event.tick, {}
			end
			local entity = event.entity
			local position = entity.position
			duplicate_key = entity.unit_number
				or table.concat({
					entity.surface.index,
					entity.name,
					position.x,
					position.y,
				}, ":")
			if processed[duplicate_key] then
				return { outcome = "ignored", reason = "duplicate-event" }, nil, nil
			end
		end
		local context, boundary, adapter_errors = options.adapters:adapt(source, event)
		if not context then
			return nil, boundary, adapter_errors
		end
		if context.payload.entity.type == "entity-ghost" and ghost_policy == "ignore" then
			if duplicate_key then
				processed[duplicate_key] = true
			end
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
			if duplicate_key then
				processed[duplicate_key] = true
			end
			return { outcome = "allow", matched_rule_ids = {}, actions = {} }, boundary, nil
		end
		local result, evaluation_error = options.evaluator:evaluate(candidates, context)
		if not result then
			return nil, boundary, { evaluation_error }
		end
		if options.record then
			options.record(public_result(result), context)
		end
		if options.feedback then
			options.feedback(result, context, boundary)
		end
		if duplicate_key then
			processed[duplicate_key] = true
		end
		if result.outcome == "deny" and options.reject then
			options.reject(boundary, result, context)
		end
		return result, boundary, nil
	end

	return enforcer
end

function M.cooperative_interface(enforcer, tick_provider)
	assert(type(tick_provider) == "function", "tick provider is required")
	return {
		enforce_construction = function(entity, source)
			source = source or "script_raised_built"
			assert(SCRIPT_SOURCES[source], "cooperative source must be a script-raised event")
			local result, _, errors = enforcer:handle(source, {
				entity = entity,
				tick = tick_provider(),
			})
			return result, errors
		end,
	}
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
