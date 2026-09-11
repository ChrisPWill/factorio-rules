local Zones = require("lib.zones")

local function context(surface, force)
	return {
		surface = surface or { index = 1, name = "nauvis" },
		force = force or { index = 2, name = "player" },
	}
end

return {
	{
		name = "deletes only unreferenced custom zones",
		run = function()
			local kept, removed = Zones.delete_unused({
				{ id = "test:used" },
				{ id = "test:unused" },
			}, { { zone_ids = { "test:used" } } })
			assert(#kept == 1 and kept[1].id == "test:used")
			assert(#removed == 1 and removed[1] == "test:unused")
		end,
	},
	{
		name = "checks circle boundaries with squared distance",
		run = function()
			local zones = assert(Zones.new({
				{
					id = "test:circle",
					shape = { type = "circle", radius = 5 },
					anchor = { type = "absolute", position = { x = 10, y = 20 } },
				},
			}))
			assert(zones:contains("test:circle", context(), { x = 13, y = 24 }))
			assert(not zones:contains("test:circle", context(), { x = 13, y = 24.1 }))
		end,
	},
	{
		name = "checks centered rectangle boundaries",
		run = function()
			local zones = assert(Zones.new({
				{
					id = "test:rectangle",
					shape = { type = "rectangle", width = 4, height = 6 },
					anchor = { type = "absolute", position = { x = 10, y = 20 } },
				},
			}))
			assert(zones:contains("test:rectangle", context(), { x = 12, y = 23 }))
			assert(not zones:contains("test:rectangle", context(), { x = 12.1, y = 23 }))
		end,
	},
	{
		name = "resolves force-spawn anchors only inside zone scope",
		run = function()
			local calls = 0
			local zones = assert(Zones.new({
				{
					id = "test:spawn",
					shape = { type = "circle", radius = 10 },
					anchor = { type = "force-spawn" },
					scope = { surfaces = { "nauvis" }, forces = { 2 } },
				},
			}, {
				force_spawn = function(surface, force)
					calls = calls + 1
					assert(surface.name == "nauvis" and force.index == 2)
					return { x = 5, y = 5 }
				end,
			}))
			assert(zones:contains("test:spawn", context(), { x = 5, y = 5 }))
			assert(
				not zones:contains(
					"test:spawn",
					context(nil, { index = 3, name = "enemy" }),
					{ x = 5, y = 5 }
				)
			)
			assert(calls == 1)
		end,
	},
	{
		name = "keeps reusable definitions independent from caller mutation",
		run = function()
			local definitions = {
				{
					id = "test:stable",
					shape = { type = "circle", radius = 3 },
					anchor = { type = "absolute", position = { x = 0, y = 0 } },
				},
			}
			local zones = assert(Zones.new(definitions))
			definitions[1].shape.radius = 100
			local listed = zones.list()
			listed[1].shape.radius = 200
			assert(not zones:contains("test:stable", context(), { x = 4, y = 0 }))
		end,
	},
	{
		name = "rejects duplicate IDs and invalid geometry",
		run = function()
			local zones, errors = Zones.new({
				{
					id = "test:duplicate",
					shape = { type = "circle", radius = 0 },
					anchor = { type = "absolute", position = { x = 0, y = 0 } },
				},
				{
					id = "test:duplicate",
					shape = { type = "triangle" },
					anchor = { type = "planet" },
				},
			})
			assert(zones == nil and #errors == 4)
		end,
	},
	{
		name = "rejects keyed definition and scope collections",
		run = function()
			local zones, errors = Zones.new({
				invalid = {
					id = "test:keyed",
					shape = { type = "circle", radius = 1 },
					anchor = { type = "absolute", position = { x = 0, y = 0 } },
				},
			})
			assert(zones == nil and #errors == 1)
			zones, errors = Zones.new({
				{
					id = "test:keyed-scope",
					shape = { type = "circle", radius = 1 },
					anchor = { type = "absolute", position = { x = 0, y = 0 } },
					scope = { surfaces = { nauvis = true } },
				},
			})
			assert(zones == nil and #errors == 1)
		end,
	},
}
