local M = {}
M.SHORTCUT_NAME = "factorio-rules-manage-rules"
M.FRAME_NAME = "factorio-rules-rule-manager"

local function clear(element)
	for _, child in pairs(element.children) do
		child.destroy()
	end
end

local function provenance(rule)
	local source = rule.provenance and rule.provenance.source or "unknown"
	return source .. " / " .. (rule.provenance and rule.provenance.kind or "unknown")
end

function M.new(options)
	assert(type(options) == "table", "rule UI options are required")
	local ui = {}

	local function player(index)
		return options.get_player(index)
	end

	local function refresh(index)
		local target = player(index)
		local frame = target and target.gui.screen[M.FRAME_NAME]
		if not frame then
			return
		end
		local list = frame[M.FRAME_NAME .. "-list"]
		clear(list)
		for _, rule in ipairs(options.effective_rules()) do
			local row = list.add({ type = "flow", direction = "horizontal" })
			row.add({
				type = "checkbox",
				state = rule.enabled,
				tags = { action = "enabled", rule_id = rule.id },
			})
			row.add({ type = "label", caption = rule.id })
			row.add({
				type = "label",
				caption = rule.effects.primary.type .. ": " .. rule.effects.primary.reason,
			})
			row.add({ type = "label", caption = "priority " .. rule.priority })
			row.add({ type = "label", caption = provenance(rule) })
			row.add({
				type = "textfield",
				text = tostring(rule.priority),
				tags = { action = "priority", rule_id = rule.id },
			})
			row.add({
				type = "button",
				caption = "Reset",
				tags = { action = "reset", rule_id = rule.id },
			})
		end
	end

	function ui.close(_self, index)
		local target = player(index)
		local frame = target and target.gui.screen[M.FRAME_NAME]
		if frame then
			frame.destroy()
		end
	end

	function ui.open(_self, index)
		local target = player(index)
		if not target or not target.gui or not target.gui.screen then
			return nil, "player GUI unavailable"
		end
		ui.close(index)
		local frame = target.gui.screen.add({
			type = "frame",
			name = M.FRAME_NAME,
			caption = "Rule manager",
			direction = "vertical",
		})
		frame.auto_center = true
		frame.add({ type = "label", caption = "Effective rules (edits are saved as overrides)" })
		local list = frame.add({ type = "scroll-pane", name = M.FRAME_NAME .. "-list" })
		list.style.maximal_height = 600
		local close = frame.add({ type = "button", caption = "Close", tags = { action = "close" } })
		close.style.horizontally_stretchable = true
		refresh(index)
		return true, nil
	end

	function ui.handle_click(_self, event)
		local element = event.element
		if not element or not element.valid or not element.tags or not element.tags.action then
			return false
		end
		local action, id = element.tags.action, element.tags.rule_id
		if action == "close" then
			ui.close(event.player_index)
			return true
		elseif action == "reset" then
			assert(options.clear_override(id))
		elseif action == "enabled" then
			assert(options.set_override(id, { enabled = element.state }))
		elseif action == "priority" then
			local value = tonumber(element.text)
			if not value or value % 1 ~= 0 then
				return false, "priority must be an integer"
			end
			assert(options.set_override(id, { priority = value }))
		end
		options.rebuild()
		refresh(event.player_index)
		return true, nil
	end

	return ui
end

return M
