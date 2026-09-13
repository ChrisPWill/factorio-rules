local Application = require("runtime.application")

local function runtime()
	local lifecycle = {}
	local events = {}
	local interfaces = {}
	local messages = {}
	local event_ids = {
		on_built_entity = 1,
		on_robot_built_entity = 2,
		script_raised_built = 3,
		script_raised_revive = 4,
		on_lua_shortcut = 5,
		on_player_joined_game = 6,
		on_chunk_generated = 7,
		on_runtime_mod_setting_changed = 8,
	}
	local script_api = {
		on_init = function(callback)
			lifecycle.init = callback
		end,
		on_configuration_changed = function(callback)
			lifecycle.configuration_changed = callback
		end,
		on_load = function(callback)
			lifecycle.load = callback
		end,
		on_event = function(event_id, callback)
			events[event_id] = callback
		end,
		on_nth_tick = function() end,
	}
	local game = {
		surfaces = {},
		forces = {},
		players = {},
		get_player = function()
			return nil
		end,
		get_surface = function()
			return nil
		end,
		tick = 0,
	}
	local storage = {}
	local settings = {
		global = {
			["factorio-rules-debug"] = { value = false },
			["factorio-rules-violation-history-limit"] = { value = 0 },
			["factorio-rules-nauvis-spawn-radius"] = { value = 500 },
			["factorio-rules-expected-spawn-resources"] = { value = "" },
		},
	}
	local rendering = {}
	local result = {
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
		script = script_api,
		defines = { events = event_ids, inventory = {} },
		remote = {
			add_interface = function(name, interface)
				interfaces[name] = interface
			end,
		},
		log = function()
			return function(message)
				messages[#messages + 1] = message
			end
		end,
	}
	return result, storage, settings, lifecycle, events, interfaces, messages, event_ids
end

return {
	{
		name = "registers one application boundary and shares lifecycle activation",
		run = function()
			local api, storage, settings, lifecycle, events, interfaces, messages, event_ids =
				runtime()
			Application.register(api)
			assert(type(lifecycle.init) == "function")
			assert(type(lifecycle.configuration_changed) == "function")
			assert(type(lifecycle.load) == "function")
			for _, event_id in pairs(event_ids) do
				assert(type(events[event_id]) == "function")
			end
			assert(type(interfaces.factorio_rules.enforce_construction) == "function")

			lifecycle.init()
			assert(storage.rules.schema_version == 1)
			local rules = storage.rules
			settings.global["factorio-rules-debug"].value = true
			lifecycle.configuration_changed()
			assert(storage.rules == rules)
			assert(messages[1] == "[factorio-rules] Configuration updated")
			local saved_rules = storage.rules
			lifecycle.load()
			assert(storage.rules == saved_rules)
		end,
	},
}
