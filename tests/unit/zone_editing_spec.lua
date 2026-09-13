local ZoneEditing = require("runtime.zone_editing")
local Store = require("runtime.zone_store")

return {
	{
		name = "rejects zone edits when authorization fails",
		run = function()
			local editor = ZoneEditing.new({
				get_player = function()
					return { cursor_stack = {} }
				end,
				authorize = function()
					return false, "only an admin can edit rules"
				end,
			})
			local ok, error_message = editor:begin(2)
			assert(not ok and error_message == "only an admin can edit rules")
		end,
	},
	{
		name = "redraw preserves zone identity and rejects a different surface",
		run = function()
			local store = Store.new({ zones = {} })
			local id = assert(store:save({
				name = "Home",
				shape = { type = "circle", radius = 4 },
				anchor = { type = "absolute", position = { x = 0, y = 0 } },
				scope = { surfaces = { "nauvis" }, forces = { "player" } },
			}))
			local player = {
				surface = { name = "nauvis" },
				force = { name = "player" },
				cursor_stack = { set_stack = function() end, clear = function() end },
			}
			local editor = ZoneEditing.new({
				get_player = function()
					return player
				end,
				get = function(key)
					return store:get(key)
				end,
				save = function(zone)
					return store:save(zone)
				end,
				rebuild = function() end,
			})
			assert(editor:begin(1, id))
			local event = {
				item = ZoneEditing.TOOL_NAME,
				player_index = 1,
				area = { left_top = { x = 2, y = 2 }, right_bottom = { x = 8, y = 8 } },
			}
			player.surface.name = "other"
			assert(not editor:select(event))
			player.surface.name = "nauvis"
			assert(editor:select(event))
			assert(
				#store.list() == 1
					and store:get(id).name == "Home"
					and store:get(id).shape.width == 6
			)
		end,
	},
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
