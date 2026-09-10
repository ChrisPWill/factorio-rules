local Capabilities = require("runtime.capabilities")

local function contains(values, expected)
	for _, value in ipairs(values or {}) do
		if value == expected then
			return true
		end
	end
	return false
end

return {
	{
		name = "prefers native query then statistics over a tracker",
		run = function()
			local activations = 0
			local resolver = Capabilities.new()
			resolver:register("entity-count", {
				source = "tracker",
				resolve = function()
					return 30
				end,
				activate = function()
					activations = activations + 1
				end,
				deactivate = function() end,
			})
			resolver:register("entity-count", {
				source = "native-statistics",
				resolve = function()
					return 20
				end,
			})
			resolver:register("entity-count", {
				source = "native-query",
				resolve = function()
					return 10
				end,
			})
			resolver:register("production-total", {
				source = "tracker",
				resolve = function()
					return 31
				end,
				activate = function()
					activations = activations + 1
				end,
				deactivate = function() end,
			})
			resolver:register("production-total", {
				source = "native-statistics",
				resolve = function()
					return 21
				end,
			})

			assert(resolver:apply_requirements({ "entity-count", "production-total" }))
			assert(resolver:provider_source("entity-count") == "native-query")
			assert(resolver:provider_source("production-total") == "native-statistics")
			assert(resolver:resolve("entity-count", {}) == 10)
			assert(resolver:resolve("production-total", {}) == 21)
			assert(activations == 0)
		end,
	},
	{
		name = "activates trackers only while demanded",
		run = function()
			local activations, deactivations = 0, 0
			local resolver = Capabilities.new()
			resolver:register("tracked-total", {
				source = "tracker",
				resolve = function()
					return 7
				end,
				activate = function()
					activations = activations + 1
				end,
				deactivate = function()
					deactivations = deactivations + 1
				end,
			})

			assert(resolver:apply_requirements({ "tracked-total" }))
			assert(resolver:apply_requirements({ "tracked-total" }))
			assert(activations == 1 and deactivations == 0)
			assert(resolver:resolve("tracked-total", {}) == 7)

			assert(resolver:apply_requirements({}))
			assert(activations == 1 and deactivations == 1)
			assert(resolver:resolve("tracked-total", {}) == nil)
		end,
	},
	{
		name = "rejects unavailable requirements without changing demand",
		run = function()
			local resolver = Capabilities.new()
			resolver:register("available", {
				source = "native-query",
				resolve = function()
					return true
				end,
			})
			assert(resolver:apply_requirements({ "available" }))
			local ok, errors = resolver:apply_requirements({ "missing" })
			assert(ok == nil and contains(errors, "capability missing has no provider"))
			assert(resolver:resolve("available", {}) == true)
		end,
	},
	{
		name = "counts entities with the native surface query",
		run = function()
			local received
			local surface = {
				count_entities_filtered = function(_, filter)
					received = filter
					return 12
				end,
			}
			local provider = Capabilities.entity_count_provider({
				get_surface = function(index)
					assert(index == 4)
					return surface
				end,
			}, { type = "mining-drill" })
			local value = provider.resolve({
				surface = { index = 4 },
				force = { index = 2, name = "player" },
			})
			assert(provider.source == "native-query" and value == 12)
			assert(received.type == "mining-drill" and received.force == "player")
		end,
	},
	{
		name = "reads production totals from Factorio statistics",
		run = function()
			local statistics = {
				get_output_count = function(_, name)
					assert(name == "iron-plate")
					return 99
				end,
			}
			local provider = Capabilities.production_total_provider({
				get_statistics = function(context)
					assert(context.force.index == 2)
					return statistics
				end,
			}, { name = "iron-plate", direction = "output" })
			local value = provider.resolve({ force = { index = 2 } })
			assert(provider.source == "native-statistics" and value == 99)
		end,
	},
}
