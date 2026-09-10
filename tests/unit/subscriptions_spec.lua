local Subscriptions = require("runtime.subscriptions")

local function event(domain, kind)
	return { domain = domain, kind = kind }
end

return {
	{
		name = "registers only required events with filters",
		run = function()
			local registered, received = {}, {}
			local manager = Subscriptions.new({
				events = {
					["construction\0entity-built"] = {
						filters = { { filter = "name", name = "electric-mining-drill" } },
						register = function(handler, filters)
							registered[#registered + 1] = handler
							received = filters
							return #registered
						end,
						unregister = function() end,
					},
				},
			})
			local handler = function() end
			assert(manager:rebuild({ event("construction", "entity-built") }, handler))
			assert(#registered == 1 and received[1].name == "electric-mining-drill")
			assert(#manager:active_events() == 1)
		end,
	},
	{
		name = "rebuilds dynamic subscriptions and leaves low frequency ones",
		run = function()
			local registrations, unregistrations = 0, 0
			local manager = Subscriptions.new({
				events = {
					["construction\0entity-built"] = {
						filters = { "one" },
						dynamic = true,
						register = function()
							registrations = registrations + 1
						end,
						unregister = function()
							unregistrations = unregistrations + 1
						end,
					},
					["runtime\0tick"] = {
						dynamic = false,
						register = function()
							registrations = registrations + 1
						end,
						unregister = function()
							unregistrations = unregistrations + 1
						end,
					},
				},
			})
			assert(
				manager:rebuild(
					{ event("construction", "entity-built"), event("runtime", "tick") },
					function() end
				)
			)
			assert(manager:rebuild({ event("construction", "entity-built") }, function() end))
			assert(registrations == 2 and unregistrations == 0)
			assert(
				manager:rebuild({ event("construction", "entity-built") }, function() end) == false
			)
		end,
	},
	{
		name = "rejects unavailable subscriptions before changing them",
		run = function()
			local registrations = 0
			local manager = Subscriptions.new({
				events = {
					["construction\0entity-built"] = {
						register = function()
							registrations = registrations + 1
						end,
						unregister = function() end,
					},
				},
			})
			assert(manager:rebuild({ event("construction", "entity-built") }, function() end))
			local ok, errors = manager:rebuild({ event("missing", "event") }, function() end)
			assert(ok == nil and #errors == 1 and registrations == 1)
		end,
	},
}
