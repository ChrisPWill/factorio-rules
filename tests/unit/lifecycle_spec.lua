local cases = {}

for _, existing in ipairs({ false, { schema_version = 1, saved_rule = "preserved" } }) do
	cases[#cases + 1] = {
		name = existing and "preserves saved state" or "initializes a new save",
		run = function()
			local persisted = { rules = existing or nil }
			local env = { storage = persisted }
			local state = assert(loadfile("mod/runtime/state.lua", "t", env))()
			assert(state.initialize() == persisted)
			assert(persisted.rules.schema_version == 1)
			assert(type(persisted.violations) == "table")
			assert(type(persisted.overlays.players) == "table")
			assert(persisted.resource_patches.schema_version == 1)
			assert(persisted.spawn_patches.schema_version == 1)
			assert(persisted.resource_discovery.schema_version == 1)
			if existing then
				assert(persisted.rules == existing)
				assert(persisted.rules.saved_rule == "preserved")
			end
			local first = persisted.rules
			local violations = persisted.violations
			local overlays = persisted.overlays
			local resource_patches = persisted.resource_patches
			local spawn_patches = persisted.spawn_patches
			local resource_discovery = persisted.resource_discovery
			state.initialize()
			assert(persisted.rules == first, "Initialization must be idempotent")
			assert(persisted.violations == violations)
			assert(persisted.overlays == overlays)
			assert(persisted.resource_patches == resource_patches)
			assert(persisted.spawn_patches == spawn_patches)
			assert(persisted.resource_discovery == resource_discovery)
		end,
	}
end

cases[#cases + 1] = {
	name = "resets resource caches through one state boundary",
	run = function()
		local persisted = {}
		local state = assert(loadfile("mod/runtime/state.lua", "t", { storage = persisted }))()
		state.initialize()
		local old_patches = persisted.resource_patches
		local old_spawn = persisted.spawn_patches
		local old_discovery = persisted.resource_discovery
		state.reset_resource_cache()
		assert(persisted.resource_patches ~= old_patches)
		assert(persisted.resource_patches.schema_version == 1)
		assert(persisted.resource_patches.next_id == 1)
		assert(persisted.spawn_patches ~= old_spawn)
		assert(persisted.spawn_patches.schema_version == 1)
		assert(persisted.resource_discovery == old_discovery)
	end,
}

for _, enabled in ipairs({ false, true }) do
	cases[#cases + 1] = {
		name = "debug logging enabled=" .. tostring(enabled),
		run = function()
			local messages = {}
			local logger = require("runtime.logger").new(
				{ global = { ["factorio-rules-debug"] = { value = enabled } } },
				function(message)
					messages[#messages + 1] = message
				end
			)
			logger.debug("test")
			assert(#messages == (enabled and 1 or 0))
			if enabled then
				assert(messages[1] == "[factorio-rules] test")
			end
		end,
	}
end

return cases
