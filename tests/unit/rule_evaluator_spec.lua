local Evaluator = require("lib.rules.evaluator")

local evaluator = Evaluator.new({
	value_is = function(context, condition)
		return context.metadata.value == condition.value
	end,
	capability_is = function(context, condition)
		return context:get_capability(condition.capability) == condition.value
	end,
})

local function context(overrides)
	local result = {
		domain = "construction",
		kind = "entity-built",
		surface = { index = 1, name = "nauvis" },
		force = { index = 1, name = "player" },
		metadata = { value = 1 },
		payload = {
			source = "player",
			entity = { name = "electric-mining-drill", type = "mining-drill" },
		},
		get_capability = function(_, name)
			return name == "zone" and "spawn" or nil
		end,
	}
	for key, value in pairs(overrides or {}) do
		result[key] = value
	end
	return result
end

local function rule(id, priority, outcome, condition)
	return {
		id = id,
		enabled = true,
		priority = priority,
		event = { domain = "construction", kind = "entity-built" },
		selector = {},
		scope = {},
		when = condition or { predicate = "value_is", value = 1 },
		effects = {
			primary = { type = outcome, reason = id .. " reason" },
			actions = { { type = "test:notify" } },
		},
	}
end

return {
	{
		name = "allows when no restriction matches",
		run = function()
			local result = assert(evaluator:evaluate(
				{ rule("test:no", 1, "deny", {
					predicate = "value_is",
					value = 2,
				}) },
				context()
			))
			assert(result.outcome == "allow" and #result.matched_rule_ids == 0)
			assert(result.explanation == nil)
		end,
	},
	{
		name = "warning allows with feedback intents",
		run = function()
			local result =
				assert(evaluator:evaluate({ rule("test:warning", 1, "warn") }, context()))
			assert(result.outcome == "warn" and result.rule_id == "test:warning")
			assert(#result.actions == 1 and result.actions[1].rule_id == "test:warning")
		end,
	},
	{
		name = "deny wins over a higher-priority warning",
		run = function()
			local result = assert(evaluator:evaluate({
				rule("test:warning", 100, "warn"),
				rule("test:deny", 1, "deny"),
			}, context()))
			assert(result.outcome == "deny" and result.rule_id == "test:deny")
			assert(result.matched_rule_ids[1] == "test:warning")
		end,
	},
	{
		name = "priority and ID deterministically select the surfaced denial",
		run = function()
			local result = assert(evaluator:evaluate({
				rule("test:z", 5, "deny"),
				rule("test:low", 1, "deny"),
				rule("test:a", 5, "deny"),
			}, context()))
			assert(result.rule_id == "test:a")
			assert(result.matched_rule_ids[1] == "test:a")
			assert(result.matched_rule_ids[2] == "test:z")
		end,
	},
	{
		name = "supports all any not and capability predicates",
		run = function()
			local condition = {
				all = {
					{ predicate = "value_is", value = 1 },
					{
						any = {
							{ predicate = "capability_is", capability = "zone", value = "spawn" },
							{ ["not"] = { predicate = "value_is", value = 1 } },
						},
					},
				},
			}
			local result = assert(evaluator:evaluate({
				rule("test:composed", 1, "deny", condition),
			}, context()))
			assert(result.outcome == "deny")
		end,
	},
	{
		name = "filters by selectors and scope before predicates",
		run = function()
			local selected = rule("test:selected", 1, "deny")
			selected.selector = {
				entity_types = { "mining-drill" },
				entity_names = { "electric-mining-drill" },
				sources = { "player" },
			}
			selected.scope = { surfaces = { "nauvis" }, forces = { 1 } }
			local matching = assert(evaluator:evaluate({ selected }, context()))
			assert(matching.outcome == "deny")
			selected.scope.surfaces = { "vulcanus" }
			local outside_scope = assert(evaluator:evaluate({ selected }, context()))
			assert(outside_scope.outcome == "allow")
		end,
	},
	{
		name = "builds detailed traces only on demand",
		run = function()
			local disabled = rule("test:disabled", 2, "deny")
			disabled.enabled = false
			local result = assert(evaluator:evaluate({
				disabled,
				rule("test:explained", 1, "deny", {
					all = {
						{ predicate = "value_is", value = 1 },
						{ predicate = "value_is", value = 2 },
					},
				}),
			}, context(), { explain = true }))
			assert(result.outcome == "allow")
			assert(result.explanation.rules[1].status == "disabled")
			assert(result.explanation.rules[2].condition.children[2].matched == false)
		end,
	},
}
