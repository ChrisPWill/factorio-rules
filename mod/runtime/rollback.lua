local M = {}

local function copy_with_count(stack, count)
	local result = {}
	for key, value in pairs(stack) do
		result[key] = value
	end
	result.count = count
	return result
end

local function call(operation, ...)
	local ok, result = pcall(operation, ...)
	if not ok then
		return nil, tostring(result)
	end
	return result, nil
end

function M.new(options)
	assert(type(options) == "table", "rollback options must be a table")
	assert(type(options.capture) == "function", "rollback capture is required")
	assert(type(options.destroy) == "function", "rollback destroy is required")
	assert(type(options.insert) == "function", "rollback insert is required")
	assert(type(options.spill) == "function", "rollback spill is required")
	local rollback = {}

	function rollback.apply(_self, boundary, context)
		if not boundary.entity or boundary.entity.valid == false then
			return { status = "already-reverted", refunded = 0, spilled = 0 }, nil
		end

		local stacks, capture_error = call(options.capture, boundary, context)
		if not stacks then
			return nil, { "refund capture failed: " .. capture_error }
		end
		local destroyed, destroy_error = call(options.destroy, boundary, context)
		if not destroyed then
			return nil,
				{ "entity rollback failed: " .. (destroy_error or "destroy returned false") }
		end

		local report = { status = "reverted", refunded = 0, spilled = 0 }
		local errors = {}
		for _, stack in ipairs(stacks) do
			local requested = stack.count or 0
			local inserted, insert_error = call(options.insert, boundary, context, stack)
			inserted = inserted or 0
			if insert_error then
				errors[#errors + 1] = "refund insert failed for "
					.. stack.name
					.. ": "
					.. insert_error
			end
			if inserted < 0 or inserted > requested then
				return nil, { "refund insert returned an invalid count for " .. stack.name }
			end
			report.refunded = report.refunded + inserted
			local remainder = requested - inserted
			if remainder > 0 then
				local spilled, spill_error =
					call(options.spill, boundary, context, copy_with_count(stack, remainder))
				spilled = spilled or 0
				if spilled < 0 or spilled > remainder then
					return nil, { "refund spill returned an invalid count for " .. stack.name }
				end
				report.spilled = report.spilled + spilled
				if spill_error then
					errors[#errors + 1] = "refund spill failed for "
						.. stack.name
						.. ": "
						.. spill_error
				end
				if spilled < remainder then
					errors[#errors + 1] = string.format(
						"refund incomplete for %s: %d item(s) remain",
						stack.name,
						remainder - spilled
					)
				end
			end
		end
		return report, #errors > 0 and errors or nil
	end

	return rollback
end

local function consumed_stacks(boundary)
	local inventory = boundary.event and boundary.event.consumed_items
	if not inventory or not inventory.valid then
		return {}
	end
	local result = {}
	for index = 1, #inventory do
		local stack = inventory[index]
		if stack.valid_for_read then
			local definition = {
				name = stack.name,
				count = stack.count,
				quality = stack.quality.name,
			}
			for _, field in ipairs({
				"health",
				"durability",
				"ammo",
				"tags",
				"custom_description",
				"spoil_percent",
			}) do
				local ok, value = pcall(function()
					return stack[field]
				end)
				if ok and value ~= nil then
					definition[field] = value
				end
			end
			result[#result + 1] = definition
		end
	end
	return result
end

function M.factorio(api, defines_api)
	assert(type(api) == "table", "Factorio rollback API is required")
	return M.new({
		capture = consumed_stacks,
		destroy = function(boundary)
			return boundary.entity.destroy()
		end,
		insert = function(boundary, _, stack)
			local event = boundary.event or {}
			if event.player_index then
				local player = api.get_player(event.player_index)
				return player and player.insert(stack) or 0
			end
			if boundary.robot and boundary.robot.valid then
				local inventory = boundary.robot.get_inventory(defines_api.inventory.robot_cargo)
				return inventory and inventory.insert(stack) or 0
			end
			return 0
		end,
		spill = function(_, context, stack)
			local surface = assert(api.get_surface(context.surface.index), "surface unavailable")
			local spilled = surface.spill_item_stack({
				position = context.payload.entity.position,
				stack = stack,
				force = context.force and (context.force.name or context.force.index),
				enable_looted = true,
			})
			return #spilled > 0 and stack.count or 0
		end,
	})
end

return M
