local ResourceDiscovery = require("runtime.resource_discovery")

local function state()
	return {
		queue = {},
		head = 1,
		queued = {},
		processed = {},
		active = false,
		validation_pending = false,
		validation_warnings = {},
	}
end

local function job(x)
	return {
		surface_index = 1,
		chunk = { x = x, y = 0 },
		area = { left_top = { x = x * 32, y = 0 }, right_bottom = { x = x * 32 + 32, y = 32 } },
	}
end

local function setup(overrides)
	local persisted = state()
	local scans, ingested, activations, warnings, resets = {}, {}, {}, {}, 0
	local patches = overrides and overrides.patches or {}
	local discovery = ResourceDiscovery.new({
		state = function()
			return persisted
		end,
		scan = function(queued)
			scans[#scans + 1] = queued.chunk.x
			return { { name = "iron-ore", chunk = queued.chunk.x } }
		end,
		ingest = function(resources)
			ingested[#ingested + 1] = resources[1].chunk
			return { { patch_id = "patch-" .. resources[1].chunk } }
		end,
		patch_for = function(_, name)
			return name == "iron-ore" and "cached" or nil
		end,
		all_patches = function()
			return patches
		end,
		expected_resources = function()
			return { { surface_index = 1, names = { "iron-ore", "coal" } } }
		end,
		warn = function(message)
			warnings[#warnings + 1] = message
		end,
		set_active = function(active)
			activations[#activations + 1] = active
		end,
		reset_cache = function()
			resets = resets + 1
			patches = {}
		end,
	})
	return discovery,
		persisted,
		scans,
		ingested,
		activations,
		warnings,
		function()
			return resets
		end
end

return {
	{
		name = "processes queued chunks within a fixed budget and becomes idle",
		run = function()
			local discovery, _, scans, ingested, activations = setup()
			for x = 1, 3 do
				assert(discovery:enqueue(job(x)))
			end
			assert(not discovery:enqueue(job(1)), "duplicate chunk should not queue")
			local count, remaining = discovery:process(2)
			assert(count == 2 and remaining and #scans == 2 and #ingested == 2)
			count, remaining = discovery:process(2)
			assert(count == 1 and not remaining and #scans == 3)
			assert(activations[1] == true and activations[2] == false)
		end,
	},
	{
		name = "serves placement lookups without scanning",
		run = function()
			local discovery, _, scans = setup()
			assert(discovery:cached_patch_for(1, "iron-ore", { x = 0, y = 0 }) == "cached")
			assert(#scans == 0)
		end,
	},
	{
		name = "warns for configurable missing expectations without fabricating patches",
		run = function()
			local discovery, _, _, _, _, warnings = setup({
				patches = { { surface_index = 1, resource_name = "iron-ore" } },
			})
			discovery:seed({})
			assert(#warnings == 1 and warnings[1]:find("coal", 1, true))
			assert(discovery:cached_patch_for(1, "coal", { x = 0, y = 0 }) == nil)
		end,
	},
	{
		name = "explicit rebuild invalidates cache and requeues generated chunks",
		run = function()
			local discovery, persisted, scans, _, _, _, reset_count = setup()
			assert(discovery:enqueue(job(1)))
			assert(discovery:process(1))
			assert(persisted.processed["1:1:0"])
			discovery:rebuild({ job(1), job(2) })
			assert(reset_count() == 1 and persisted.processed["1:1:0"] == nil)
			discovery:process(2)
			assert(#scans == 3)
		end,
	},
	{
		name = "normalizes solid and fluid Factorio resources",
		run = function()
			local scanner = ResourceDiscovery.factorio_scanner(function(index)
				assert(index == 1)
				return {
					index = 1,
					find_entities_filtered = function(query)
						assert(query.type == "resource")
						return {
							{
								name = "iron-ore",
								position = { x = 0, y = 0 },
								amount = 100,
								prototype = { resource_category = "basic-solid" },
							},
							{
								name = "crude-oil",
								position = { x = 1, y = 0 },
								amount = 1000,
								prototype = { resource_category = "basic-fluid" },
							},
						}
					end,
				}
			end)
			local resources = scanner(job(0))
			assert(resources[1].kind == "solid" and resources[2].kind == "fluid")
		end,
	},
}
