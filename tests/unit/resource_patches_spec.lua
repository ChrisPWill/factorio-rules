local ResourcePatches = require("lib.resource_patches")

local function state()
	return { next_id = 1, patches = {}, cells = {}, aliases = {} }
end

local function resource(name, x, y, kind, amount)
	return {
		name = name,
		surface_index = 1,
		position = { x = x, y = y },
		kind = kind or "solid",
		amount = amount or 100,
	}
end

return {
	{
		name = "groups adjacent solid resources consistently",
		run = function()
			local tracker = ResourcePatches.new(state())
			tracker:ingest({
				resource("iron-ore", 1, 1),
				resource("iron-ore", 0, 0),
				resource("iron-ore", 5, 5),
			})
			local first = tracker:patch_for(1, "iron-ore", { x = 0, y = 0 })
			assert(first == tracker:patch_for(1, "iron-ore", { x = 1, y = 1 }))
			assert(first ~= tracker:patch_for(1, "iron-ore", { x = 5, y = 5 }))
			local patch = tracker:patch(first)
			assert(patch.size == 2 and patch.total_amount == 200)
		end,
	},
	{
		name = "merges chunk continuations through cached neighbor cells",
		run = function()
			local persisted = state()
			local tracker = ResourcePatches.new(persisted)
			tracker:ingest({ resource("copper-ore", 0, 0), resource("copper-ore", 2, 0) })
			local first = tracker:patch_for(1, "copper-ore", { x = 0, y = 0 })
			local second = tracker:patch_for(1, "copper-ore", { x = 2, y = 0 })
			assert(first ~= second)
			tracker:ingest({ resource("copper-ore", 1, 0) })
			assert(tracker:patch_for(1, "copper-ore", { x = 2, y = 0 }) == first)
			assert(tracker:patch(second).id == first, "merged IDs should remain resolvable")
			assert(#tracker:all() == 1 and tracker:patch(first).size == 3)
		end,
	},
	{
		name = "preserves patch identity across tracker reconstruction",
		run = function()
			local persisted = state()
			local tracker = ResourcePatches.new(persisted)
			tracker:ingest({ resource("coal", -1, -1) })
			local id = tracker:patch_for(1, "coal", { x = -1, y = -1 })
			tracker = ResourcePatches.new(persisted)
			tracker:ingest({ resource("coal", -1, -1) })
			assert(tracker:patch_for(1, "coal", { x = -1, y = -1 }) == id)
			assert(tracker:patch(id).size == 1)
		end,
	},
	{
		name = "keeps resource names and surfaces separate",
		run = function()
			local tracker = ResourcePatches.new(state())
			local other_surface = resource("iron-ore", 0, 0)
			other_surface.surface_index = 2
			tracker:ingest({
				resource("iron-ore", 0, 0),
				resource("copper-ore", 0, 0),
				other_surface,
			})
			assert(#tracker:all() == 3)
		end,
	},
	{
		name = "treats each fluid resource entity as its own patch",
		run = function()
			local tracker = ResourcePatches.new(state())
			tracker:ingest({
				resource("crude-oil", 0, 0, "fluid"),
				resource("crude-oil", 1, 0, "fluid"),
			})
			local left = tracker:patch_for(1, "crude-oil", { x = 0, y = 0 })
			local right = tracker:patch_for(1, "crude-oil", { x = 1, y = 0 })
			assert(left ~= right and #tracker:all() == 2)
			assert(tracker:patch(left).kind == "fluid")
		end,
	},
}
