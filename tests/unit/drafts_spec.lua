local Drafts = require("lib.rules.drafts")

return {
	{
		name = "isolates per-player drafts and preserves the opening revision",
		run = function()
			local drafts = Drafts.new()
			local rule = { id = "factorio-rules:rule-1", name = "Ban", enabled = true, conditions = {} }
			local opened = assert(drafts.open(1, rule, 4))
			opened.rule.name = "changed outside"
			assert(rule.name == "Ban")
			local second = assert(drafts.open(2, rule, 9))
			assert(second.base_revision == 9)
			local first = assert(drafts.snapshot(1))
			assert(first.base_revision == 4 and first.rule.name == "Ban" and not first.dirty)
		end,
	},
	{
		name = "updates are copy-on-write and cancel removes the session",
		run = function()
			local drafts = Drafts.new()
			local rule = { id = "r", enabled = true, conditions = {} }
			assert(drafts.open(3, rule, 2))
			local changed = assert(drafts.update(3, { id = "r", enabled = false, conditions = {} }))
			assert(changed.dirty and changed.rule.enabled == false and changed.base_revision == 2)
			changed.rule.enabled = true
			assert(drafts.snapshot(3).rule.enabled == false)
			drafts.cancel(3)
			assert(drafts.snapshot(3) == nil)
			local ok, err = drafts.update(3, rule)
			assert(ok == nil and err == "draft is not open")
		end,
	},
}
