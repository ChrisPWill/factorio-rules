local state = require("runtime.state")
local logger = require("runtime.logger")
local AdapterRegistry = require("runtime.adapters.registry")
local ConstructionAdapters = require("runtime.adapters.construction")
local Compiler = require("lib.rules.compiler")
local Evaluator = require("lib.rules.evaluator")
local Construction = require("runtime.construction")

local adapters = AdapterRegistry.new()
ConstructionAdapters.register(adapters)
local compiler = Compiler.new()
local enforcer = Construction.new({
	adapters = adapters,
	compiler = compiler,
	evaluator = Evaluator.new({}),
	record = function(result)
		storage.last_enforcement = result
	end,
	reject = function(boundary)
		boundary.entity.destroy()
	end,
})
Construction.register_player_event(script, defines, enforcer)

script.on_init(function()
	state.initialize()
	logger.debug("Initialized persistent state")
end)

script.on_configuration_changed(function()
	state.initialize()
	logger.debug("Configuration updated")
end)
