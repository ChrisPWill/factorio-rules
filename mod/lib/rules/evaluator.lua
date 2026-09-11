local Selector = require("lib.rules.selector")

local M = {}

local function evaluate_condition(condition, context, predicates, services, explain)
	if condition.predicate then
		local predicate = predicates[condition.predicate]
		if not predicate then
			return nil, nil, "unknown predicate " .. condition.predicate
		end
		local matched = not not predicate(context, condition, services)
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
			evaluate_condition(condition["not"], context, predicates, services, explain)
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
			evaluate_condition(child_condition, context, predicates, services, explain)
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

function M.new(predicates, settings)
	local applicable = settings and settings.applicable
	assert(type(predicates) == "table", "predicates must be a table")
	local evaluator = {}

	function evaluator.evaluate(_self, rules, context, options)
		options = options or {}
		local services = options.services or {}
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
				local selected, rejected_by = Selector.matches(rule, context)
				if selected and applicable and not applicable(rule, context) then
					selected, rejected_by = false, "zone-scope"
				end
				if not selected then
					if rule_trace then
						rule_trace.status = "not-selected"
						rule_trace.rejected_by = rejected_by
					end
				else
					local matched, condition_trace, err = evaluate_condition(
						rule.when,
						context,
						predicates,
						services,
						options.explain
					)
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
