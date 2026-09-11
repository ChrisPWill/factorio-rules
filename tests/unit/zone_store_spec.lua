local Store = require("runtime.zone_store")
local Zones = require("lib.zones")
return {
	{
		name = "zone identities survive redraw deletion and reconstruction",
		run = function()
			local state = { zones = {} }
			local store = Store.new(state)
			local id = assert(store:save({
				shape = { type = "circle", radius = 4 },
				anchor = { type = "absolute", position = { x = 0, y = 0 } },
			}))
			local zone = store:get(id)
			zone.shape.radius = 9
			zone.name = "Home"
			assert(store:save(zone) == id)
			assert(#state.zones == 1 and Store.new(state):get(id).name == "Home")
			state.zones = {}
			zone.id = nil
			assert(Store.new(state):save(zone) ~= id)
		end,
	},
	{
		name = "cleanup protects nested disabled and restorable references",
		run = function()
			local kept, removed = Zones.delete_unused(
				{ { id = "test:a" }, { id = "test:b" }, { id = "test:c" } },
				{
					sources = {
						test = {
							rules = {
								one = {
									enabled = false,
									when = {
										["not"] = {
											predicate = "factorio-rules:inside-zone",
											zone_id = "test:a",
										},
									},
								},
							},
						},
					},
					overrides = { missing = { zone_ids = { "test:b" } } },
				}
			)
			assert(#kept == 2 and #removed == 1 and removed[1] == "test:c")
		end,
	},
}
