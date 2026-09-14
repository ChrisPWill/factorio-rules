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
		name = "syncs current source defaults without replacing save-owned rules or overrides",
		run = function()
			local state = {}
			local registry = Registry.new(state)
			local v1 = rule("alpha:one", "v1")
			v1.priority = 1
			assert(registry:sync_source("alpha", { v1 }))
			assert(registry:set_override("alpha:one", { priority = 9 }))
			local saved = rule("alpha:save", "saved")
			saved.provenance.kind = "save"
			assert(registry:register(saved))

			local v2 = rule("alpha:one", "v2")
			v2.priority = 2
			assert(registry:sync_source("alpha", { v2 }))
			local effective = assert(registry:effective())
			assert(effective[1].effects.primary.reason == "v2")
			assert(effective[1].priority == 9)
			assert(effective[2].id == "alpha:save")
			assert(registry:clear_override("alpha:one"))
			effective = assert(registry:effective())
			assert(effective[1].priority == 2)
		end,
	},
	{
		name = "uses declared patch order and records the winning field owner",
		run = function()
			local registry = Registry.new({})
			assert(registry:register(rule("alpha:one")))
			assert(registry:override("alpha:one", { priority = 2 }, "later", 20))
			assert(registry:override("alpha:one", { priority = 1 }, "earlier", 10))
			local effective = assert(registry:effective())[1]
			assert(effective.priority == 2)
			assert(effective.provenance.fields.priority.source == "later")
			assert(effective.provenance.fields.priority.kind == "override")
		end,
	},
	{
		name = "removes absent source definitions while retaining overrides for restoration",
		run = function()
			local registry = Registry.new({})
			assert(registry:sync_source("alpha", { rule("alpha:one") }))
			assert(registry:set_override("alpha:one", { enabled = false }))
			assert(registry:sync_source("alpha", {}))
			local effective, _, warnings = registry:effective()
			assert(#effective == 0)
			assert(#warnings == 1 and warnings[1]:find("orphaned", 1, true))
			assert(registry:sync_source("alpha", { rule("alpha:one") }))
			effective = assert(registry:effective())
			assert(#effective == 1 and effective[1].enabled == false)
		end,
	},
	{
		name = "inspects effective rules without changing persisted state",
		run = function()
			local state = {}
			local registry = Registry.new(state)
			assert(registry:register(rule("alpha:one")))
			assert(registry:override("alpha:one", { priority = 2 }, "beta:patch"))
			assert(registry:override("alpha:one", { enabled = false }, "gamma:patch"))
			local original_sequence = state.patches[1].sequence
			local effective = assert(registry:effective())
			effective[1].priority = 99
			assert(state.patches[1].sequence == original_sequence)
			assert(assert(registry:effective())[1].priority == 2)
		end,
	},
	{
		name = "retains and warns about orphaned save overrides",
		run = function()
			local registry = Registry.new({ overrides = { ["gone:rule"] = { enabled = false } } })
			local effective, _, warnings = registry:effective()
			assert(effective)
			assert(#effective == 0)
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
