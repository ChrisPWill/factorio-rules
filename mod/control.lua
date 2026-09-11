local state = require("runtime.state")
local logger = require("runtime.logger")
local AdapterRegistry = require("runtime.adapters.registry")
local ConstructionAdapters = require("runtime.adapters.construction")
local Compiler = require("lib.rules.compiler")
local Evaluator = require("lib.rules.evaluator")
local Construction = require("runtime.construction")
local Rollback = require("runtime.rollback")
local Feedback = require("runtime.feedback")

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
	logger.debug("Initialized persistent state")
end)

script.on_configuration_changed(function()
	state.initialize()
	logger.debug("Configuration updated")
end)
