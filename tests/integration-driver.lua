-- Factorio cannot raise GUI/player-build events; invoke the mod's registered handlers in tests.
remote.add_interface("factorio_rules_test", {
	dispatch = function(name, event)
		local handler = assert(script.get_event_handler(assert(defines.events[name])))
		event.name = defines.events[name]
		event.tick = game.tick
		return handler(event)
	end,
})
