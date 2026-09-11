local schema = require("lib.rules.schema")

local function valid_rule()
	return {
		schema_version = 1,
		definition_version = 1,
		id = "factorio-rules:nauvis-spawn-miners",
		provenance = { source = "factorio-rules", kind = "builtin" },
		event = { domain = "construction", kind = "entity-built" },
		selector = { entity_types = { "mining-drill" } },
		scope = { surfaces = { "nauvis" } },
		when = { predicate = "entity.in-spawn-resource-zone", value = true },
		effects = {
			primary = { type = "deny", reason = "Mining drills are not allowed in the spawn zone." },
			actions = { { type = "factorio-rules:notify-player", severity = "error" } },
		},
	}
end

local function contains(errors, text)
	for _, message in ipairs(errors or {}) do
		if message:find(text, 1, true) then
			return true
		end
	end
	return false
end

return {
	{
		name = "normalizes defaults without mutating the definition",
		run = function()
			local input = valid_rule()
			local normalized, errors = schema.normalize(input)
			assert(normalized and not errors)
			assert(normalized.enabled == true)
			assert(normalized.priority == 0)
			assert(input.enabled == nil and input.priority == nil)
			assert(normalized ~= input and normalized.selector ~= input.selector)
		end,
	},
	{
		name = "normalizes human-friendly unless into not",
		run = function()
			local input = valid_rule()
			input.unless = { predicate = "actor.is-admin", value = true }
			local normalized = assert(schema.normalize(input))
			assert(normalized.unless == nil)
			assert(normalized.when.all[1].predicate == "entity.in-spawn-resource-zone")
			assert(normalized.when.all[2]["not"].predicate == "actor.is-admin")
		end,
	},
	{
		name = "supports all any and not composition",
		run = function()
			local input = valid_rule()
			input.when = {
				all = {
					{ predicate = "entity.is-miner" },
					{
						any = {
							{ predicate = "zone.spawn" },
							{ ["not"] = { predicate = "surface.nauvis" } },
						},
					},
				},
			}
			assert(schema.normalize(input))
		end,
	},
	{
		name = "reports actionable field paths",
		run = function()
			local input = valid_rule()
			input.id = "missing-namespace"
			input.definition_version = 0
			input.effects.primary.type = "allow"
			local normalized, errors = schema.normalize(input)
			assert(normalized == nil)
			assert(contains(errors, "rule.id:"))
			assert(contains(errors, "rule.definition_version:"))
			assert(contains(errors, "rule.effects.primary.type:"))
		end,
	},
	{
		name = "rejects executable callbacks anywhere in rule data",
		run = function()
			local input = valid_rule()
			input.selector.callback = function() end
			local normalized, errors = schema.normalize(input)
			assert(normalized == nil)
			assert(contains(errors, "rule.selector.callback: must contain only serializable data"))
		end,
	},
	{
		name = "rejects ambiguous condition shapes",
		run = function()
			local input = valid_rule()
			input.when = { predicate = "one", all = { { predicate = "two" } } }
			local normalized, errors = schema.normalize(input)
			assert(normalized == nil)
			assert(contains(errors, "must define exactly one"))
		end,
	},
	{
		name = "preserves strict collection validation",
		run = function()
			local input = valid_rule()
			input.selector.entity_types.extra = "mixed"
			local normalized, errors = schema.normalize(input)
			assert(normalized == nil)
			assert(contains(errors, "must not mix array indexes and string keys"))
		end,
	},
	{
		name = "accepts persisted zone references on rules",
		run = function()
			local input = valid_rule()
			input.zone_ids = { "test:zone" }
			local rule = assert(schema.normalize(input))
			assert(rule.zone_ids[1] == "test:zone")
		end,
	},
}
