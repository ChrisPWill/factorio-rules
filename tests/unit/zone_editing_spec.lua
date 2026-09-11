local ZoneEditing = require("runtime.zone_editing")

return {
	{
		name = "converts a world selection into a scoped persisted rectangle",
		run = function()
			local stack
			stack = {
				valid_for_read = true,
				set_stack = function(value)
					stack.value = value
				end,
				clear = function()
					stack.value = nil
				end,
			}
			local player =
				{ cursor_stack = stack, surface = { name = "nauvis" }, force = { name = "player" } }
			local saved, rebuilt = nil, 0
			local editor = ZoneEditing.new({
				get_player = function()
					return player
				end,
				next_id = function()
					return "test:zone"
				end,
				save = function(zone)
					saved = zone
					return true
				end,
				rebuild = function()
					rebuilt = rebuilt + 1
				end,
			})
			assert(editor:begin(1))
			assert(stack.value.name == ZoneEditing.TOOL_NAME)
			assert(editor:select({
				item = ZoneEditing.TOOL_NAME,
				player_index = 1,
				area = { left_top = { x = 2, y = 4 }, right_bottom = { x = 10, y = 16 } },
			}))
			assert(saved.shape.width == 8 and saved.shape.height == 12)
			assert(saved.anchor.position.x == 6 and saved.anchor.position.y == 10)
			assert(saved.scope.surfaces[1] == "nauvis" and saved.scope.forces[1] == "player")
			assert(rebuilt == 1 and stack.value == nil)
		end,
	},
}
