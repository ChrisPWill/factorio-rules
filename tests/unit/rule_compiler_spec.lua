local Compiler = require("lib.rules.compiler")
local Evaluator = require("lib.rules.evaluator")

local function rule(id, priority, overrides)
	local result = {
		id = id,
		enabled = true,
		priority = priority,
		event = { domain = "construction", kind = "entity-built" },
		selector = {},
		scope = {},
		when = { predicate = "allowed" },
		effects = {
			primary = { type = "deny", reason = id },
			actions = {},
		},
	}
	for key, value in pairs(overrides or {}) do
		result[key] = value
	end
	return result
end

local function context(overrides)
	local result = {
		domain = "construction",
		kind = "entity-built",
		surface = { index = 1, name = "nauvis" },
		force = { index = 1, name = "player" },
		payload = {
			source = "player",
			entity = { name = "electric-mining-drill", type = "mining-drill" },
		},
	}
	for key, value in pairs(overrides or {}) do
		result[key] = value
	end
	return result
end

local function ids(rules)
	local result = {}
	for _, candidate in ipairs(rules) do
		result[#result + 1] = candidate.id
	end
	return table.concat(result, ",")
end

local function compile(rules)
	local compiler = Compiler.new({
		predicate_requirements = {
			allowed = { capabilities = { "placement-zone" } },
			configured = function(condition)
				return { capabilities = { condition.capability } }
			end,
		},
		action_requirements = {
			["test:notify"] = { services = { "player-feedback" } },
		},
	})
	assert(compiler:replace(rules))
	return compiler
end

return {
	{
		name = "selects candidates through every cheap index",
		run = function()
			local matching = rule("test:matching", 1, {
				selector = {
					entity_types = { "mining-drill" },
					entity_names = { "electric-mining-drill" },
					sources = { "player" },
				},
				scope = { surfaces = { "nauvis", 1 }, forces = { 1 } },
			})
			local compiler = compile({
				matching,
				rule("test:other-event", 9, {
					event = { domain = "mining", kind = "resource-mined" },
				}),
				rule("test:other-type", 8, { selector = { entity_types = { "furnace" } } }),
				rule(
					"test:other-name",
					7,
					{ selector = { entity_names = { "burner-mining-drill" } } }
				),
				rule("test:other-source", 6, { selector = { sources = { "robot" } } }),
				rule("test:other-surface", 5, { scope = { surfaces = { "vulcanus" } } }),
				rule("test:other-force", 4, { scope = { forces = { "enemy" } } }),
			})
			assert(ids(compiler:candidates(context())) == "test:matching")
			local unnamed = context({
				surface = { index = 1 },
				force = { index = 1 },
			})
			assert(ids(compiler:candidates(unnamed)) == "test:matching")
		end,
	},
	{
		name = "preserves priority and ID ordering",
		run = function()
			local compiler = compile({
				rule("test:z", 5),
				rule("test:low", 1),
				rule("test:a", 5),
			})
			assert(ids(compiler:candidates(context())) == "test:a,test:z,test:low")
		end,
	},
	{
		name = "discovers active event capability and service requirements",
		run = function()
			local active = rule("test:active", 1, {
				when = {
					all = {
						{ predicate = "allowed" },
						{ predicate = "configured", capability = "force-budget" },
					},
				},
				effects = {
					primary = { type = "deny", reason = "active" },
					actions = { { type = "test:notify" } },
				},
			})
			local disabled = rule("test:disabled", 1)
			disabled.enabled = false
			local compiler = compile({ active, disabled })
			local requirements = compiler:requirements()
			assert(#requirements.events == 1)
			assert(requirements.events[1].domain == "construction")
			assert(requirements.events[1].kind == "entity-built")
			assert(table.concat(requirements.domains, ",") == "construction")
			assert(table.concat(requirements.capabilities, ",") == "force-budget,placement-zone")
			assert(table.concat(requirements.services, ",") == "player-feedback")
		end,
	},
	{
		name = "rebuilds only when registered definitions change",
		run = function()
			local rules = { rule("test:one", 1) }
			local compiler = compile(rules)
			local revision = compiler:revision()
			assert(compiler:replace(rules) == false)
			assert(compiler:revision() == revision)

			rules[1].priority = 2
			assert(compiler:revision() == revision)
			assert(compiler:replace(rules) == true)
			assert(compiler:revision() == revision + 1)
		end,
	},
	{
		name = "filters expensive predicates before evaluation",
		run = function()
			local calls = 0
			local evaluator = Evaluator.new({
				allowed = function()
					calls = calls + 1
					return true
				end,
			})
			local compiler = compile({
				rule("test:selected", 1),
				rule("test:irrelevant", 2, { selector = { entity_types = { "furnace" } } }),
			})
			local result = assert(evaluator:evaluate(compiler:candidates(context()), context()))
			assert(result.outcome == "deny")
			assert(calls == 1)
		end,
	},
}
