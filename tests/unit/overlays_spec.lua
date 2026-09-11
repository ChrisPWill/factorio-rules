local Overlays = require("runtime.overlays")

local function setup(players)
	local state = { players = {}, forced = {}, entries = {}, objects = {} }
	local draws, updates, destroyed, shortcuts = 0, {}, 0, {}
	local overlays = Overlays.new({
		state = function()
			return state
		end,
		player_indices = function()
			local result = {}
			for _, index in ipairs(players) do
				result[#result + 1] = index
			end
			return result
		end,
		is_admin = function(index)
			return index == 1
		end,
		set_shortcut = function(index, toggled)
			shortcuts[index] = toggled
		end,
		draw = function()
			draws = draws + 1
			return { valid = true, id = draws }
		end,
		set_audience = function(object, audience)
			updates[object.id] = audience
		end,
		valid = function(object)
			return object.valid
		end,
		destroy = function(object)
			object.valid = false
			destroyed = destroyed + 1
		end,
	})
	return overlays, state, updates, shortcuts, function()
		return draws, destroyed
	end
end

local function entry(overrides)
	local result = {
		key = "test:zone@1",
		zone_id = "test:zone",
		rule_ids = { "test:rule" },
		shape = { type = "circle", radius = 10 },
		center = { x = 0, y = 0 },
		surface = { index = 1, name = "nauvis" },
	}
	for key, value in pairs(overrides or {}) do
		result[key] = value
	end
	return result
end

return {
	{
		name = "keeps multiplayer visibility preferences independent",
		run = function()
			local overlays, _, updates, shortcuts = setup({ 2, 1 })
			assert(overlays:replace({ entry() }))
			assert(#updates[1] == 0)
			assert(overlays:toggle(1))
			assert(#updates[1] == 1 and updates[1][1] == 1)
			assert(overlays:toggle(2))
			assert(#updates[1] == 2 and updates[1][2] == 2)
			overlays:set_rule_visible(1, "test:rule", false)
			assert(#updates[1] == 1 and updates[1][1] == 2)
			assert(shortcuts[1] and shortcuts[2])
		end,
	},
	{
		name = "reuses unchanged rendering objects",
		run = function()
			local overlays, _, _, _, counts = setup({ 1 })
			assert(overlays:replace({ entry() }))
			assert(overlays:replace({ entry() }))
			local draws, destroyed = counts()
			assert(draws == 1 and destroyed == 0)
			assert(overlays:replace({ entry({
				shape = { type = "circle", radius = 20 },
			}) }))
			draws, destroyed = counts()
			assert(draws == 2 and destroyed == 1)
		end,
	},
	{
		name = "supports explicit rule and admin forced visibility",
		run = function()
			local overlays, _, updates = setup({ 1, 2 })
			assert(overlays:replace({ entry({ forced = true }) }))
			assert(#updates[1] == 2)
			assert(overlays:replace({ entry() }))
			local ok, err = overlays:set_forced(2, "test:zone", true)
			assert(ok == nil and err:find("admin", 1, true))
			assert(overlays:set_forced(1, "test:zone", true))
			assert(#updates[1] == 2)
		end,
	},
	{
		name = "draws circles and rectangles on their resolved surfaces",
		run = function()
			local circles, rectangles = {}, {}
			local state = { players = {}, forced = {}, entries = {}, objects = {} }
			local overlays = Overlays.factorio({
				state = function()
					return state
				end,
				player_indices = function()
					return {}
				end,
			}, {
				draw_circle = function(parameters)
					circles[#circles + 1] = parameters
					return { valid = true }
				end,
				draw_rectangle = function(parameters)
					rectangles[#rectangles + 1] = parameters
					return { valid = true }
				end,
			})
			assert(overlays:replace({
				entry(),
				entry({
					key = "test:rectangle@2",
					shape = { type = "rectangle", width = 4, height = 6 },
					center = { x = 10, y = 20 },
					surface = { index = 2, name = "vulcanus" },
				}),
			}))
			assert(circles[1].surface == 1 and circles[1].radius == 10)
			assert(rectangles[1].surface == 2)
			assert(rectangles[1].left_top.x == 8 and rectangles[1].right_bottom.y == 23)
		end,
	},
}
