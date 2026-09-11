local serializable = require("lib.serializable")

local M = {}

local function namespaced(name, kind)
	assert(
		type(name) == "string" and name:match("^[%w_-]+:[%w_.-]+$"),
		kind .. " name must use the namespace:name format"
	)
end

local function requirements(value)
	local copied, errors =
		serializable.copy(value or {}, "requirements", { strict_collections = true })
	assert(#errors == 0, table.concat(errors, "; "))
	return copied
end

function M.new()
	local predicates, actions = {}, {}
	local predicate_requirements, action_requirements = {}, {}
	local extensions = {}

	function extensions.register_predicate(_self, name, callback, requirement)
		namespaced(name, "predicate")
		assert(type(callback) == "function", "predicate callback is required")
		assert(not predicates[name], "predicate already registered: " .. name)
		predicates[name] = callback
		predicate_requirements[name] = requirements(requirement)
		return true, nil
	end

	function extensions.register_action(_self, name, callback, requirement)
		namespaced(name, "action")
		assert(type(callback) == "function", "action callback is required")
		assert(not actions[name], "action already registered: " .. name)
		actions[name] = callback
		action_requirements[name] = requirements(requirement)
		return true, nil
	end

	function extensions.predicates(_self)
		return predicates
	end

	function extensions.predicate_requirements(_self)
		return predicate_requirements
	end

	function extensions.action_requirements(_self)
		return action_requirements
	end

	function extensions.actions(_self)
		return actions
	end

	return extensions
end

return M
