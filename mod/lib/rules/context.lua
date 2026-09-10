local serializable = require("lib.serializable")

local M = {}
local NIL = {}

local function add_error(errors, path, message)
	errors[#errors + 1] = path .. ": " .. message
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

	local common, errors = serializable.copy({
		domain = spec.domain,
		kind = spec.kind,
		surface = spec.surface,
		force = spec.force,
		actor = spec.actor,
		metadata = spec.metadata or {},
	}, "context")
	local payload, payload_errors = serializable.copy(spec.payload or {}, "context.payload")
	for _, message in ipairs(payload_errors) do
		errors[#errors + 1] = message
	end

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

	local capabilities = spec.capabilities
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
		if not capabilities then
			return nil
		end
		local value = capabilities:resolve(name, self)
		capability_cache[name] = value == nil and NIL or value
		return value
	end

	return context, nil
end

return M
