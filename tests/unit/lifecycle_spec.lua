local cases = {}

for _, existing in ipairs({ false, { schema_version = 1, saved_rule = "preserved" } }) do
	cases[#cases + 1] = {
		name = existing and "preserves saved state" or "initializes a new save",
		run = function()
			local persisted = { rules = existing or nil }
			local env = { storage = persisted }
			local state = assert(loadfile("mod/runtime/state.lua", "t", env))()
			state.initialize()
			assert(persisted.rules.schema_version == 1)
			if existing then
				assert(persisted.rules == existing)
				assert(persisted.rules.saved_rule == "preserved")
			end
			local first = persisted.rules
			state.initialize()
			assert(persisted.rules == first, "Initialization must be idempotent")
		end,
	}
end

for _, enabled in ipairs({ false, true }) do
	cases[#cases + 1] = {
		name = "debug logging enabled=" .. tostring(enabled),
		run = function()
			local messages = {}
			local env = {
				settings = { global = { ["factorio-rules-debug"] = { value = enabled } } },
				log = function(message)
					messages[#messages + 1] = message
				end,
			}
			local logger = assert(loadfile("mod/runtime/logger.lua", "t", env))()
			logger.debug("test")
			assert(#messages == (enabled and 1 or 0))
			if enabled then
				assert(messages[1] == "[factorio-rules] test")
			end
		end,
	}
end

return cases
