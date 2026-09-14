local Extensions = require("runtime.extensions")
local Evaluator = require("lib.rules.evaluator")

return {
	{
		name = "binds providers through validated data descriptors",
		run = function()
			local extensions = Extensions.new({
				resolve = function(descriptor, kind)
					assert(descriptor.interface == "test-provider" and kind == "predicate")
					return function(_context, condition)
						return condition.value == 42
					end
				end,
			})
			assert(
				extensions:register_predicate_provider(
					"test:provider",
					{ interface = "test-provider", function_name = "matches" }
				)
			)
			assert(extensions:predicates()["test:provider"]({}, { value = 42 }, {}))
		end,
	},
	{
		name = "registers namespaced predicates with constrained services",
		run = function()
			local extensions = Extensions.new()
			local seen
			assert(
				extensions:register_predicate(
					"test:positive",
					function(context, condition, services)
						seen = { context = context, condition = condition, services = services }
						return services.answer == 42
					end
				)
			)
			local evaluator = Evaluator.new(extensions:predicates())
			local result = assert(evaluator:evaluate({
				{
					id = "test:rule",
					priority = 1,
					enabled = true,
					event = { domain = "test", kind = "event" },
					selector = {},
					scope = {},
					when = { predicate = "test:positive" },
					effects = { primary = { type = "deny", reason = "denied" }, actions = {} },
				},
			}, {
				domain = "test",
				kind = "event",
				surface = {},
				force = {},
				payload = { entity = { type = "test" } },
			}, { services = { answer = 42 } }))
			assert(result.outcome == "deny" and seen.services.answer == 42)
		end,
	},
	{
		name = "rejects duplicate and unnamespaced extension contracts",
		run = function()
			local extensions = Extensions.new()
			local ok = pcall(function()
				extensions:register_predicate("plain", function() end)
			end)
			assert(not ok)
			assert(extensions:register_action("test:action", function() end))
			ok = pcall(function()
				extensions:register_action("test:action", function() end)
			end)
			assert(not ok)
		end,
	},
}
