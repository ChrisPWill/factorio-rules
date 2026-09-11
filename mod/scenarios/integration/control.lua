local AdapterRegistry = require("__factorio-rules__.runtime.adapters.registry")
local ConstructionAdapters = require("__factorio-rules__.runtime.adapters.construction")
local Compiler = require("__factorio-rules__.lib.rules.compiler")
local Evaluator = require("__factorio-rules__.lib.rules.evaluator")
local Construction = require("__factorio-rules__.runtime.construction")
local Rollback = require("__factorio-rules__.runtime.rollback")
local Feedback = require("__factorio-rules__.runtime.feedback")
local Overlays = require("__factorio-rules__.runtime.overlays")

local checks = {
	{
		name = "allowed entities can be placed and inspected",
		run = function(surface)
			local entity = surface.create_entity({
				name = "stone-furnace",
				position = { 0, 0 },
				force = "player",
			})
			assert(entity and entity.valid, "stone-furnace was not created")
			assert(entity.name == "stone-furnace", "unexpected entity prototype")
			assert(entity.position.x == 0 and entity.position.y == 0, "unexpected entity position")
		end,
	},
	{
		name = "circle and rectangle overlays render once on the selected surface",
		run = function(surface)
			local overlay_state = { players = {}, forced = {}, entries = {}, objects = {} }
			local overlays = Overlays.factorio({
				state = function()
					return overlay_state
				end,
				player_indices = function()
					return {}
				end,
			}, rendering)
			local entries = {
				{
					key = "integration:circle@1",
					zone_id = "integration:circle",
					shape = { type = "circle", radius = 5 },
					center = { x = 0, y = 10 },
					surface = { index = surface.index, name = surface.name },
				},
				{
					key = "integration:rectangle@1",
					zone_id = "integration:rectangle",
					shape = { type = "rectangle", width = 4, height = 6 },
					center = { x = 10, y = 10 },
					surface = { index = surface.index, name = surface.name },
				},
			}
			assert(overlays:replace(entries))
			local circle = overlay_state.objects["integration:circle@1"].object
			local rectangle = overlay_state.objects["integration:rectangle@1"].object
			assert(circle.valid and circle.type == "circle" and circle.surface == surface)
			assert(
				rectangle.valid and rectangle.type == "rectangle" and rectangle.surface == surface
			)
			local circle_id, rectangle_id = circle.id, rectangle.id
			assert(overlays:replace(entries))
			assert(overlay_state.objects["integration:circle@1"].object.id == circle_id)
			assert(overlay_state.objects["integration:rectangle@1"].object.id == rectangle_id)
			assert(overlays:replace({}))
			assert(not circle.valid and not rectangle.valid)
		end,
	},
	{
		name = "denied builds rollback with safe refunds",
		run = function(surface)
			local adapters = AdapterRegistry.new()
			ConstructionAdapters.register(adapters)
			local compiler = Compiler.new()
			assert(compiler:replace({
				{
					id = "integration:deny-mining-drills",
					enabled = true,
					priority = 1,
					event = { domain = "construction", kind = "entity-built" },
					selector = { entity_types = { "mining-drill" } },
					scope = {},
					when = { predicate = "always" },
					effects = {
						primary = { type = "deny", reason = "integration policy" },
						actions = {},
					},
				},
			}))
			local evaluator = Evaluator.new({
				always = function()
					return true
				end,
			})
			local chest = assert(surface.create_entity({
				name = "wooden-chest",
				position = { 10, 0 },
				force = "player",
			}))
			local refund_inventory = assert(chest.get_inventory(defines.inventory.chest))
			local rollback = Rollback.new({
				capture = function(boundary)
					if boundary.entity.type == "entity-ghost" then
						return {}
					end
					return { { name = "electric-mining-drill", count = 1, quality = "normal" } }
				end,
				destroy = function(boundary)
					return boundary.entity.destroy()
				end,
				insert = function(_, _, stack)
					return refund_inventory.insert(stack)
				end,
				spill = function(_, context, stack)
					local items = surface.spill_item_stack({
						position = context.payload.entity.position,
						stack = stack,
						force = "player",
					})
					return #items > 0 and stack.count or 0
				end,
			})
			local recorded = {}
			local notifications = {}
			local feedback = Feedback.new({
				history_limit = function()
					return 0
				end,
				notify_player = function(index, message)
					notifications[#notifications + 1] =
						{ target = "player", index = index, message = message }
				end,
				notify_force = function(index, message)
					notifications[#notifications + 1] =
						{ target = "force", index = index, message = message }
				end,
			})
			local last_rollback, last_boundary, last_context
			local enforcer = Construction.new({
				adapters = adapters,
				compiler = compiler,
				evaluator = evaluator,
				record = function(result)
					recorded[#recorded + 1] = result
				end,
				feedback = function(result, context, boundary)
					feedback:emit(result, context, boundary)
				end,
				reject = function(boundary, _, context)
					last_boundary, last_context = boundary, context
					last_rollback = assert(rollback:apply(boundary, context))
				end,
			})
			local entity = surface.create_entity({
				name = "electric-mining-drill",
				position = { 2, 0 },
				force = "player",
			})
			assert(entity and entity.valid, "electric-mining-drill was not created")
			local result = assert(enforcer:handle("on_built_entity", {
				entity = entity,
				player_index = 1,
				tick = 1,
			}))
			assert(result.outcome == "deny", "mining drill should be denied")
			assert(not entity.valid, "denied mining drill should be removed")
			assert(last_rollback.refunded == 1 and last_rollback.spilled == 0)
			assert(refund_inventory.get_item_count("electric-mining-drill") == 1)
			local repeated = assert(rollback:apply(last_boundary, last_context))
			assert(repeated.status == "already-reverted")
			assert(refund_inventory.get_item_count("electric-mining-drill") == 1)
			assert(#recorded == 1 and recorded[1].rule_id == "integration:deny-mining-drills")
			assert(notifications[1].target == "player" and notifications[1].index == 1)
			assert(notifications[1].message:find("integration:deny-mining-drills", 1, true))

			refund_inventory.insert({ name = "electric-mining-drill", count = 1000 })
			refund_inventory.insert({ name = "stone", count = 100000 })
			local overflow = assert(surface.create_entity({
				name = "electric-mining-drill",
				position = { 6, 0 },
				force = "player",
			}))
			result = assert(enforcer:handle("on_built_entity", { entity = overflow }))
			assert(result.outcome == "deny" and not overflow.valid)
			assert(last_rollback.refunded == 0 and last_rollback.spilled == 1)
			local spilled = surface.find_entities_filtered({
				area = { { 5, -1 }, { 7, 1 } },
				type = "item-entity",
			})
			assert(#spilled > 0, "overflow refund should spill on the ground")

			local robot_build = assert(surface.create_entity({
				name = "electric-mining-drill",
				position = { 8, 0 },
				force = "player",
			}))
			result = assert(enforcer:handle("on_robot_built_entity", {
				entity = robot_build,
				robot = { unit_number = 99 },
				tick = 2,
			}))
			assert(result.outcome == "deny" and not robot_build.valid)
			assert(notifications[#notifications].target == "force")

			local ghost = surface.create_entity({
				name = "entity-ghost",
				inner_name = "electric-mining-drill",
				position = { 4, 0 },
				force = "player",
			})
			assert(ghost and ghost.valid, "electric-mining-drill ghost was not created")
			result = assert(enforcer:handle("script_raised_built", { entity = ghost }))
			assert(result.outcome == "deny", "mining drill ghost should be denied")
			assert(not ghost.valid, "denied mining drill ghost should be removed")
			assert(#recorded == 4, "manual, robot, and ghost denials should be recorded")
			assert(notifications[#notifications].target == "force")

			local scripted = assert(surface.create_entity({
				name = "stone-furnace",
				position = { 8, 2 },
				force = "player",
			}))
			local cooperative = Construction.cooperative_interface(enforcer, function()
				return 77
			end)
			result = assert(cooperative.enforce_construction(scripted))
			assert(result.outcome == "allow", "cooperative script build should be evaluated")
			local duplicate = assert(enforcer:handle("script_raised_built", {
				entity = scripted,
				tick = 77,
			}))
			assert(duplicate.reason == "duplicate-event", "script build should be evaluated once")
			scripted.destroy()
		end,
	},
}

script.on_init(function()
	local surface = game.surfaces[1]
	for _, check in ipairs(checks) do
		local ok, err = pcall(check.run, surface)
		if not ok then
			error("[factorio-rules integration] FAIL: " .. check.name .. ": " .. tostring(err))
		end
		log("[factorio-rules integration] PASS: " .. check.name)
	end
	log("[factorio-rules integration] ALL TESTS PASSED")
end)
