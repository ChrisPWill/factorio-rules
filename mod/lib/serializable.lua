local M = {}

local function add_error(errors, path, message)
	errors[#errors + 1] = path .. ": " .. message
end

local function is_array_index(value)
	return type(value) == "number" and value >= 1 and value % 1 == 0
end

local function copy_value(value, path, errors, ancestors, strict_collections)
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
	for key, child in pairs(value) do
		if is_array_index(key) then
			has_numeric = true
			numeric_keys[#numeric_keys + 1] = key
		elseif type(key) == "string" then
			has_string = true
		else
			add_error(errors, path, "keys must be strings or positive array indexes")
		end
		if type(key) == "string" or is_array_index(key) then
			local child_path = type(key) == "number" and (path .. "[" .. key .. "]")
				or (path .. "." .. key)
			result[key] = copy_value(child, child_path, errors, ancestors, strict_collections)
		end
	end

	if strict_collections and has_numeric and has_string then
		add_error(errors, path, "must not mix array indexes and string keys")
	elseif strict_collections and has_numeric then
		table.sort(numeric_keys)
		for index, key in ipairs(numeric_keys) do
			if key ~= index then
				add_error(errors, path, "array indexes must be contiguous from 1")
				break
			end
		end
	end
	ancestors[value] = nil
	return result
end

function M.copy(value, path, options)
	local errors = {}
	local result = copy_value(
		value,
		path or "value",
		errors,
		{},
		options and options.strict_collections or false
	)
	return result, errors
end

return M
