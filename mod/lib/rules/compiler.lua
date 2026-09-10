local Selector = require("lib.rules.selector")
local serializable = require("lib.serializable")

local M = {}

local function reference_values(reference)
	local values = {}
	if reference then
		if reference.name ~= nil then
			values[#values + 1] = reference.name
		end
		values[#values + 1] = reference.index
	end
	return values
end

local DIMENSIONS = {
	{
		rule_values = function(rule)
			return rule.selector.entity_types
		end,
		context_values = function(context)
			local entity = context.payload.entity
			return { entity and (entity.ghost_type or entity.type) }
		end,
	},
	{
		rule_values = function(rule)
			return rule.selector.entity_names
		end,
		context_values = function(context)
			local entity = context.payload.entity
			return { entity and (entity.ghost_name or entity.name) }
		end,
	},
	{
		rule_values = function(rule)
			return rule.selector.sources
		end,
		context_values = function(context)
			return { context.payload.source }
		end,
	},
	{
		rule_values = function(rule)
			return rule.scope.surfaces
		end,
		context_values = function(context)
			return reference_values(context.surface)
		end,
	},
	{
		rule_values = function(rule)
			return rule.scope.forces
		end,
		context_values = function(context)
			return reference_values(context.force)
		end,
	},
}

local function value_key(value)
	return type(value) .. ":" .. tostring(value)
end

local function event_key(domain, kind)
	return domain .. "\0" .. kind
end

local function ordered(left, right)
	if left.priority == right.priority then
		return left.id < right.id
	end
	return left.priority > right.priority
end

local function deep_equal(left, right, seen)
	if left == right then
		return true
	end
	if type(left) ~= "table" or type(right) ~= "table" then
		return false
	end
	seen = seen or {}
	if seen[left] == right then
		return true
	end
	seen[left] = right
	for key, value in pairs(left) do
		if not deep_equal(value, right[key], seen) then
			return false
		end
	end
	for key in pairs(right) do
		if left[key] == nil then
			return false
		end
	end
	return true
end

local function add_requirement(target, values)
	for _, value in ipairs(values or {}) do
		target[value] = true
	end
end

local function resolve_requirement(definition, node)
	if type(definition) == "function" then
		return definition(node) or {}
	end
	return definition or {}
end

local function visit_condition(condition, definitions, capabilities, services)
	if condition.predicate then
		local requirement = resolve_requirement(definitions[condition.predicate], condition)
		add_requirement(capabilities, requirement.capabilities)
		add_requirement(services, requirement.services)
		return
	end
	if condition["not"] then
		visit_condition(condition["not"], definitions, capabilities, services)
		return
	end
	for _, child in ipairs(condition.all or condition.any or {}) do
		visit_condition(child, definitions, capabilities, services)
	end
end

local function sorted_keys(set)
	local result = {}
	for key in pairs(set) do
		result[#result + 1] = key
	end
	table.sort(result)
	return result
end

local function build(rules, options)
	local buckets = {}
	local domains, event_map = {}, {}
	local capabilities, services = {}, {}

	for _, rule in ipairs(rules) do
		if rule.enabled then
			local key = event_key(rule.event.domain, rule.event.kind)
			local bucket = buckets[key]
			if not bucket then
				bucket = { rules = {}, dimensions = {} }
				for index in ipairs(DIMENSIONS) do
					bucket.dimensions[index] = { wildcard = {}, values = {} }
				end
				buckets[key] = bucket
			end
			bucket.rules[#bucket.rules + 1] = rule
			for index, definition in ipairs(DIMENSIONS) do
				local dimension = bucket.dimensions[index]
				local values = definition.rule_values(rule)
				if not values or #values == 0 then
					dimension.wildcard[#dimension.wildcard + 1] = rule
				else
					for _, value in ipairs(values) do
						local indexed = dimension.values[value_key(value)]
						if not indexed then
							indexed = {}
							dimension.values[value_key(value)] = indexed
						end
						indexed[#indexed + 1] = rule
					end
				end
			end

			domains[rule.event.domain] = true
			event_map[key] = { domain = rule.event.domain, kind = rule.event.kind }
			visit_condition(rule.when, options.predicate_requirements, capabilities, services)
			for _, action in ipairs(rule.effects.actions) do
				local requirement =
					resolve_requirement(options.action_requirements[action.type], action)
				add_requirement(capabilities, requirement.capabilities)
				add_requirement(services, requirement.services)
			end
		end
	end

	for _, bucket in pairs(buckets) do
		table.sort(bucket.rules, ordered)
	end
	local events = {}
	for _, event in pairs(event_map) do
		events[#events + 1] = event
	end
	table.sort(events, function(left, right)
		return left.domain < right.domain
			or (left.domain == right.domain and left.kind < right.kind)
	end)

	return buckets,
		{
			domains = sorted_keys(domains),
			events = events,
			capabilities = sorted_keys(capabilities),
			services = sorted_keys(services),
		}
end

local function include_rules(set, rules)
	for _, rule in ipairs(rules or {}) do
		set[rule] = true
	end
end

function M.new(options)
	options = options or {}
	local configuration = {
		predicate_requirements = options.predicate_requirements or {},
		action_requirements = options.action_requirements or {},
	}

	local snapshot, buckets = {}, {}
	local requirements = { domains = {}, events = {}, capabilities = {}, services = {} }
	local revision = 0
	local compiler = {}

	function compiler.replace(_self, rules)
		local copied, errors = serializable.copy(rules, "rules", { strict_collections = true })
		if not copied or #errors > 0 then
			return nil, errors
		end
		if deep_equal(snapshot, copied) then
			return false
		end
		snapshot = copied
		buckets, requirements = build(snapshot, configuration)
		revision = revision + 1
		return true
	end

	function compiler.candidates(_self, context)
		local bucket = buckets[event_key(context.domain, context.kind)]
		if not bucket then
			return {}
		end

		local candidates
		for index, definition in ipairs(DIMENSIONS) do
			local dimension = bucket.dimensions[index]
			local allowed = {}
			include_rules(allowed, dimension.wildcard)
			for _, value in ipairs(definition.context_values(context)) do
				if value ~= nil then
					include_rules(allowed, dimension.values[value_key(value)])
				end
			end
			if not candidates then
				candidates = allowed
			else
				for candidate in pairs(candidates) do
					if not allowed[candidate] then
						candidates[candidate] = nil
					end
				end
			end
		end

		local result = {}
		for _, candidate in ipairs(bucket.rules) do
			if candidates[candidate] and Selector.matches(candidate, context) then
				result[#result + 1] = candidate
			end
		end
		return result
	end

	function compiler.requirements(_self)
		return assert(serializable.copy(requirements, "requirements"))
	end

	function compiler.revision(_self)
		return revision
	end

	return compiler
end

return M
