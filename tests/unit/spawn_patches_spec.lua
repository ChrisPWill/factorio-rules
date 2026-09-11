local ResourcePatches = require("lib.resource_patches")
local SpawnPatches = require("lib.spawn_patches")

local surface = { index = 1, name = "nauvis" }
local player = { index = 1, name = "player" }

local function resource(name, x, y, kind)
	return {
		name = name,
		surface_index = surface.index,
		position = { x = x, y = y },
		kind = kind or "solid",
		amount = 100,
	}
end

local function setup(persisted)
	persisted = persisted
		or {
			patches = { next_id = 1, patches = {}, cells = {}, aliases = {} },
			spawn = { windows = {} },
		}
	local tracker = ResourcePatches.new(persisted.patches)
	return tracker, SpawnPatches.new(persisted.spawn, tracker), persisted
end

return {
	{
		name = "freezes cells discovered during the initial window",
		run = function()
			local tracker, classifier = setup()
			tracker:ingest({ resource("iron-ore", 0, 0), resource("iron-ore", 1, 0) })
			local id = tracker:patch_for(1, "iron-ore", { x = 0, y = 0 })
			assert(classifier:open(surface, player))
			assert(classifier:observe(surface, player, { id }))
			local report = assert(classifier:close(surface, player))
			assert(report.solid_patches == 1)
			assert(classifier:is_spawn_resource(surface, player, resource("iron-ore", 1, 0)))

			tracker:ingest({ resource("iron-ore", 2, 0) })
			assert(not classifier:is_spawn_resource(surface, player, resource("iron-ore", 2, 0)))
		end,
	},
	{
		name = "does not reclassify a later connected deposit",
		run = function()
			local tracker, classifier = setup()
			tracker:ingest({ resource("copper-ore", 0, 0) })
			local spawn_id = tracker:patch_for(1, "copper-ore", { x = 0, y = 0 })
			assert(classifier:open(surface, player))
			assert(classifier:observe(surface, player, { spawn_id }))
			assert(classifier:close(surface, player))

			tracker:ingest({ resource("copper-ore", 2, 0), resource("copper-ore", 1, 0) })
			assert(tracker:patch_for(1, "copper-ore", { x = 2, y = 0 }) == spawn_id)
			assert(not classifier:is_spawn_resource(surface, player, resource("copper-ore", 2, 0)))
		end,
	},
	{
		name = "answers mining-area overlap from the frozen position cache",
		run = function()
			local tracker, classifier = setup()
			tracker:ingest({ resource("iron-ore", 4, 5) })
			local id = tracker:patch_for(1, "iron-ore", { x = 4, y = 5 })
			assert(classifier:open(surface, player))
			assert(classifier:observe(surface, player, { id }))
			assert(classifier:close(surface, player))
			assert(classifier:has_spawn_resource(surface, player, {
				left_top = { x = 3.5, y = 4.5 },
				right_bottom = { x = 5.5, y = 6.5 },
			}))
			assert(classifier:has_resource_name(surface, player, "iron-ore"))
			assert(not classifier:has_resource_name(surface, player, "coal"))
			assert(not classifier:has_spawn_resource(surface, player, {
				left_top = { x = 10, y = 10 },
				right_bottom = { x = 13, y = 13 },
			}))
		end,
	},
	{
		name = "classifies independently for each force",
		run = function()
			local tracker, classifier = setup()
			tracker:ingest({ resource("coal", 0, 0) })
			local id = tracker:patch_for(1, "coal", { x = 0, y = 0 })
			assert(classifier:open(surface, player))
			assert(classifier:observe(surface, player, { id }))
			assert(classifier:close(surface, player))
			local enemy = { index = 2, name = "enemy" }
			assert(classifier:open(surface, enemy))
			assert(classifier:close(surface, enemy))
			assert(classifier:is_spawn_resource(surface, player, resource("coal", 0, 0)))
			assert(not classifier:is_spawn_resource(surface, enemy, resource("coal", 0, 0)))
		end,
	},
	{
		name = "excludes fluid patches explicitly",
		run = function()
			local tracker, classifier = setup()
			tracker:ingest({ resource("crude-oil", 0, 0, "fluid") })
			local id = tracker:patch_for(1, "crude-oil", { x = 0, y = 0 })
			assert(classifier:open(surface, player))
			assert(classifier:observe(surface, player, { id }))
			local report = assert(classifier:close(surface, player))
			assert(report.excluded_fluid_patches == 1)
			local matched, reason =
				classifier:is_spawn_resource(surface, player, resource("crude-oil", 0, 0, "fluid"))
			assert(not matched and reason:find("excluded", 1, true))
		end,
	},
	{
		name = "persists frozen classification across reconstruction",
		run = function()
			local tracker, classifier, persisted = setup()
			tracker:ingest({ resource("stone", 3, 4) })
			local id = tracker:patch_for(1, "stone", { x = 3, y = 4 })
			assert(classifier:open(surface, player))
			assert(classifier:observe(surface, player, { id }))
			assert(classifier:close(surface, player))
			classifier = select(2, setup(persisted))
			assert(classifier.status(classifier, surface, player) == "closed")
			assert(classifier:is_spawn_resource(surface, player, resource("stone", 3, 4)))
		end,
	},
	{
		name = "reports incomplete and immutable classifications",
		run = function()
			local _, classifier = setup()
			local matched, err =
				classifier:is_spawn_resource(surface, player, resource("iron-ore", 0, 0))
			assert(matched == nil and err:find("not complete", 1, true))
			assert(classifier:open(surface, player))
			assert(classifier:close(surface, player))
			local reopened, reopen_error = classifier:open(surface, player)
			assert(reopened == nil and reopen_error:find("frozen", 1, true))
		end,
	},
}
