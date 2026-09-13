local Registry = require("lib.rules.registry")

local function rule(id, reason)
	return {
		schema_version = 1,
		definition_version = 1,
		id = id,
		provenance = { source = id:match("^[^:]+"), kind = "test" },
		event = { domain = "test", kind = "event" },
		selector = {},
		scope = {},
		when = { predicate = "test:predicate" },
		effects = { primary = { type = "deny", reason = reason or "deny" }, actions = {} },
	}
end

return {
	{
		name = "rejects duplicate registration but allows explicit replacement",
		run = function()
			local registry = Registry.new({})
			assert(registry:register(rule("alpha:one")))
			local ok, errors = registry:register(rule("alpha:one"))
			assert(not ok and errors[1]:find("already registered", 1, true))
			assert(registry:replace(rule("alpha:one", "replacement")))
			local effective = assert(registry:effective())
			assert(effective[1].effects.primary.reason == "replacement")
		end,
	},
	{
		name = "applies ordered cross-source patches and sparse save overrides",
		run = function()
			local state = {}
			local registry = Registry.new(state)
			assert(registry:register(rule("alpha:one")))
			assert(registry:override("alpha:one", { priority = 4 }, "beta:patch"))
			assert(
				registry:override(
					"alpha:one",
					{ effects = { primary = { reason = "patched" } } },
					"gamma:patch"
				)
			)
			assert(registry:set_override("alpha:one", { enabled = false }))
			local effective = assert(registry:effective())
			assert(effective[1].priority == 4)
			assert(effective[1].effects.primary.reason == "patched")
			assert(effective[1].enabled == false)
			assert(#effective[1].provenance.lineage == 4)
		end,
	},
	{
		name = "retains and warns about orphaned save overrides",
		run = function()
			local registry = Registry.new({ overrides = { ["gone:rule"] = { enabled = false } } })
			local effective = assert(registry:effective())
			assert(#effective == 0)
			local warnings = registry:warnings()
			assert(#warnings == 1 and warnings[1]:find("orphaned", 1, true))
		end,
	},
	{
		name = "replaces condition and collection fields instead of retaining stale values",
		run = function()
			local registry = Registry.new({})
			local base = rule("alpha:one")
			base.selector = { entity_names = { "iron-chest", "steel-chest" } }
			base.when = { all = { { predicate = "test:predicate" }, { predicate = "test:other" } } }
			assert(registry:register(base))
			assert(registry:set_override("alpha:one", {
				selector = { entity_names = { "wooden-chest" } },
				when = { any = { { predicate = "test:new" } } },
			}))
			local effective = assert(registry:effective())[1]
			assert(
				#effective.selector.entity_names == 1
					and effective.selector.entity_names[1] == "wooden-chest"
			)
			assert(effective.when.any and not effective.when.all)
		end,
	},
	{
		name = "migrates old sparse overrides transactionally",
		run = function()
			local base = rule("alpha:one")
			base.definition_version = 2
			local state = {
				overrides = { ["alpha:one"] = { old_reason = "legacy" } },
				override_versions = { ["alpha:one"] = 1 },
			}
			local registry = Registry.new(state)
			assert(registry:register(base))
			assert(registry:migrate({
				rule_migrations = {
					["alpha:one"] = function(_fields, from, to)
						assert(from == 1 and to == 2)
						return { priority = 7 }
					end,
				},
			}))
			local effective = assert(registry:effective())
			assert(effective[1].priority == 7)
		end,
	},
	{
		name = "does not commit a failed migration",
		run = function()
			local state = { framework_schema_version = 1 }
			local registry = Registry.new(state)
			local ok, errors = registry:migrate({
				framework_schema_version = 2,
				framework_migrations = {
					[1] = function()
						return nil
					end,
				},
			})
			assert(not ok and errors[1]:find("migration failed", 1, true))
			assert(state.framework_schema_version == 1)
		end,
	},
}
