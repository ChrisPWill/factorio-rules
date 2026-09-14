local M = {}

local function chunk_key(job)
	return table.concat({ job.surface_index, job.chunk.x, job.chunk.y }, ":")
end

local function has_work(state)
	return state.head <= #state.queue
end

local function set_active(options, state, active)
	if state.active == active then
		return
	end
	state.active = active
	options.set_active(active)
end

local function validate_expected(options)
	local available = {}
	if not options.has_expected_resource then
		for _, patch in ipairs(options.all_patches()) do
			available[patch.surface_index .. ":" .. patch.resource_name] = true
		end
	end
	local warnings = {}
	for _, expectation in ipairs(options.expected_resources()) do
		for _, resource_name in ipairs(expectation.names) do
			local found = options.has_expected_resource
					and options.has_expected_resource(expectation, resource_name)
				or available[expectation.surface_index .. ":" .. resource_name]
			if not found then
				local message = string.format(
					"expected spawn resource %s was not discovered on surface %d",
					resource_name,
					expectation.surface_index
				)
				warnings[#warnings + 1] = message
				options.warn(message)
			end
		end
	end
	return warnings
end

function M.new(options)
	assert(type(options) == "table", "resource discovery options must be a table")
	assert(type(options.state) == "function", "resource discovery state is required")
	assert(type(options.scan) == "function", "resource chunk scanner is required")
	assert(type(options.ingest) == "function", "resource patch ingestion is required")
	assert(type(options.set_active) == "function", "resource discovery activation is required")
	local discovery = {}

	local function finish_if_idle(state)
		if has_work(state) then
			return
		end
		state.queue, state.head, state.queued = {}, 1, {}
		set_active(options, state, false)
		if state.validation_pending then
			if options.on_idle then
				options.on_idle()
			end
			state.validation_warnings = validate_expected(options)
			state.validation_pending = false
		end
	end

	function discovery.enqueue(_self, job)
		local state = options.state()
		local key = chunk_key(job)
		if state.processed[key] or state.queued[key] then
			return false
		end
		state.queue[#state.queue + 1] = job
		state.queued[key] = true
		set_active(options, state, true)
		return true
	end

	function discovery.seed(_self, jobs)
		local state = options.state()
		state.validation_pending = true
		for _, job in ipairs(jobs) do
			discovery:enqueue(job)
		end
		finish_if_idle(state)
	end

	function discovery.process(_self, budget)
		assert(type(budget) == "number" and budget >= 1 and budget % 1 == 0)
		local state = options.state()
		local processed = 0
		while processed < budget and has_work(state) do
			local job = state.queue[state.head]
			state.queue[state.head] = false
			state.head = state.head + 1
			local key = chunk_key(job)
			state.queued[key] = nil
			local resources = options.scan(job)
			local discovered = options.ingest(resources)
			if options.on_discovered then
				options.on_discovered(job, discovered)
			end
			state.processed[key] = true
			processed = processed + 1
		end
		finish_if_idle(state)
		return processed, has_work(state)
	end

	function discovery.cached_patch_for(_self, surface_index, resource_name, position)
		return options.patch_for(surface_index, resource_name, position)
	end

	function discovery.rebuild(_self, jobs)
		options.reset_cache()
		local state = options.state()
		state.queue = {}
		state.head = 1
		state.queued = {}
		state.processed = {}
		state.validation_warnings = {}
		state.validation_pending = true
		for _, job in ipairs(jobs) do
			discovery:enqueue(job)
		end
		finish_if_idle(state)
	end

	function discovery.resume()
		local state = options.state()
		-- Event subscriptions are not retained across a Factorio load, while the
		-- persisted active flag is. Re-register from queued work without writing it.
		options.set_active(has_work(state))
	end

	return discovery
end

function M.factorio_scanner(get_surface)
	return function(job)
		local surface = assert(get_surface(job.surface_index), "resource surface unavailable")
		local resources = {}
		for _, entity in
			ipairs(surface.find_entities_filtered({ area = job.area, type = "resource" }))
		do
			resources[#resources + 1] = {
				name = entity.name,
				surface_index = surface.index,
				position = { x = entity.position.x, y = entity.position.y },
				amount = entity.amount,
				kind = entity.prototype.resource_category == "basic-fluid" and "fluid" or "solid",
			}
		end
		return resources
	end
end

return M
