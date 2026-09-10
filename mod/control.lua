local state = require("runtime.state")
local logger = require("runtime.logger")

script.on_init(function()
	state.initialize()
	logger.debug("Initialized persistent state")
end)

script.on_configuration_changed(function()
	state.initialize()
	logger.debug("Configuration updated")
end)
