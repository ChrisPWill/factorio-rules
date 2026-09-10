local M = {}
local NIL = {}

local function add_error(errors, path, message)
	errors[#errors + 1] = path .. ": " .. message
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
	for key, child in pairs(value) do
		if type(key) ~= "string" and (type(key) ~= "number" or key < 1 or key % 1 ~= 0) then
			add_error(errors, path, "keys must be strings or positive array indexes")
		else
			local child_path = type(key) == "number" and (path .. "[" .. key .. "]")
				or (path .. "." .. key)
			result[key] = copy_data(child, child_path, errors, ancestors)
		end
	end
	ancestors[value] = nil
	return result
end

local function require_string(value, path, errors)
	if type(value) ~= "string" or value == "" then
		add_error(errors, path, "must be a nonempty string")
	end
end

local function validate_reference(value, path, errors, required)
	if value == nil and not required then
		return
	end
	if type(value) ~= "table" then
		add_error(errors, path, "must be a normalized reference")
		return
	end
	if type(value.index) ~= "number" or value.index < 1 or value.index % 1 ~= 0 then
		add_error(errors, path .. ".index", "must be a positive integer")
	end
	if value.name ~= nil then
		require_string(value.name, path .. ".name", errors)
	end
end

function M.new(spec)
	if type(spec) ~= "table" then
		return nil, { "context: must be a table" }
	end

	local errors = {}
	local common = copy_data({
		domain = spec.domain,
		kind = spec.kind,
		surface = spec.surface,
		force = spec.force,
		actor = spec.actor,
		metadata = spec.metadata or {},
	}, "context", errors, {})
	local payload = copy_data(spec.payload or {}, "context.payload", errors, {})

	require_string(common.domain, "context.domain", errors)
	require_string(common.kind, "context.kind", errors)
	validate_reference(common.surface, "context.surface", errors, true)
	validate_reference(common.force, "context.force", errors, false)
	if common.actor ~= nil then
		if type(common.actor) ~= "table" then
			add_error(errors, "context.actor", "must be a normalized actor")
		else
			require_string(common.actor.kind, "context.actor.kind", errors)
		end
	end
	if spec.capabilities ~= nil and type(spec.capabilities) ~= "table" then
		add_error(errors, "context.capabilities", "must be a capability resolver")
	elseif spec.capabilities and type(spec.capabilities.resolve) ~= "function" then
		add_error(errors, "context.capabilities.resolve", "must be a function")
	end
	if #errors > 0 then
		return nil, errors
	end

	local capability_cache = {}
	local context = {
		domain = common.domain,
		kind = common.kind,
		surface = common.surface,
		force = common.force,
		actor = common.actor,
		metadata = common.metadata,
		payload = payload,
	}

	function context:get_capability(name)
		assert(type(name) == "string" and name ~= "", "capability name must be a nonempty string")
		local cached = capability_cache[name]
		if cached ~= nil then
			return cached == NIL and nil or cached
		end
		if not spec.capabilities then
			return nil
		end
		local value = spec.capabilities:resolve(name, self)
		capability_cache[name] = value == nil and NIL or value
		return value
	end

	return context, nil
end

return M
