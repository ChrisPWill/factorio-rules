local Authoring = require("lib.rules.authoring")
local Registry = require("lib.rules.registry")
local Schema = require("lib.rules.schema")

local function rule(reason)
	return {
		schema_version = 1,
		definition_version = 1,
		name = "Test rule",
		event = { domain = "construction", kind = "entity-built" },
		selector = {},
		scope = {},
		when = { predicate = "factorio-rules:always" },
		effects = { primary = { type = "deny", reason = reason or "deny" }, actions = {} },
	}
end

local function builtin()
	local value = rule("builtin")
	value.id = "factorio-rules:builtin"
	value.provenance = { source = "factorio-rules", kind = "builtin" }
	return value
end

local function authoring(state)
	return Authoring.new(state, {
		validate = Schema.normalize,
		stage = function()
			return true
		end,
	})
end

return {
	{
		name = "creates updates duplicates and deletes save-owned rules with stable revisions",
		run = function()
			local state = {}
			local commands = authoring(state)
			local created = assert(commands:execute({ { kind = "create", rule = rule() } }))
			local id = created.results[1].id
			assert(id == "factorio-rules:rule-1")
			assert(commands:list()[1].revision == 2)
			local updated = rule("updated")
			assert(commands:execute({ { kind = "update", id = id, revision = 2, rule = updated } }))
			local effective = commands:list()
			assert(effective[1].effects.primary.reason == "updated" and effective[1].revision == 3)
			local duplicate =
				assert(commands:execute({ { kind = "duplicate", id = id, revision = 3 } }))
			assert(duplicate.results[1].id == "factorio-rules:rule-2")
			assert(commands:execute({ { kind = "delete", id = id, revision = 3 } }))
			assert(#commands:list() == 1 and commands:list()[1].id == "factorio-rules:rule-2")
		end,
	},
	{
		name = "rejects stale and invalid edits without changing persisted rules",
		run = function()
			local state = {}
			local commands = authoring(state)
			local id =
				assert(commands:execute({ { kind = "create", rule = rule() } })).results[1].id
			local before = assert(commands:list()[1].effects.primary.reason)
			local ok, errors = commands:execute({
				{ kind = "update", id = id, revision = 1, rule = rule("changed") },
			})
			assert(not ok and errors[1].field == "commands[1].revision")
			assert(commands:list()[1].effects.primary.reason == before)
			local invalid = rule()
			invalid.when = { predicate = "" }
			ok, errors =
				commands:execute({ { kind = "update", id = id, revision = 2, rule = invalid } })
			assert(not ok and errors[1].field == "commands[1].rule")
			assert(commands:list()[1].effects.primary.reason == before)
		end,
	},
	{
		name = "allows sparse source overrides and reset but protects source ownership",
		run = function()
			local state = {}
			assert(Registry.new(state):register(builtin()))
			local commands = authoring(state)
			assert(commands:execute({
				{
					kind = "set-enabled",
					id = "factorio-rules:builtin",
					revision = 1,
					enabled = false,
				},
			}))
			assert(commands:list()[1].enabled == false)
			assert(
				commands:execute({ { kind = "reset", id = "factorio-rules:builtin", revision = 2 } })
			)
			assert(commands:list()[1].enabled == true)
			local ok, errors = commands:execute({
				{ kind = "delete", id = "factorio-rules:builtin", revision = 3 },
			})
			assert(not ok and errors[1].field == "commands[1]")
		end,
	},
}
