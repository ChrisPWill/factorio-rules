local RuleUI = require("runtime.rule_ui")

return {
	{
		name = "writes sparse enabled and priority edits through the registry boundary",
		run = function()
			local overrides, rebuilds = {}, 0
			local deleted = 0
			local ui = RuleUI.new({
				get_player = function(index)
					assert(index == 1)
					return nil
				end,
				effective_rules = function()
					return {}
				end,
				set_override = function(id, fields)
					overrides[id] = fields
					return true
				end,
				clear_override = function()
					return true
				end,
				delete_unused_zones = function()
					deleted = deleted + 1
					return true
				end,
				rebuild = function()
					rebuilds = rebuilds + 1
				end,
			})
			local element = {
				valid = true,
				tags = { action = "enabled", rule_id = "test:rule" },
				state = false,
			}
			assert(ui:handle_click({ element = element, player_index = 1 }))
			assert(overrides["test:rule"].enabled == false and rebuilds == 1)
			element.tags.action = "priority"
			element.text = "7"
			assert(ui:handle_click({ element = element, player_index = 1 }))
			assert(overrides["test:rule"].priority == 7 and rebuilds == 2)
			local close = { valid = true, tags = { action = "close" } }
			assert(ui:handle_click({ element = close, player_index = 1 }))
			assert(ui:handle_click({
				element = { valid = true, tags = { action = "delete-unused-zones" } },
				player_index = 1,
			}))
			assert(deleted == 1)
		end,
	},
}
