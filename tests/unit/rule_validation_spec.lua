local Validation = require("runtime.rule_validation")

local function rule(id, overrides)
	local result = {
		id = id,
		enabled = true,
		event = { domain = "construction", kind = "entity-built" },
		when = { predicate = "known-predicate" },
		effects = { actions = { { type = "known-action" } } },
	}
	for key, value in pairs(overrides or {}) do
		result[key] = value
	end
	return result
end

local registry = {
	events = { ["construction\0entity-built"] = true },
	predicates = { ["known-predicate"] = true },
	actions = { ["known-action"] = true },
}

return {
	{
		name = "keeps valid rules active",
		run = function()
			local active, diagnostics, errors =
				Validation.validate({ rule("test:valid") }, registry)
			assert(#active == 1 and #diagnostics == 0 and not errors)
		end,
	},
	{
		name = "disables optional unavailable references with warnings",
		run = function()
			local active, diagnostics, errors = Validation.validate({
				rule("test:optional", { effects = { actions = { { type = "missing-action" } } } }),
			}, registry)
			assert(#active == 0 and #diagnostics == 1 and diagnostics[1].action == "disabled")
			assert(not errors)
		end,
	},
	{
		name = "supports fatal reference severity",
		run = function()
			local active, errors = Validation.validate({
				rule("test:required", {
					validation = { action = "error" },
					effects = { actions = { { type = "missing-action" } } },
				}),
			}, registry)
			assert(active == nil and #errors == 1)
		end,
	},
}
