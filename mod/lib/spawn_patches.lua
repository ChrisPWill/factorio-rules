local M = {}

local function window_key(surface, force)
	return surface.index .. ":" .. force.index
end

local function cell_key(surface_index, resource_name, position)
	return table.concat({
		surface_index,
		resource_name,
		math.floor(position.x),
		math.floor(position.y),
	}, ":")
end

local function get_window(state, surface, force)
	return state.windows[window_key(surface, force)]
end

function M.new(state, tracker)
	assert(type(state) == "table" and type(state.windows) == "table")
	assert(type(tracker) == "table", "resource patch tracker is required")
	local classifier = {}

	function classifier.open(_self, surface, force)
		local key = window_key(surface, force)
		local existing = state.windows[key]
		if existing and existing.status == "closed" then
			return nil, "spawn classification is already frozen"
		end
		state.windows[key] = existing
			or { status = "open", patch_ids = {}, fluid_patch_ids = {}, cells = {} }
		return true, nil
	end

	function classifier.observe(_self, surface, force, patch_ids)
		local window = get_window(state, surface, force)
		if not window or window.status ~= "open" then
			return nil, "spawn discovery window is not open"
		end
		for _, id in ipairs(patch_ids) do
			local patch = tracker:patch(id)
			if not patch then
				return nil, "unknown resource patch " .. tostring(id)
			end
			if patch.surface_index ~= surface.index then
				return nil, "resource patch is on a different surface"
			end
			if patch.kind == "fluid" then
				window.fluid_patch_ids[patch.id] = true
			else
				window.patch_ids[patch.id] = true
			end
		end
		return true, nil
	end

	function classifier.close(_self, surface, force)
		local window = get_window(state, surface, force)
		if not window or window.status ~= "open" then
			return nil, "spawn discovery window is not open"
		end
		for id in pairs(window.patch_ids) do
			for _, member in ipairs(tracker:members(id)) do
				window.cells[cell_key(member.surface_index, member.resource_name, member)] = true
			end
		end
		window.status = "closed"
		local solid_count, fluid_count = 0, 0
		for _ in pairs(window.patch_ids) do
			solid_count = solid_count + 1
		end
		for _ in pairs(window.fluid_patch_ids) do
			fluid_count = fluid_count + 1
		end
		return { solid_patches = solid_count, excluded_fluid_patches = fluid_count }, nil
	end

	function classifier.is_spawn_resource(_self, surface, force, resource)
		local window = get_window(state, surface, force)
		if not window or window.status ~= "closed" then
			return nil, "spawn classification is not complete"
		end
		if resource.kind == "fluid" then
			return false, "fluid resources are excluded from spawn-patch classification"
		end
		return not not window.cells[cell_key(surface.index, resource.name, resource.position)], nil
	end

	function classifier.status(_self, surface, force)
		local window = get_window(state, surface, force)
		return window and window.status or "unclassified"
	end

	return classifier
end

return M
