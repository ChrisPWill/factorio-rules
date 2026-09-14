local Zones = require("lib.zones")
local M = {}
M.SHORTCUT_NAME = "factorio-rules-manage-rules"
M.FRAME_NAME = "factorio-rules-rule-manager"
M.TOP_BUTTON_NAME = "factorio-rules-manage-rules-button"

local function clear(element)
	for _, child in pairs(element.children) do
		child.destroy()
	end
end

local function provenance(rule)
	local source = rule.provenance and rule.provenance.source or "unknown"
	return source .. " / " .. (rule.provenance and rule.provenance.kind or "unknown")
end

local function zone_caption(rule)
	local ids = {}
	for id in pairs(Zones.referenced_ids(rule)) do
		ids[#ids + 1] = id
	end
	table.sort(ids)
	if #ids == 0 then
		return "Zones: none"
	end
	local labels = {}
	for _, id in ipairs(ids) do
		labels[#labels + 1] = id
	end
	return "Zones: " .. table.concat(labels, ", ")
end

function M.new(options)
	assert(type(options) == "table", "rule UI options are required")
	local ui = {}

	local function player(index)
		return options.get_player(index)
	end

	local function can_edit(index)
		return not options.can_edit or options.can_edit(index)
	end

	local function owned_element(element, index)
		local frame = player(index) and player(index).gui.screen[M.FRAME_NAME]
		if not frame or not element.parent then
			return true
		end
		local current = element
		while current do
			if current == frame then
				return true
			end
			current = current.parent
		end
		return false
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
			local row = list.add({ type = "flow", direction = "vertical" })
			row.style.horizontally_stretchable = true
			local header = row.add({ type = "flow", direction = "horizontal" })
			header.style.horizontally_stretchable = true
			header.add({
				type = "checkbox",
				state = rule.enabled,
				tags = {
					action = "enabled",
					rule_id = rule.id,
					revision = options.revision and options.revision(rule.id),
				},
			})
			header.add({ type = "label", caption = rule.enabled and "Enabled" or "Disabled" })
			header.add({ type = "label", caption = rule.id })
			local effect = row.add({
				type = "label",
				caption = rule.effects.primary.type .. ": " .. rule.effects.primary.reason,
			})
			effect.style.single_line = false
			row.add({
				type = "label",
				caption = zone_caption(rule),
			})
			local details = row.add({ type = "flow", direction = "horizontal" })
			details.style.horizontally_stretchable = true
			details.add({ type = "label", caption = "Priority: " .. rule.priority })
			details.add({ type = "label", caption = provenance(rule) })
			details.add({
				type = "textfield",
				text = tostring(rule.priority),
				tags = {
					action = "priority",
					rule_id = rule.id,
					revision = options.revision and options.revision(rule.id),
				},
			})
			details.add({
				type = "button",
				caption = "Reset",
				tags = {
					action = "reset",
					rule_id = rule.id,
					revision = options.revision and options.revision(rule.id),
				},
			})
		end
		if options.zones then
			list.add({ type = "label", caption = "Custom zones" })
			for _, zone in ipairs(options.zones()) do
				local row = list.add({ type = "flow", direction = "horizontal" })
				row.add({
					type = "textfield",
					text = zone.name or zone.id,
					tags = { action = "rename-zone", zone_id = zone.id },
					tooltip = "Press Enter to rename",
				})
				row.add({ type = "label", caption = zone.id })
				row.add({
					type = "button",
					caption = "Redraw",
					tags = { action = "edit-zone", zone_id = zone.id },
				})
			end
		end
	end

	function ui.close(_self, index)
		local target = player(index)
		local frame = target and target.gui.screen[M.FRAME_NAME]
		if frame then
			frame.destroy()
		end
	end

	function ui.ensure_button(_self, index)
		local target = player(index)
		if not target or not target.gui or not target.gui.top then
			return false
		end
		local button = target.gui.top[M.TOP_BUTTON_NAME]
		if button and button.valid then
			return true
		end
		target.gui.top.add({
			type = "button",
			name = M.TOP_BUTTON_NAME,
			caption = { "shortcut-name.factorio-rules-manage-rules" },
			tags = { action = "open-manager" },
		})
		return true
	end

	function ui.open(_self, index)
		local target = player(index)
		if not target or not target.gui or not target.gui.screen then
			return nil, "player GUI unavailable"
		end
		ui:close(index)
		local frame = target.gui.screen.add({
			type = "frame",
			name = M.FRAME_NAME,
			caption = "Rule manager",
			direction = "vertical",
		})
		frame.auto_center = true
		frame.style.minimal_width = 900
		frame.add({ type = "label", caption = "Effective rules (edits are saved as overrides)" })
		local summary = options.zone_summary and options.zone_summary() or { unused = 0 }
		frame.add({
			type = "label",
			name = M.FRAME_NAME .. "-zone-summary",
			caption = "Unused zones: " .. tostring(summary.unused or 0),
		})
		frame.add({
			type = "button",
			caption = "Delete unused zones",
			tags = { action = "delete-unused-zones" },
		})
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
		if not owned_element(element, event.player_index) then
			return false
		end
		local action, id = element.tags.action, element.tags.rule_id
		if action == "open-manager" then
			ui:open(event.player_index)
			return true
		elseif action == "close" then
			ui:close(event.player_index)
			return true
		elseif action == "delete-unused-zones" then
			if not can_edit(event.player_index) then
				return false, "only an admin can edit rules"
			end
			assert(options.delete_unused_zones())
			options.rebuild()
			refresh(event.player_index)
			local target = player(event.player_index)
			local frame = target and target.gui.screen[M.FRAME_NAME]
			local summary = options.zone_summary and options.zone_summary() or { unused = 0 }
			if frame and frame[M.FRAME_NAME .. "-zone-summary"] then
				frame[M.FRAME_NAME .. "-zone-summary"].caption = "Unused zones: "
					.. tostring(summary.unused or 0)
			end
			return true, nil
		elseif action == "edit-zone" then
			if not can_edit(event.player_index) then
				return false, "only an admin can edit rules"
			end
			local ok, errors = options.edit_zone(event.player_index, element.tags.zone_id)
			if ok then
				ui:close(event.player_index)
			end
			return ok, errors
		elseif action == "rename-zone" then
			if not can_edit(event.player_index) then
				return false, "only an admin can edit rules"
			end
			local ok, errors = options.rename_zone(element.tags.zone_id, element.text)
			if not ok then
				return nil, errors
			end
		elseif action == "reset" then
			if not can_edit(event.player_index) then
				return false, "only an admin can edit rules"
			end
			assert(options.mutate({
				{
					kind = "reset",
					id = id,
					revision = element.tags.revision or options.revision(id),
				},
			}, { origin = "gui", player_index = event.player_index }))
		elseif action == "enabled" then
			if not can_edit(event.player_index) then
				return false, "only an admin can edit rules"
			end
			assert(options.mutate({
				{
					kind = "set-enabled",
					id = id,
					revision = element.tags.revision or options.revision(id),
					enabled = element.state,
				},
			}, { origin = "gui", player_index = event.player_index }))
		elseif action == "priority" then
			if not can_edit(event.player_index) then
				return false, "only an admin can edit rules"
			end
			local value = tonumber(element.text)
			if not value or value % 1 ~= 0 then
				return false, "priority must be an integer"
			end
			assert(options.mutate({
				{
					kind = "set-priority",
					id = id,
					revision = element.tags.revision or options.revision(id),
					priority = value,
				},
			}, { origin = "gui", player_index = event.player_index }))
		end
		options.rebuild()
		refresh(event.player_index)
		return true, nil
	end

	return ui
end

return M
