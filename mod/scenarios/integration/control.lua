local AdapterRegistry = require("__factorio-rules__.runtime.adapters.registry")
local ConstructionAdapters = require("__factorio-rules__.runtime.adapters.construction")
local Compiler = require("__factorio-rules__.lib.rules.compiler")
local Evaluator = require("__factorio-rules__.lib.rules.evaluator")
local Construction = require("__factorio-rules__.runtime.construction")
local Rollback = require("__factorio-rules__.runtime.rollback")
local Feedback = require("__factorio-rules__.runtime.feedback")
local Overlays = require("__factorio-rules__.runtime.overlays")
local ResourcePatches = require("__factorio-rules__.lib.resource_patches")
local ResourceDiscovery = require("__factorio-rules__.runtime.resource_discovery")
local SpawnPatches = require("__factorio-rules__.lib.spawn_patches")
local Zones = require("__factorio-rules__.lib.zones")
local NauvisMiner = require("__factorio-rules__.lib.builtin.nauvis_miner")
local RuleRegistry = require("__factorio-rules__.lib.rules.registry")

local checks = {
	{
		name = "rule registry resolves source, patch, save override, and orphan provenance",
		run = function()
			local state = {}
			local registry = RuleRegistry.new(state)
			local rule = NauvisMiner.rule()
			assert(registry:register(rule))
			assert(registry:override(rule.id, { priority = 101 }, "integration:patch"))
			assert(registry:set_override(rule.id, { enabled = false }))
			local effective = assert(registry:effective())
			assert(#effective == 1 and effective[1].priority == 101 and not effective[1].enabled)
			assert(#effective[1].provenance.lineage == 3)
			assert(registry:set_override("removed:rule", { enabled = false }))
			assert(registry:effective())
			assert(#registry:warnings() == 1)
		end,
	},
	{
		name = "rule registry upgrades a saved override without corrupting state",
		run = function()
			local state = {
				framework_schema_version = 1,
				overrides = { ["integration:rule"] = { old_field = true } },
				override_versions = { ["integration:rule"] = 1 },
			}
			local registry = RuleRegistry.new(state)
			local rule = NauvisMiner.rule()
			rule.id = "integration:rule"
			rule.provenance.source = "integration"
			rule.definition_version = 2
			assert(registry:register(rule))
			assert(registry:migrate({
				rule_migrations = {
					["integration:rule"] = function()
						return { priority = 9 }
					end,
				},
				source_versions = { integration = "2.0.0" },
			}))
			local effective = assert(registry:effective())
			assert(effective[1].priority == 9)
			assert(state.source_versions.integration == "2.0.0")
		end,
	},
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
		name = "seed 3885402781 restricts nearby non-starting resource patches",
		run = function(surface)
			local force = game.forces.player
			local spawn = force.get_spawn_position(surface)
			surface.request_to_generate_chunks(spawn, 16)
			surface.force_generate_chunk_requests()

			local resources = {}
			for _, entity in
				ipairs(surface.find_entities_filtered({
					area = {
						{ spawn.x - 512, spawn.y - 512 },
						{ spawn.x + 512, spawn.y + 512 },
					},
					type = "resource",
				}))
			do
				if entity.prototype.resource_category ~= "basic-fluid" then
					resources[#resources + 1] = {
						name = entity.name,
						surface_index = surface.index,
						position = entity.position,
						amount = entity.amount,
						kind = "solid",
					}
				end
			end
			local tracker = ResourcePatches.new({
				next_id = 1,
				patches = {},
				cells = {},
				aliases = {},
			})
			local discovered = tracker:ingest(resources)
			local patch_ids = {}
			for _, item in ipairs(discovered) do
				patch_ids[#patch_ids + 1] = item.patch_id
			end
			local initial_ids = NauvisMiner.initial_spawn_patch_ids(tracker, patch_ids, spawn)
			assert(#initial_ids > 0, "expected a starting resource patch")
			local initial = {}
			for _, patch_id in ipairs(initial_ids) do
				initial[patch_id] = true
			end
			local nearby
			for _, patch in ipairs(tracker:all()) do
				if not initial[patch.id] then
					for _, member in ipairs(tracker:members(patch.id)) do
						if (member.x - spawn.x) ^ 2 + (member.y - spawn.y) ^ 2 <= 500 ^ 2 then
							nearby = member
							break
						end
					end
				end
				if nearby then
					break
				end
			end
			assert(nearby, "expected a non-starting patch inside the default restriction")

			local classifier = SpawnPatches.new({ windows = {} }, tracker)
			local surface_reference = { index = surface.index, name = surface.name }
			local force_reference = { index = force.index, name = force.name }
			assert(classifier:open(surface_reference, force_reference))
			assert(classifier:observe(surface_reference, force_reference, initial_ids))
			assert(classifier:close(surface_reference, force_reference))
			local zones = assert(Zones.new({ NauvisMiner.zone(500) }, {
				force_spawn = function()
					return spawn
				end,
			}))
			local compiler = Compiler.new()
			assert(compiler:replace({ NauvisMiner.rule() }))
			local evaluator = Evaluator.new({
				[NauvisMiner.INSIDE_PREDICATE] = function(context)
					return zones:contains(
						NauvisMiner.ZONE_ID,
						context,
						context.payload.entity.position
					)
				end,
				[NauvisMiner.SPAWN_PATCH_PREDICATE] = function(context)
					return classifier:has_spawn_resource(
						context.surface,
						context.force,
						context.payload.entity.mining_area
					)
				end,
			})
			local function evaluate(member)
				local candidate = {
					domain = "construction",
					kind = "entity-built",
					surface = surface_reference,
					force = force_reference,
					payload = {
						source = "player",
						entity = {
							name = "electric-mining-drill",
							type = "mining-drill",
							position = member,
							mining_area = {
								left_top = member,
								right_bottom = { x = member.x + 1, y = member.y + 1 },
							},
						},
					},
				}
				return assert(evaluator:evaluate(compiler:candidates(candidate), candidate))
			end
			local starting_member = tracker:members(initial_ids[1])[1]
			assert(evaluate(starting_member).outcome == "allow")
			assert(evaluate(nearby).outcome == "deny")
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
		name = "incremental discovery scans real solid and fluid resources",
		run = function(surface)
			local iron = assert(surface.create_entity({
				name = "iron-ore",
				position = { 20, 20 },
				amount = 1000,
			}))
			local oil = assert(surface.create_entity({
				name = "crude-oil",
				position = { 22, 20 },
				amount = 100000,
			}))
			local patch_state = { next_id = 1, patches = {}, cells = {}, aliases = {} }
			local tracker = ResourcePatches.new(patch_state)
			local discovery_state = {
				queue = {},
				head = 1,
				queued = {},
				processed = {},
				active = false,
				validation_pending = false,
				validation_warnings = {},
			}
			local active
			local discovery = ResourceDiscovery.new({
				state = function()
					return discovery_state
				end,
				scan = ResourceDiscovery.factorio_scanner(function()
					return surface
				end),
				ingest = function(resources)
					return tracker:ingest(resources)
				end,
				patch_for = function(index, name, position)
					return tracker:patch_for(index, name, position)
				end,
				all_patches = function()
					return tracker.all()
				end,
				expected_resources = function()
					return {}
				end,
				warn = function() end,
				set_active = function(value)
					active = value
				end,
				reset_cache = function() end,
			})
			assert(discovery:enqueue({
				surface_index = surface.index,
				chunk = { x = 0, y = 0 },
				area = { { 19, 19 }, { 23, 21 } },
			}))
			assert(active and discovery:process(1) == 1 and not active)
			local iron_id = discovery:cached_patch_for(surface.index, "iron-ore", iron.position)
			local oil_id = discovery:cached_patch_for(surface.index, "crude-oil", oil.position)
			assert(tracker:patch(iron_id).kind == "solid")
			assert(tracker:patch(oil_id).kind == "fluid")
			iron.destroy()
			oil.destroy()
		end,
	},
	{
		name = "built-in miner rule allows spawn patches and denies all off-patch paths",
		run = function(surface)
			local force = game.forces.player
			local spawn = force.get_spawn_position(surface)
			local patch_position = assert(
				surface.find_non_colliding_position(
					"electric-mining-drill",
					{ x = spawn.x + 20, y = spawn.y },
					20,
					1
				)
			)
			local denied_position = assert(
				surface.find_non_colliding_position(
					"electric-mining-drill",
					{ x = spawn.x, y = spawn.y + 20 },
					20,
					1
				)
			)
			for _, existing in
				ipairs(surface.find_entities_filtered({
					area = {
						{ patch_position.x - 3, patch_position.y - 3 },
						{ patch_position.x + 3, patch_position.y + 3 },
					},
					type = "resource",
				}))
			do
				existing.destroy()
			end
			local ore = assert(surface.create_entity({
				name = "iron-ore",
				position = patch_position,
				amount = 1000,
			}))
			local patch_state = { next_id = 1, patches = {}, cells = {}, aliases = {} }
			local tracker = ResourcePatches.new(patch_state)
			tracker:ingest({
				{
					name = ore.name,
					surface_index = surface.index,
					position = ore.position,
					amount = ore.amount,
					kind = "solid",
				},
			})
			local patch_id = tracker:patch_for(surface.index, ore.name, ore.position)
			local classifier = SpawnPatches.new({ windows = {} }, tracker)
			local surface_reference = { index = surface.index, name = surface.name }
			local force_reference = { index = force.index, name = force.name }
			assert(classifier:open(surface_reference, force_reference))
			assert(classifier:observe(surface_reference, force_reference, { patch_id }))
			assert(classifier:close(surface_reference, force_reference))

			local zones = assert(Zones.new({ NauvisMiner.zone(100) }, {
				force_spawn = function()
					return spawn
				end,
			}))
			local compiler = Compiler.new()
			assert(compiler:replace({ NauvisMiner.rule() }))
			local evaluator = Evaluator.new({
				[NauvisMiner.INSIDE_PREDICATE] = function(context)
					return zones:contains(
						NauvisMiner.ZONE_ID,
						context,
						context.payload.entity.position
					)
				end,
				[NauvisMiner.SPAWN_PATCH_PREDICATE] = function(context)
					return classifier:has_spawn_resource(
						context.surface,
						context.force,
						context.payload.entity.mining_area
					)
				end,
			})
			local adapters = AdapterRegistry.new()
			ConstructionAdapters.register(adapters)
			local notifications = {}
			local feedback = Feedback.new({
				history_limit = function()
					return 0
				end,
				notify_player = function(_, message)
					notifications[#notifications + 1] = { target = "player", message = message }
				end,
				notify_force = function(_, message)
					notifications[#notifications + 1] = { target = "force", message = message }
				end,
			})
			local rollback = Rollback.new({
				capture = function()
					return {}
				end,
				destroy = function(boundary)
					return boundary.entity.destroy()
				end,
				insert = function()
					return 0
				end,
				spill = function()
					return 0
				end,
			})
			local enforcer = Construction.new({
				adapters = adapters,
				compiler = compiler,
				evaluator = evaluator,
				feedback = function(result, context, boundary)
					feedback:emit(result, context, boundary)
				end,
				reject = function(boundary, _, context)
					assert(rollback:apply(boundary, context))
				end,
			})

			local allowed = assert(surface.create_entity({
				name = "electric-mining-drill",
				position = patch_position,
				force = force,
			}))
			local result = assert(enforcer:handle("on_built_entity", {
				entity = allowed,
				player_index = 1,
			}))
			assert(result.outcome == "allow" and allowed.valid)
			allowed.destroy()

			local function denied_entity(source, extra, entity_definition)
				local entity = assert(surface.create_entity(entity_definition))
				extra.entity = entity
				local denied = assert(enforcer:handle(source, extra))
				assert(denied.outcome == "deny" and denied.rule_id == NauvisMiner.RULE_ID)
				assert(not entity.valid)
			end
			denied_entity("on_built_entity", { player_index = 1 }, {
				name = "electric-mining-drill",
				position = denied_position,
				force = force,
			})
			denied_entity("on_robot_built_entity", { robot = { unit_number = 1 } }, {
				name = "electric-mining-drill",
				position = denied_position,
				force = force,
			})
			denied_entity("script_raised_built", {}, {
				name = "entity-ghost",
				inner_name = "electric-mining-drill",
				position = denied_position,
				force = force,
			})
			assert(#notifications == 3)
			assert(notifications[1].target == "player")
			assert(notifications[2].target == "force" and notifications[3].target == "force")
			assert(notifications[1].message:find(NauvisMiner.RULE_ID, 1, true))
			ore.destroy()
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
