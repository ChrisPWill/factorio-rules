local serializable = require("lib.serializable")

local M = {}
M.SHORTCUT_NAME = "factorio-rules-toggle-zones"

local function sorted_player_indices(options)
	local result = options.player_indices()
	table.sort(result)
	return result
end

local function visible_for(entry, state, player_index)
	if entry.forced or state.forced[entry.zone_id] then
		return true
	end
	local preference = state.players[player_index]
	if not preference or not preference.visible then
		return false
	end
	if not entry.rule_ids or #entry.rule_ids == 0 then
		return true
	end
	for _, rule_id in ipairs(entry.rule_ids) do
		if not preference.hidden_rules[rule_id] then
			return true
		end
	end
	return false
end

local function audience(entry, state, options)
	local result = {}
	for _, player_index in ipairs(sorted_player_indices(options)) do
		if visible_for(entry, state, player_index) then
			result[#result + 1] = player_index
		end
	end
	return result
end

local function fingerprint(entry)
	local shape = entry.shape
	return table.concat({
		entry.zone_id,
		entry.surface.index or entry.surface.name,
		entry.center.x,
		entry.center.y,
		shape.type,
		shape.radius or shape.width,
		shape.height or "",
	}, ":")
end

function M.new(options)
	assert(type(options) == "table", "overlay options must be a table")
	assert(type(options.state) == "function", "overlay state provider is required")
	assert(type(options.draw) == "function", "overlay draw function is required")
	assert(type(options.set_audience) == "function", "overlay audience function is required")
	assert(type(options.destroy) == "function", "overlay destroy function is required")
	assert(type(options.player_indices) == "function", "overlay player provider is required")
	local overlays = {}

	local function sync_entry(entry, record, state)
		options.set_audience(record.object, audience(entry, state, options))
	end

	function overlays.sync()
		local state = options.state()
		for key, entry in pairs(state.entries) do
			local record = state.objects[key]
			if record and options.valid(record.object) then
				sync_entry(entry, record, state)
			end
		end
	end

	function overlays.replace(_self, entries)
		local copied, errors = serializable.copy(entries, "overlays", { strict_collections = true })
		if #errors > 0 then
			return nil, errors
		end
		local state = options.state()
		local next_entries = {}
		for _, entry in ipairs(copied) do
			assert(type(entry.key) == "string" and entry.key ~= "", "overlay key is required")
			next_entries[entry.key] = entry
		end
		for key, record in pairs(state.objects) do
			if not next_entries[key] or record.fingerprint ~= fingerprint(next_entries[key]) then
				if options.valid(record.object) then
					options.destroy(record.object)
				end
				state.objects[key] = nil
			end
		end
		state.entries = next_entries
		for key, entry in pairs(next_entries) do
			local record = state.objects[key]
			if not record or not options.valid(record.object) then
				record = { fingerprint = fingerprint(entry), object = options.draw(entry) }
				state.objects[key] = record
			end
			sync_entry(entry, record, state)
		end
		return true, nil
	end

	function overlays.toggle(_self, player_index)
		local state = options.state()
		local preference = state.players[player_index]
		if not preference then
			preference = { visible = false, hidden_rules = {} }
			state.players[player_index] = preference
		end
		preference.visible = not preference.visible
		if options.set_shortcut then
			options.set_shortcut(player_index, preference.visible)
		end
		overlays.sync()
		return preference.visible
	end

	function overlays.set_rule_visible(_self, player_index, rule_id, visible)
		local state = options.state()
		local preference = state.players[player_index]
		if not preference then
			preference = { visible = false, hidden_rules = {} }
			state.players[player_index] = preference
		end
		preference.hidden_rules[rule_id] = visible and nil or true
		overlays.sync()
	end

	function overlays.set_forced(_self, player_index, zone_id, forced)
		if not options.is_admin or not options.is_admin(player_index) then
			return nil, "only an admin can force overlay visibility"
		end
		local state = options.state()
		state.forced[zone_id] = forced and true or nil
		overlays.sync()
		return true, nil
	end

	function overlays.sync_player(_self, player_index)
		local preference = options.state().players[player_index]
		if options.set_shortcut then
			options.set_shortcut(player_index, preference and preference.visible or false)
		end
		overlays.sync()
	end

	return overlays
end

function M.factorio(options, rendering_api)
	return M.new({
		state = options.state,
		player_indices = options.player_indices,
		is_admin = options.is_admin,
		set_shortcut = options.set_shortcut,
		valid = function(object)
			return object.valid
		end,
		destroy = function(object)
			object.destroy()
		end,
		set_audience = function(object, players)
			object.visible = #players > 0
			if #players > 0 then
				object.players = players
			end
		end,
		draw = function(entry)
			local parameters = {
				color = entry.color or { r = 1, g = 0.2, b = 0.2, a = 0.65 },
				width = entry.width or 2,
				filled = false,
				surface = entry.surface.index or entry.surface.name,
				visible = false,
				draw_on_ground = true,
			}
			if entry.shape.type == "circle" then
				parameters.radius = entry.shape.radius
				parameters.target = entry.center
				return rendering_api.draw_circle(parameters)
			end
			parameters.left_top = {
				x = entry.center.x - entry.shape.width / 2,
				y = entry.center.y - entry.shape.height / 2,
			}
			parameters.right_bottom = {
				x = entry.center.x + entry.shape.width / 2,
				y = entry.center.y + entry.shape.height / 2,
			}
			return rendering_api.draw_rectangle(parameters)
		end,
	})
end

return M
