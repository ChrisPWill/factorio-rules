local RuleUI = require("runtime.rule_ui")

return {
	{
		name = "writes sparse enabled and priority edits through the registry boundary",
		run = function()
			local commands, rebuilds = {}, 0
			local deleted = 0
			local ui = RuleUI.new({
				get_player = function(index)
					assert(index == 1)
					return nil
				end,
				effective_rules = function()
					return {}
				end,
				mutate = function(next)
					commands[#commands + 1] = next[1]
					return true
				end,
				revision = function()
					return 1
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
			assert(commands[1].enabled == false and commands[1].revision == 1 and rebuilds == 1)
			element.tags.action = "priority"
			element.text = "7"
			assert(ui:handle_click({ element = element, player_index = 1 }))
			assert(
				commands[2].priority == 7 and commands[2].kind == "set-priority" and rebuilds == 2
			)
			local close = { valid = true, tags = { action = "close" } }
			assert(ui:handle_click({ element = close, player_index = 1 }))
			assert(ui:handle_click({
				element = { valid = true, tags = { action = "delete-unused-zones" } },
				player_index = 1,
			}))
			assert(deleted == 1)
			local top = {
				add = function(spec)
					assert(spec.name == RuleUI.TOP_BUTTON_NAME)
					assert(spec.tags.action == "open-manager")
					return spec
				end,
			}
			local player = { gui = { top = top } }
			local button_ui = RuleUI.new({
				get_player = function()
					return player
				end,
				effective_rules = function()
					return {}
				end,
			})
			assert(button_ui:ensure_button(1))
		end,
	},
}
