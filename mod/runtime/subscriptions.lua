local Event = require("lib.rules.event")

local M = {}

local function deep_equal(left, right)
	if left == right then
		return true
	end
	if type(left) ~= "table" or type(right) ~= "table" then
		return false
	end
	for key, value in pairs(left) do
		if not deep_equal(value, right[key]) then
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

local function sorted_events(events)
	local result = {}
	for _, event in ipairs(events or {}) do
		result[#result + 1] = { domain = event.domain, kind = event.kind }
	end
	table.sort(result, function(left, right)
		return Event.key(left) < Event.key(right)
	end)
	return result
end

function M.new(options)
	options = options or {}
	local definitions = options.events or {}
	local active = {}
	local configuration
	local revision = 0
	local manager = {}

	local function definition_for(event)
		return definitions[Event.key(event)]
	end

	function manager.rebuild(_self, requirements, handler)
		local events = sorted_events(requirements)
		local next_configuration = {}
		local errors = {}
		for _, event in ipairs(events) do
			local key = Event.key(event)
			local definition = definition_for(event)
			if not definition or definition.available == false then
				errors[#errors + 1] = "event " .. key:gsub("\0", "/") .. " has no subscription"
			else
				local filters = definition.filters
				if type(filters) == "function" then
					filters = filters(event)
				end
				next_configuration[key] = {
					event = event,
					filters = filters,
					dynamic = definition.dynamic ~= false,
				}
			end
		end
		if #errors > 0 then
			return nil, errors
		end
		if configuration and deep_equal(configuration, next_configuration) then
			return false
		end

		for key, registration in pairs(active) do
			if registration.dynamic and not next_configuration[key] then
				registration.definition.unregister(registration.token)
				active[key] = nil
			end
		end
		for key, registration in pairs(next_configuration) do
			local existing = active[key]
			if
				not existing
				or existing.dynamic and not deep_equal(existing.filters, registration.filters)
			then
				if existing and existing.dynamic then
					existing.definition.unregister(existing.token)
				end
				local definition = definition_for(registration.event)
				local token = definition.register(handler, registration.filters)
				active[key] = {
					definition = definition,
					event = registration.event,
					token = token,
					dynamic = registration.dynamic,
					filters = registration.filters,
				}
			end
		end
		configuration = next_configuration
		revision = revision + 1
		return true
	end

	function manager.revision(_self)
		return revision
	end

	function manager.active_events(_self)
		local result = {}
		for _, registration in pairs(active) do
			result[#result + 1] = registration.event
		end
		table.sort(result, function(left, right)
			return Event.key(left) < Event.key(right)
		end)
		return result
	end

	return manager
end

return M
