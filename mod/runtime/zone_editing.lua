local M = {}
M.SHORTCUT_NAME = "factorio-rules-select-zone"
M.TOOL_NAME = "factorio-rules-zone-selector"

function M.new(options)
	assert(type(options) == "table", "zone editor options are required")
	local editor = {}
	local editing = {}

	function editor.begin(_self, player_index, zone_id)
		local player = options.get_player(player_index)
		if not player or not player.cursor_stack then
			return nil, "player cursor unavailable"
		end
		if zone_id and (not options.get or not options.get(zone_id)) then
			return nil, "unknown zone"
		end
		editing[player_index] = zone_id
		player.cursor_stack.set_stack({ name = M.TOOL_NAME })
		return true, nil
	end

	function editor.select(_self, event)
		if event.item ~= M.TOOL_NAME then
			return false
		end
		local area = event.area
		local player = options.get_player(event.player_index)
		if not player or not area then
			return nil, "selection context unavailable"
		end
		local surface = player.surface
		local force = player.force
		local center = {
			x = (area.left_top.x + area.right_bottom.x) / 2,
			y = (area.left_top.y + area.right_bottom.y) / 2,
		}
		local width = math.max(1, area.right_bottom.x - area.left_top.x)
		local height = math.max(1, area.right_bottom.y - area.left_top.y)
		local zone_id = editing[event.player_index]
		local previous = zone_id and options.get(zone_id)
		if zone_id and not previous then
			return nil, "zone no longer exists"
		end
		if
			previous
			and (
				previous.scope.surfaces[1] ~= surface.name
				or previous.scope.forces[1] ~= force.name
			)
		then
			return nil, "edit must stay on the same surface and force"
		end
		zone_id = zone_id or (options.next_id and options.next_id())
		local saved, errors = options.save({
			name = previous and previous.name,
			id = zone_id,
			shape = { type = "rectangle", width = width, height = height },
			anchor = { type = "absolute", position = center },
			scope = { surfaces = { surface.name }, forces = { force.name } },
		})
		if not saved then
			return nil, errors
		end
		editing[event.player_index] = nil
		if player.cursor_stack.valid_for_read then
			player.cursor_stack.clear()
		end
		options.rebuild()
		return true, nil
	end

	function editor.delete_unused(_self)
		return options.delete_unused()
	end

	return editor
end

return M
