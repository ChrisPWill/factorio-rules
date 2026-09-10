local M = {}

local SOURCE_PRIORITY = {
	["native-query"] = 1,
	["native-statistics"] = 2,
	tracker = 3,
}

local function choose_provider(providers)
	local selected
	for _, provider in pairs(providers or {}) do
		if not selected or SOURCE_PRIORITY[provider.source] < SOURCE_PRIORITY[selected.source] then
			selected = provider
		end
	end
	return selected
end

local function requirement_set(requirements)
	local desired = {}
	local errors = {}
	for _, name in ipairs(requirements or {}) do
		if type(name) ~= "string" or name == "" then
			errors[#errors + 1] = "capability requirements must be nonempty strings"
		else
			desired[name] = true
		end
	end
	return desired, errors
end

function M.new()
	local providers = {}
	local active = {}
	local resolver = {}

	function resolver.register(_self, name, provider)
		assert(type(name) == "string" and name ~= "", "capability name must be nonempty")
		assert(type(provider) == "table", "provider must be a table")
		assert(
			SOURCE_PRIORITY[provider.source],
			"unknown provider source " .. tostring(provider.source)
		)
		assert(type(provider.resolve) == "function", "provider resolve must be a function")
		if provider.source == "tracker" then
			assert(type(provider.activate) == "function", "tracker activate must be a function")
			assert(type(provider.deactivate) == "function", "tracker deactivate must be a function")
		end

		local registered = providers[name]
		if not registered then
			registered = {}
			providers[name] = registered
		end
		assert(
			not registered[provider.source],
			name .. " already has a " .. provider.source .. " provider"
		)
		registered[provider.source] = provider
	end

	function resolver.apply_requirements(_self, requirements)
		local desired, errors = requirement_set(requirements)
		local selected = {}
		for name in pairs(desired) do
			selected[name] = choose_provider(providers[name])
			if not selected[name] then
				errors[#errors + 1] = "capability " .. name .. " has no provider"
			end
		end
		if #errors > 0 then
			return nil, errors
		end

		for name, provider in pairs(active) do
			if provider ~= selected[name] and provider.source == "tracker" then
				provider.deactivate()
			end
		end
		for name, provider in pairs(selected) do
			if provider ~= active[name] and provider.source == "tracker" then
				provider.activate()
			end
		end
		active = selected
		return true, nil
	end

	function resolver.resolve(_self, name, context)
		local provider = active[name]
		return provider and provider.resolve(context) or nil
	end

	function resolver.provider_source(_self, name)
		local provider = active[name]
		return provider and provider.source or nil
	end

	return resolver
end

local function copy_filter(filter)
	local result = {}
	for key, value in pairs(filter or {}) do
		result[key] = value
	end
	return result
end

function M.entity_count_provider(factorio, filter)
	assert(type(factorio) == "table" and type(factorio.get_surface) == "function")
	return {
		source = "native-query",
		resolve = function(context)
			local surface =
				assert(factorio.get_surface(context.surface.index), "surface unavailable")
			local query = copy_filter(filter)
			if query.force == nil and context.force then
				query.force = context.force.name or context.force.index
			end
			return surface:count_entities_filtered(query)
		end,
	}
end

function M.production_total_provider(factorio, options)
	assert(type(factorio) == "table" and type(factorio.get_statistics) == "function")
	assert(type(options) == "table" and type(options.name) == "string")
	assert(options.direction == "input" or options.direction == "output")
	local method = "get_" .. options.direction .. "_count"
	return {
		source = "native-statistics",
		resolve = function(context)
			local statistics = assert(factorio.get_statistics(context), "statistics unavailable")
			return statistics[method](statistics, options.name, options.quality)
		end,
	}
end

return M
