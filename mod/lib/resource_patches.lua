local M = {}

local NEIGHBORS = {
	{ -1, -1 },
	{ 0, -1 },
	{ 1, -1 },
	{ -1, 0 },
	{ 1, 0 },
	{ -1, 1 },
	{ 0, 1 },
	{ 1, 1 },
}

local function coordinate(value)
	return math.floor(value)
end

local function cell_key(surface_index, resource_name, x, y)
	return table.concat({ surface_index, resource_name, x, y }, ":")
end

local function resolve_id(state, id)
	while state.aliases[id] do
		id = state.aliases[id]
	end
	return id
end

local function extend_bounds(bounds, x, y)
	bounds.left = math.min(bounds.left, x)
	bounds.right = math.max(bounds.right, x)
	bounds.top = math.min(bounds.top, y)
	bounds.bottom = math.max(bounds.bottom, y)
end

local function new_patch(state, resource)
	local sequence = state.next_id
	state.next_id = sequence + 1
	local id = "patch-" .. sequence
	local x, y = coordinate(resource.position.x), coordinate(resource.position.y)
	local patch = {
		id = id,
		sequence = sequence,
		resource_name = resource.name,
		kind = resource.kind,
		surface_index = resource.surface_index,
		size = 0,
		total_amount = 0,
		bounds = { left = x, right = x, top = y, bottom = y },
		cells = {},
	}
	state.patches[id] = patch
	return patch
end

local function add_resource(state, patch, resource)
	local x, y = coordinate(resource.position.x), coordinate(resource.position.y)
	local key = cell_key(resource.surface_index, resource.name, x, y)
	if patch.cells[key] then
		return
	end
	patch.cells[key] = true
	state.cells[key] = patch.id
	patch.size = patch.size + 1
	patch.total_amount = patch.total_amount + (resource.amount or 0)
	extend_bounds(patch.bounds, x, y)
end

local function merge(state, target, source)
	if target.id == source.id then
		return target
	end
	for key in pairs(source.cells) do
		target.cells[key] = true
		state.cells[key] = target.id
	end
	target.size = target.size + source.size
	target.total_amount = target.total_amount + source.total_amount
	extend_bounds(target.bounds, source.bounds.left, source.bounds.top)
	extend_bounds(target.bounds, source.bounds.right, source.bounds.bottom)
	state.aliases[source.id] = target.id
	state.patches[source.id] = nil
	return target
end

local function adjacent_patches(state, resource)
	local ids, seen = {}, {}
	local x, y = coordinate(resource.position.x), coordinate(resource.position.y)
	for _, offset in ipairs(NEIGHBORS) do
		local key = cell_key(resource.surface_index, resource.name, x + offset[1], y + offset[2])
		local id = state.cells[key]
		if id then
			id = resolve_id(state, id)
			if not seen[id] then
				seen[id] = true
				ids[#ids + 1] = id
			end
		end
	end
	table.sort(ids, function(left, right)
		return state.patches[left].sequence < state.patches[right].sequence
	end)
	return ids
end

local function snapshot(patch)
	return {
		id = patch.id,
		resource_name = patch.resource_name,
		kind = patch.kind,
		surface_index = patch.surface_index,
		size = patch.size,
		total_amount = patch.total_amount,
		bounds = {
			left = patch.bounds.left,
			right = patch.bounds.right,
			top = patch.bounds.top,
			bottom = patch.bounds.bottom,
		},
	}
end

function M.new(state)
	assert(type(state) == "table", "resource patch state is required")
	assert(type(state.next_id) == "number", "resource patch next ID is required")
	assert(type(state.patches) == "table", "resource patches are required")
	assert(type(state.cells) == "table", "resource patch cells are required")
	assert(type(state.aliases) == "table", "resource patch aliases are required")
	local tracker = {}

	function tracker.ingest(_self, resources)
		local ordered = {}
		for _, resource in ipairs(resources) do
			assert(type(resource.name) == "string", "resource name is required")
			assert(type(resource.surface_index) == "number", "resource surface is required")
			assert(type(resource.position) == "table", "resource position is required")
			assert(resource.kind == "solid" or resource.kind == "fluid", "resource kind is invalid")
			ordered[#ordered + 1] = resource
		end
		table.sort(ordered, function(left, right)
			if left.surface_index ~= right.surface_index then
				return left.surface_index < right.surface_index
			end
			if left.name ~= right.name then
				return left.name < right.name
			end
			if left.position.y ~= right.position.y then
				return left.position.y < right.position.y
			end
			return left.position.x < right.position.x
		end)

		local discovered = {}
		for _, resource in ipairs(ordered) do
			local x, y = coordinate(resource.position.x), coordinate(resource.position.y)
			local key = cell_key(resource.surface_index, resource.name, x, y)
			local existing = state.cells[key]
			local patch
			if existing then
				patch = state.patches[resolve_id(state, existing)]
			elseif resource.kind == "fluid" then
				patch = new_patch(state, resource)
				add_resource(state, patch, resource)
			else
				local adjacent = adjacent_patches(state, resource)
				patch = #adjacent > 0 and state.patches[adjacent[1]] or new_patch(state, resource)
				for index = 2, #adjacent do
					merge(state, patch, state.patches[adjacent[index]])
				end
				add_resource(state, patch, resource)
			end
			discovered[#discovered + 1] = { key = key, patch_id = patch.id }
		end
		return discovered
	end

	function tracker.patch(_self, id)
		local patch = state.patches[resolve_id(state, id)]
		return patch and snapshot(patch) or nil
	end

	function tracker.patch_for(_self, surface_index, resource_name, position)
		local key =
			cell_key(surface_index, resource_name, coordinate(position.x), coordinate(position.y))
		local id = state.cells[key]
		return id and resolve_id(state, id) or nil
	end

	function tracker.all()
		local result = {}
		for _, patch in pairs(state.patches) do
			result[#result + 1] = snapshot(patch)
		end
		table.sort(result, function(left, right)
			return left.id < right.id
		end)
		return result
	end

	return tracker
end

return M
