local M = {}

local function format_message(result)
	return string.format("[factorio-rules] %s (%s)", result.reason, result.rule_id)
end

local function violation(result, context)
	return {
		tick = context.metadata.tick,
		outcome = result.outcome,
		rule_id = result.rule_id,
		reason = result.reason,
		domain = context.domain,
		kind = context.kind,
		surface = context.surface,
		force = context.force,
		actor = context.actor,
		source = context.payload.source,
	}
end

function M.new(options)
	assert(type(options) == "table", "feedback options must be a table")
	local feedback = {}

	function feedback.emit(_self, result, context, boundary)
		if result.outcome ~= "deny" and result.outcome ~= "warn" then
			return nil
		end

		local entry = violation(result, context)
		local limit = options.history_limit and options.history_limit() or 0
		if limit > 0 then
			local history = assert(options.history(), "feedback history is unavailable")
			history[#history + 1] = entry
			while #history > limit do
				table.remove(history, 1)
			end
		end

		local message = format_message(result)
		if context.actor and context.actor.kind == "player" and options.notify_player then
			options.notify_player(context.actor.player_index, message)
		elseif context.force and options.notify_force then
			options.notify_force(context.force.index, message)
		end

		for _, intent in ipairs(result.actions) do
			local action = options.actions and options.actions[intent.action.type]
			if action then
				action(intent.action, entry, context, boundary)
			end
		end
		return entry
	end

	return feedback
end

function M.factorio(options)
	return M.new({
		history = options.history,
		history_limit = options.history_limit,
		actions = options.actions,
		notify_player = function(index, message)
			local player = options.get_player(index)
			if player then
				player.print(message)
			end
		end,
		notify_force = function(index, message)
			local force = options.get_force(index)
			if force then
				force.print(message)
			end
		end,
	})
end

return M
