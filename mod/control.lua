local state = require("runtime.state")
local logger = require("runtime.logger")
local AdapterRegistry = require("runtime.adapters.registry")
local ConstructionAdapters = require("runtime.adapters.construction")
local Compiler = require("lib.rules.compiler")
local Evaluator = require("lib.rules.evaluator")
local Construction = require("runtime.construction")
local Rollback = require("runtime.rollback")
local Feedback = require("runtime.feedback")
local Overlays = require("runtime.overlays")

local adapters = AdapterRegistry.new()
ConstructionAdapters.register(adapters)
local compiler = Compiler.new()
local rollback = Rollback.factorio({
	get_player = function(index)
		return game.get_player(index)
	end,
	get_surface = function(index)
		return game.get_surface(index)
	end,
}, defines)
local feedback = Feedback.factorio({
	history = function()
		return storage.violations
	end,
	history_limit = function()
		return settings.global["factorio-rules-violation-history-limit"].value
	end,
	get_player = function(index)
		return game.get_player(index)
	end,
	get_force = function(index)
		return game.forces[index]
	end,
})
local overlays = Overlays.factorio({
	state = function()
		return storage.overlays
	end,
	player_indices = function()
		local result = {}
		for _, player in pairs(game.players) do
			result[#result + 1] = player.index
		end
		return result
	end,
	is_admin = function(index)
		local player = game.get_player(index)
		return player and player.admin
	end,
	set_shortcut = function(index, toggled)
		local player = game.get_player(index)
		if player then
			player.set_shortcut_toggled(Overlays.SHORTCUT_NAME, toggled)
		end
	end,
}, rendering)
local enforcer = Construction.new({
	adapters = adapters,
	compiler = compiler,
	evaluator = Evaluator.new({}),
	record = function(result)
		storage.last_enforcement = result
	end,
	feedback = function(result, context, boundary)
		feedback:emit(result, context, boundary)
	end,
	reject = function(boundary, _, context)
		local _, errors = rollback:apply(boundary, context)
		if errors then
			error(table.concat(errors, "; "))
		end
	end,
})
Construction.register_construction_events(script, defines, enforcer)
remote.add_interface(
	"factorio_rules",
	Construction.cooperative_interface(enforcer, function()
		return game.tick
	end)
)

script.on_init(function()
	state.initialize()
	overlays:replace({})
	logger.debug("Initialized persistent state")
end)

script.on_configuration_changed(function()
	state.initialize()
	overlays:replace({})
	logger.debug("Configuration updated")
end)

script.on_event(defines.events.on_lua_shortcut, function(event)
	if event.prototype_name == Overlays.SHORTCUT_NAME then
		overlays:toggle(event.player_index)
	end
end)

script.on_event(defines.events.on_player_joined_game, function(event)
	overlays:sync_player(event.player_index)
end)
