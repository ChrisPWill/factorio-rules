local Event = require("lib.rules.event")

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
		reason = "entity-type",
		rule_values = function(rule)
			return rule.selector.entity_types
		end,
		context_values = function(context)
			local entity = context.payload.entity
			return { entity and (entity.ghost_type or entity.type) }
		end,
	},
	{
		reason = "entity-name",
		rule_values = function(rule)
			return rule.selector.entity_names
		end,
		context_values = function(context)
			local entity = context.payload.entity
			return { entity and (entity.ghost_name or entity.name) }
		end,
	},
	{
		reason = "source",
		rule_values = function(rule)
			return rule.selector.sources
		end,
		context_values = function(context)
			return { context.payload.source }
		end,
	},
	{
		reason = "surface",
		rule_values = function(rule)
			return rule.scope.surfaces
		end,
		context_values = function(context)
			return reference_values(context.surface)
		end,
	},
	{
		reason = "force",
		rule_values = function(rule)
			return rule.scope.forces
		end,
		context_values = function(context)
			return reference_values(context.force)
		end,
	},
}

local function key(value)
	return type(value) .. ":" .. tostring(value)
end

local function terms(values)
	local result = {}
	for _, value in ipairs(values or {}) do
		result[#result + 1] = key(value)
	end
	return result
end

local function overlaps(left, right)
	local expected = {}
	for _, value in ipairs(left) do
		expected[value] = true
	end
	for _, value in ipairs(right) do
		if expected[value] then
			return true
		end
	end
	return false
end

function M.dimension_count()
	return #DIMENSIONS
end

function M.rule_terms(rule)
	local result = {}
	for index, dimension in ipairs(DIMENSIONS) do
		result[index] = terms(dimension.rule_values(rule))
	end
	return result
end

function M.context_terms(context)
	local result = {}
	for index, dimension in ipairs(DIMENSIONS) do
		result[index] = terms(dimension.context_values(context))
	end
	return result
end

function M.matches(rule, context)
	if Event.key(rule.event) ~= Event.key(context) then
		return false, "event"
	end
	local rule_terms = M.rule_terms(rule)
	local context_terms = M.context_terms(context)
	for index, dimension in ipairs(DIMENSIONS) do
		if #rule_terms[index] > 0 and not overlaps(rule_terms[index], context_terms[index]) then
			return false, dimension.reason
		end
	end
	return true, nil
end

return M
