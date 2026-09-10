local M = {}

M.CURRENT_SCHEMA_VERSION = 1

local function add_error(errors, path, message)
	errors[#errors + 1] = path .. ": " .. message
end

local function is_positive_integer(value)
	return type(value) == "number" and value >= 1 and value % 1 == 0
end

local function copy_data(value, path, errors, ancestors)
	local value_type = type(value)
	if value_type == "string" or value_type == "boolean" or value == nil then
		return value
	end
	if value_type == "number" then
		if value ~= value or value == math.huge or value == -math.huge then
			add_error(errors, path, "number must be finite")
			return nil
		end
		return value
	end
	if value_type ~= "table" then
		add_error(errors, path, "must contain only serializable data, got " .. value_type)
		return nil
	end
	if ancestors[value] then
		add_error(errors, path, "must not contain cyclic tables")
		return nil
	end

	ancestors[value] = true
	local result = {}
	local numeric_keys = {}
	local has_numeric, has_string = false, false
	for key in pairs(value) do
		if type(key) == "number" and is_positive_integer(key) then
			has_numeric = true
			numeric_keys[#numeric_keys + 1] = key
		elseif type(key) == "string" then
			has_string = true
		else
			add_error(errors, path, "keys must be strings or positive array indexes")
		end
	end
	if has_numeric and has_string then
		add_error(errors, path, "must not mix array indexes and string keys")
	elseif has_numeric then
		table.sort(numeric_keys)
		for index, key in ipairs(numeric_keys) do
			if key ~= index then
				add_error(errors, path, "array indexes must be contiguous from 1")
				break
			end
		end
	end
	for key, child in pairs(value) do
		local child_path = type(key) == "number" and (path .. "[" .. key .. "]")
			or (path .. "." .. tostring(key))
		result[key] = copy_data(child, child_path, errors, ancestors)
	end
	ancestors[value] = nil
	return result
end

local function require_string(value, path, errors)
	if type(value) ~= "string" or value == "" then
		add_error(errors, path, "must be a nonempty string")
		return false
	end
	return true
end

local function validate_condition(condition, path, errors)
	if type(condition) ~= "table" then
		add_error(errors, path, "must be a condition table")
		return
	end
	local variants = 0
	for _, key in ipairs({ "all", "any", "not", "predicate" }) do
		if condition[key] ~= nil then
			variants = variants + 1
		end
	end
	if variants ~= 1 then
		add_error(errors, path, "must define exactly one of all, any, not, or predicate")
		return
	end
	if condition.all ~= nil or condition.any ~= nil then
		local key = condition.all ~= nil and "all" or "any"
		local children = condition[key]
		if type(children) ~= "table" or #children == 0 then
			add_error(errors, path .. "." .. key, "must be a nonempty array")
			return
		end
		for index, child in ipairs(children) do
			validate_condition(child, path .. "." .. key .. "[" .. index .. "]", errors)
		end
	elseif condition["not"] ~= nil then
		validate_condition(condition["not"], path .. ".not", errors)
	else
		require_string(condition.predicate, path .. ".predicate", errors)
	end
end

local function validate_effects(effects, errors)
	if type(effects) ~= "table" then
		add_error(errors, "rule.effects", "must be a table")
		return
	end
	local primary = effects.primary
	if type(primary) ~= "table" then
		add_error(errors, "rule.effects.primary", "must be a table")
	else
		if primary.type ~= "deny" and primary.type ~= "warn" then
			add_error(errors, "rule.effects.primary.type", "must be deny or warn")
		end
		require_string(primary.reason, "rule.effects.primary.reason", errors)
	end
	if type(effects.actions) ~= "table" then
		add_error(errors, "rule.effects.actions", "must be an array")
		return
	end
	for index, action in ipairs(effects.actions) do
		local path = "rule.effects.actions[" .. index .. "]"
		if type(action) ~= "table" then
			add_error(errors, path, "must be a table")
		else
			require_string(action.type, path .. ".type", errors)
		end
	end
end

function M.normalize(input)
	local errors = {}
	local rule = copy_data(input, "rule", errors, {})
	if type(rule) ~= "table" then
		return nil, errors
	end

	if rule.schema_version ~= M.CURRENT_SCHEMA_VERSION then
		add_error(
			errors,
			"rule.schema_version",
			"must be supported version " .. M.CURRENT_SCHEMA_VERSION
		)
	end
	if not is_positive_integer(rule.definition_version) then
		add_error(errors, "rule.definition_version", "must be a positive integer")
	end
	if
		not require_string(rule.id, "rule.id", errors) or not rule.id:match("^[%w_-]+:[%w_.-]+$")
	then
		if type(rule.id) == "string" and rule.id ~= "" then
			add_error(errors, "rule.id", "must use the namespace:rule-name format")
		end
	end
	if rule.enabled == nil then
		rule.enabled = true
	elseif type(rule.enabled) ~= "boolean" then
		add_error(errors, "rule.enabled", "must be a boolean")
	end
	if rule.priority == nil then
		rule.priority = 0
	elseif type(rule.priority) ~= "number" or rule.priority % 1 ~= 0 then
		add_error(errors, "rule.priority", "must be an integer")
	end

	if type(rule.provenance) ~= "table" then
		add_error(errors, "rule.provenance", "must be a table")
	else
		require_string(rule.provenance.source, "rule.provenance.source", errors)
		require_string(rule.provenance.kind, "rule.provenance.kind", errors)
	end
	if type(rule.event) ~= "table" then
		add_error(errors, "rule.event", "must be a table")
	else
		require_string(rule.event.domain, "rule.event.domain", errors)
		require_string(rule.event.kind, "rule.event.kind", errors)
	end
	if type(rule.selector) ~= "table" then
		add_error(errors, "rule.selector", "must be a data table")
	end
	if type(rule.scope) ~= "table" then
		add_error(errors, "rule.scope", "must be a data table")
	end

	if rule.when == nil and rule.unless == nil then
		add_error(errors, "rule.when", "must define when or unless")
	elseif rule.unless ~= nil then
		if rule.when == nil then
			rule.when = { ["not"] = rule.unless }
		else
			rule.when = { all = { rule.when, { ["not"] = rule.unless } } }
		end
		rule.unless = nil
	end
	if rule.when ~= nil then
		validate_condition(rule.when, "rule.when", errors)
	end

	rule.effects = rule.effects or {}
	rule.effects.actions = rule.effects.actions or {}
	validate_effects(rule.effects, errors)

	if #errors > 0 then
		return nil, errors
	end
	return rule, nil
end

return M
