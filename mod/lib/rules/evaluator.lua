local M = {}

local function contains(values, expected)
	for _, value in ipairs(values or {}) do
		if value == expected then
			return true
		end
	end
	return false
end

local function matches_selector(rule, context)
	if rule.event.domain ~= context.domain or rule.event.kind ~= context.kind then
		return false, "event"
	end

	local selector = rule.selector
	local entity = context.payload.entity
	if selector.entity_types then
		local entity_type = entity and (entity.ghost_type or entity.type)
		if not contains(selector.entity_types, entity_type) then
			return false, "entity-type"
		end
	end
	if selector.entity_names then
		local entity_name = entity and (entity.ghost_name or entity.name)
		if not contains(selector.entity_names, entity_name) then
			return false, "entity-name"
		end
	end
	if selector.sources and not contains(selector.sources, context.payload.source) then
		return false, "source"
	end

	local scope = rule.scope
	if
		scope.surfaces
		and not contains(scope.surfaces, context.surface.name)
		and not contains(scope.surfaces, context.surface.index)
	then
		return false, "surface"
	end
	if scope.forces then
		local force = context.force
		if
			not force
			or (not contains(scope.forces, force.name) and not contains(scope.forces, force.index))
		then
			return false, "force"
		end
	end
	return true, nil
end

local function evaluate_condition(condition, context, predicates, explain)
	if condition.predicate then
		local predicate = predicates[condition.predicate]
		if not predicate then
			return nil, nil, "unknown predicate " .. condition.predicate
		end
		local matched = not not predicate(context, condition)
		local trace = explain
				and {
					kind = "predicate",
					predicate = condition.predicate,
					matched = matched,
				}
			or nil
		return matched, trace, nil
	end

	if condition["not"] then
		local matched, child, err =
			evaluate_condition(condition["not"], context, predicates, explain)
		if err then
			return nil, nil, err
		end
		local result = not matched
		return result, explain and { kind = "not", matched = result, child = child } or nil, nil
	end

	local key = condition.all and "all" or "any"
	local expected = key == "all"
	local result = expected
	local children = explain and {} or nil
	for _, child_condition in ipairs(condition[key]) do
		local matched, child, err =
			evaluate_condition(child_condition, context, predicates, explain)
		if err then
			return nil, nil, err
		end
		if explain then
			children[#children + 1] = child
		end
		if matched ~= expected then
			result = not expected
			if not explain then
				break
			end
		end
	end
	return result, explain and { kind = key, matched = result, children = children } or nil, nil
end

local function ordered_rules(rules)
	local result = {}
	for _, rule in ipairs(rules) do
		result[#result + 1] = rule
	end
	table.sort(result, function(left, right)
		if left.priority == right.priority then
			return left.id < right.id
		end
		return left.priority > right.priority
	end)
	return result
end

function M.new(predicates)
	assert(type(predicates) == "table", "predicates must be a table")
	local evaluator = {}

	function evaluator.evaluate(_self, rules, context, options)
		options = options or {}
		local matched_ids = {}
		local actions = {}
		local first_deny, first_warning
		local explanation = options.explain and { rules = {} } or nil

		for _, rule in ipairs(ordered_rules(rules)) do
			local rule_trace = options.explain and { rule_id = rule.id, priority = rule.priority }
				or nil
			if not rule.enabled then
				if rule_trace then
					rule_trace.status = "disabled"
				end
			else
				local selected, rejected_by = matches_selector(rule, context)
				if not selected then
					if rule_trace then
						rule_trace.status = "not-selected"
						rule_trace.rejected_by = rejected_by
					end
				else
					local matched, condition_trace, err =
						evaluate_condition(rule.when, context, predicates, options.explain)
					if err then
						return nil, "rule " .. rule.id .. ": " .. err
					end
					if rule_trace then
						rule_trace.status = matched and "matched" or "condition-false"
						rule_trace.condition = condition_trace
					end
					if matched then
						matched_ids[#matched_ids + 1] = rule.id
						local primary = rule.effects.primary
						if primary.type == "deny" and not first_deny then
							first_deny = { rule_id = rule.id, reason = primary.reason }
						elseif primary.type == "warn" and not first_warning then
							first_warning = { rule_id = rule.id, reason = primary.reason }
						end
						for _, action in ipairs(rule.effects.actions) do
							actions[#actions + 1] = { rule_id = rule.id, action = action }
						end
					end
				end
			end
			if explanation then
				explanation.rules[#explanation.rules + 1] = rule_trace
			end
		end

		local selected = first_deny or first_warning
		local result = {
			outcome = first_deny and "deny" or (first_warning and "warn" or "allow"),
			rule_id = selected and selected.rule_id or nil,
			reason = selected and selected.reason or nil,
			matched_rule_ids = matched_ids,
			actions = actions,
		}
		if explanation then
			explanation.selected_rule_id = result.rule_id
			result.explanation = explanation
		end
		return result, nil
	end

	return evaluator
end

return M
