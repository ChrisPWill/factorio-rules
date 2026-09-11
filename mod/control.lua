local Application = require("runtime.application")

Application.register({
	prototypes = function()
		return prototypes
	end,
	game = function()
		return game
	end,
	storage = function()
		return storage
	end,
	settings = function()
		return settings
	end,
	rendering = function()
		return rendering
	end,
	script = script,
	defines = defines,
	remote = remote,
	log = function()
		return log
	end,
})
