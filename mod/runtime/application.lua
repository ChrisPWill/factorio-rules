local State = require("runtime.state")
local Logger = require("runtime.logger")
local AdapterRegistry = require("runtime.adapters.registry")
local ConstructionAdapters = require("runtime.adapters.construction")
local Compiler = require("lib.rules.compiler")
local Evaluator = require("lib.rules.evaluator")
local Construction = require("runtime.construction")
local Rollback = require("runtime.rollback")
local Feedback = require("runtime.feedback")
local Overlays = require("runtime.overlays")
local ResourcePatches = require("lib.resource_patches")
local ResourceDiscovery = require("runtime.resource_discovery")
local SpawnPatches = require("lib.spawn_patches")
local Zones = require("lib.zones")
local NauvisMiner = require("lib.builtin.nauvis_miner")
local RuleRegistry = require("lib.rules.registry")
local Extensions = require("runtime.extensions")
local RuleUI = require("runtime.rule_ui")
local ZoneEditing = require("runtime.zone_editing")
local Catalogue = require("lib.rules.catalogue")
local ZoneStore = require("runtime.zone_store")
local RuleAuthoring = require("lib.rules.authoring")
local Permissions = require("runtime.permissions")

local M = {}

function M.register(runtime)
	assert(type(runtime) == "table", "Factorio runtime is required")
	assert(type(runtime.game) == "function", "Factorio game provider is required")
	assert(type(runtime.storage) == "function", "Factorio storage provider is required")
	assert(type(runtime.settings) == "function", "Factorio settings provider is required")
	assert(type(runtime.rendering) == "function", "Factorio rendering provider is required")
	assert(type(runtime.log) == "function", "Factorio log provider is required")
	-- Factorio creates game after loading control.lua, so resolve it only inside runtime callbacks.
	local game = setmetatable({}, {
		__index = function(_, key)
			return assert(runtime.game(), "Factorio game API is unavailable")[key]
		end,
	})
	local function storage()
		return assert(runtime.storage(), "Factorio storage is unavailable")
	end
	local settings = setmetatable({}, {
		__index = function(_, key)
			return assert(runtime.settings(), "Factorio settings are unavailable")[key]
		end,
	})
	local rendering = setmetatable({}, {
		__index = function(_, key)
			return assert(runtime.rendering(), "Factorio rendering API is unavailable")[key]
		end,
	})
	local script = assert(runtime.script, "Factorio script API is required")
	local defines = assert(runtime.defines, "Factorio defines are required")
	local remote = assert(runtime.remote, "Factorio remote API is required")
	local log = function(message)
		return assert(runtime.log(), "Factorio log function is unavailable")(message)
	end
	local function provider_context(context)
		return {
			domain = context.domain,
			kind = context.kind,
			surface = context.surface,
			force = context.force,
			actor = context.actor,
			metadata = context.metadata,
			payload = context.payload,
		}
	end
	local source_rules = runtime.source_rules or function()
		return { NauvisMiner.rule() }
	end
	assert(type(source_rules) == "function", "source rule provider must be a function")

	local logger = Logger.new(settings, log)
	local permissions = Permissions.new(function(index)
		return game.get_player(index)
	end)
	local extensions = Extensions.new({
		resolve = function(descriptor, kind)
			assert(type(descriptor) == "table", kind .. " provider descriptor is required")
			local interface = assert(descriptor.interface, "provider interface is required")
			local function_name =
				assert(descriptor.function_name, "provider function name is required")
			assert(type(interface) == "string" and type(function_name) == "string")
			assert(remote.interfaces[interface], "unknown provider interface " .. interface)
			assert(
				remote.interfaces[interface][function_name],
				"unknown provider function " .. function_name
			)
			if kind == "predicate" then
				return function(context, condition)
					return remote.call(
						interface,
						function_name,
						provider_context(context),
						condition
					)
				end
			end
			return function(action, entry, context)
				return remote.call(
					interface,
					function_name,
					action,
					entry,
					provider_context(context)
				)
			end
		end,
	})

	local adapters = AdapterRegistry.new()
	ConstructionAdapters.register(adapters)
	local compiler = Compiler.new({
		predicate_requirements = extensions:predicate_requirements(),
		action_requirements = extensions:action_requirements(),
	})
	local rule_registry
	local authoring
	local rollback = Rollback.factorio({
		get_player = function(index)
			return game.get_player(index)
		end,
		get_surface = function(index)
			return game.get_surface(index)
		end,
	}, defines)
	local feedback = Feedback.factorio({
		history = function()
			return storage().violations
		end,
		history_limit = function()
			return settings.global["factorio-rules-violation-history-limit"].value
		end,
		get_player = function(index)
			return game.get_player(index)
		end,
		get_force = function(index)
			return game.forces[index]
		end,
		actions = extensions:actions(),
	})
	local overlays = Overlays.factorio({
		state = function()
			return storage().overlays
		end,
		player_indices = function(entry)
			local result = {}
			for _, player in pairs(game.players) do
				if not entry.force or player.force.index == entry.force.index then
					result[#result + 1] = player.index
				end
			end
			return result
		end,
		is_admin = function(index)
			local player = game.get_player(index)
			return player and player.admin
		end,
		set_shortcut = function(index, toggled)
			local player = game.get_player(index)
			if player then
				player.set_shortcut_toggled(Overlays.SHORTCUT_NAME, toggled)
			end
		end,
	}, rendering)

	local function patch_tracker()
		return ResourcePatches.new(storage().resource_patches)
	end

	local function spawn_classifier()
		return SpawnPatches.new(storage().spawn_patches, patch_tracker())
	end

	local function spawn_targets()
		local surface = game.surfaces.nauvis
		if not surface then
			return {}
		end
		local targets = {}
		for _, force in pairs(game.forces) do
			if force.name ~= "enemy" and force.name ~= "neutral" then
				targets[#targets + 1] = {
					surface = { index = surface.index, name = surface.name },
					force = { index = force.index, name = force.name },
				}
			end
		end
		table.sort(targets, function(left, right)
			return left.force.index < right.force.index
		end)
		return targets
	end

	local function zone_registry()
		local definitions = {
			NauvisMiner.zone(settings.global["factorio-rules-nauvis-spawn-radius"].value),
		}
		for _, zone in ipairs(storage().rules.zones or {}) do
			definitions[#definitions + 1] = zone
		end
		return assert(Zones.new(definitions, {
			force_spawn = function(surface_reference, force_reference)
				local surface =
					assert(game.get_surface(surface_reference.index), "surface unavailable")
				local force = assert(game.forces[force_reference.index], "force unavailable")
				return force.get_spawn_position(surface)
			end,
		}))
	end

	local zones
	local zone_editor
	local catalogue

	local function overlay_entries()
		local entries = {}
		for _, target in ipairs(spawn_targets()) do
			local zone, center = zones:resolve(NauvisMiner.ZONE_ID, target)
			if zone then
				entries[#entries + 1] = {
					key = NauvisMiner.ZONE_ID
						.. "@"
						.. target.surface.index
						.. ":"
						.. target.force.index,
					zone_id = zone.id,
					rule_ids = { NauvisMiner.RULE_ID },
					shape = zone.shape,
					center = center,
					surface = target.surface,
					force = target.force,
				}
			end
		end
		for _, definition in ipairs(storage().rules.zones or {}) do
			for _, target in ipairs(spawn_targets()) do
				local zone, center = zones:resolve(definition.id, target)
				if zone then
					entries[#entries + 1] = {
						key = definition.id
							.. "@"
							.. target.surface.index
							.. ":"
							.. target.force.index,
						zone_id = zone.id,
						shape = zone.shape,
						center = center,
						surface = target.surface,
						force = target.force,
					}
				end
			end
		end
		return entries
	end

	local function configure_policy()
		zones = zone_registry()
		if not rule_registry then
			rule_registry = RuleRegistry.new(storage().rules)
		end
		if not authoring then
			authoring = RuleAuthoring.new(storage().rules, {
				authorize = function(context)
					return permissions:authorize(context)
				end,
				validate = function(rule)
					return catalogue:validate(rule)
				end,
				stage = function(rules)
					local staged_compiler = Compiler.new({
						predicate_requirements = extensions:predicate_requirements(),
						action_requirements = extensions:action_requirements(),
					})
					local _, errors = staged_compiler:replace(rules)
					if errors then
						return nil, errors
					end
					return true
				end,
			})
		end
		local migrated, migration_errors = rule_registry:migrate({
			framework_schema_version = 1,
			source_versions = { ["factorio-rules"] = "0.1.0" },
		})
		assert(migrated, migration_errors and table.concat(migration_errors, "; "))
		local synced, sync_errors = rule_registry:sync_source("factorio-rules", source_rules())
		assert(synced, sync_errors and table.concat(sync_errors, "; "))
		local effective, registry_errors, warnings = rule_registry:effective()
		assert(effective, registry_errors and table.concat(registry_errors, "; "))
		local persisted_warnings = rule_registry:state().warnings
		for index = #persisted_warnings, 1, -1 do
			persisted_warnings[index] = nil
		end
		for _, warning in ipairs(warnings) do
			persisted_warnings[#persisted_warnings + 1] = warning
		end
		local known_zones = {}
		for _, zone in ipairs(zones.list()) do
			known_zones[zone.id] = true
		end
		for _, rule in ipairs(effective) do
			for id in pairs(Zones.referenced_ids(rule.when)) do
				if not known_zones[id] then
					rule.enabled = false
					persisted_warnings[#persisted_warnings + 1] = "rule "
						.. rule.id
						.. ": unavailable zone "
						.. id
				end
			end
		end
		local changed, errors = compiler:replace(effective)
		assert(changed ~= nil, errors and table.concat(errors, "; "))
		assert(overlays:replace(overlay_entries()))
	end

	local rule_ui = RuleUI.new({
		get_player = function(index)
			return game.get_player(index)
		end,
		effective_rules = function()
			return authoring:list()
		end,
		mutate = function(commands, context)
			return authoring:execute(commands, context)
		end,
		can_edit = function(index)
			return permissions:can_edit(index)
		end,
		revision = function(id)
			return authoring:revision(id)
		end,
		delete_unused_zones = function()
			local kept, removed = Zones.delete_unused(
				storage().rules.zones,
				{ storage().rules.sources, storage().rules.patches, storage().rules.overrides }
			)
			for _, zone_id in ipairs(removed) do
				storage().overlays.forced[zone_id] = nil
			end
			storage().rules.zones = kept
			return true, nil
		end,
		edit_zone = function(index, id)
			return zone_editor:begin(index, id)
		end,
		rename_zone = function(id, name)
			local store = ZoneStore.new(storage().rules)
			local zone = store:get(id)
			if not zone then
				return nil, { "unknown zone" }
			end
			zone.name = name
			return store:save(zone)
		end,
		zones = function()
			return storage().rules.zones or {}
		end,
		zone_summary = function()
			local _, removed = Zones.delete_unused(
				storage().rules.zones,
				{ storage().rules.sources, storage().rules.patches, storage().rules.overrides }
			)
			return { unused = #removed }
		end,
		rebuild = configure_policy,
	})
	zone_editor = ZoneEditing.new({
		get_player = function(index)
			return game.get_player(index)
		end,
		get = function(id)
			return ZoneStore.new(storage().rules):get(id)
		end,
		authorize = function(index)
			return permissions:can_edit(index), "only an admin can edit rules"
		end,
		save = function(zone)
			return ZoneStore.new(storage().rules):save(zone)
		end,
		rebuild = configure_policy,
	})

	local function prepare_spawn_classification()
		local classifier = spawn_classifier()
		for _, target in ipairs(spawn_targets()) do
			if classifier:status(target.surface, target.force) == "unclassified" then
				assert(classifier:open(target.surface, target.force))
			end
		end
	end

	local function observe_spawn_patches(job, discovered)
		if not job.initial then
			return
		end
		local classifier = spawn_classifier()
		for _, target in ipairs(spawn_targets()) do
			if
				target.surface.index == job.surface_index
				and classifier:status(target.surface, target.force) == "open"
			then
				local ids = {}
				for _, item in ipairs(discovered) do
					ids[#ids + 1] = item.patch_id
				end
				local _, center = zones:resolve(NauvisMiner.ZONE_ID, target)
				local spawn_ids = NauvisMiner.initial_spawn_patch_ids(patch_tracker(), ids, center)
				assert(classifier:observe(target.surface, target.force, spawn_ids))
			end
		end
	end

	local function finish_spawn_classification()
		local classifier = spawn_classifier()
		for _, target in ipairs(spawn_targets()) do
			if classifier:status(target.surface, target.force) == "open" then
				assert(classifier:close(target.surface, target.force))
			end
		end
	end

	local function generated_chunk_jobs()
		local jobs = {}
		for _, surface in pairs(game.surfaces) do
			for chunk in surface.get_chunks() do
				jobs[#jobs + 1] = {
					surface_index = surface.index,
					chunk = { x = chunk.x, y = chunk.y },
					initial = true,
					area = {
						left_top = { x = chunk.x * 32, y = chunk.y * 32 },
						right_bottom = { x = (chunk.x + 1) * 32, y = (chunk.y + 1) * 32 },
					},
				}
			end
		end
		return jobs
	end

	local function expected_resources()
		local surface = game.surfaces.nauvis
		if not surface then
			return {}
		end
		local names = {}
		local configured = settings.global["factorio-rules-expected-spawn-resources"].value
		for name in configured:gmatch("[^,]+") do
			name = name:match("^%s*(.-)%s*$")
			if name ~= "" then
				names[#names + 1] = name
			end
		end
		local force = game.forces.player
		return {
			{
				surface_index = surface.index,
				surface = { index = surface.index, name = surface.name },
				force = { index = force.index, name = force.name },
				names = names,
			},
		}
	end

	local discovery
	local function process_resource_discovery()
		discovery:process(2)
	end

	discovery = ResourceDiscovery.new({
		state = function()
			return storage().resource_discovery
		end,
		scan = ResourceDiscovery.factorio_scanner(function(index)
			return game.get_surface(index)
		end),
		ingest = function(resources)
			return patch_tracker():ingest(resources)
		end,
		on_discovered = observe_spawn_patches,
		on_idle = finish_spawn_classification,
		patch_for = function(surface_index, resource_name, position)
			return patch_tracker():patch_for(surface_index, resource_name, position)
		end,
		all_patches = function()
			return patch_tracker().all()
		end,
		expected_resources = expected_resources,
		has_expected_resource = function(expectation, resource_name)
			return spawn_classifier():has_resource_name(
				expectation.surface,
				expectation.force,
				resource_name
			)
		end,
		warn = function(message)
			log("[factorio-rules] warning: " .. message)
		end,
		set_active = function(active)
			script.on_nth_tick(1, active and process_resource_discovery or nil)
		end,
		reset_cache = function()
			State.reset_resource_cache(storage())
		end,
	})
	local predicates = setmetatable(extensions:predicates(), {
		__index = {
			[NauvisMiner.INSIDE_PREDICATE] = function(context)
				local inside, err =
					zones:contains(NauvisMiner.ZONE_ID, context, context.payload.entity.position)
				assert(err == nil, err)
				return inside
			end,
			[NauvisMiner.SPAWN_PATCH_PREDICATE] = function(context)
				local entity = context.payload.entity
				local position = entity.position
				local area = entity.mining_area
					or {
						left_top = { x = math.floor(position.x), y = math.floor(position.y) },
						right_bottom = {
							x = math.floor(position.x) + 1,
							y = math.floor(position.y) + 1,
						},
					}
				local matched =
					spawn_classifier():has_spawn_resource(context.surface, context.force, area)
				return matched == nil or matched
			end,
		},
	})
	predicates[Catalogue.ALWAYS] = function()
		return true
	end
	catalogue = Catalogue.new({
		predicates = predicates,
		actions = extensions:actions(),
		reference_exists = function(kind, name)
			if kind == "entity" or kind == "entity_type" then
				local entities = runtime.prototypes and runtime.prototypes().entity or {}
				if kind == "entity" then
					return entities[name] ~= nil
				end
				for _, prototype in pairs(entities) do
					if prototype.type == name then
						return true
					end
				end
			end
			if kind == "surface" then
				return game.surfaces[name] ~= nil
			end
			if kind == "force" then
				return game.forces[name] ~= nil
			end
			if kind == "zone" then
				for _, zone in ipairs(zones.list()) do
					if zone.id == name then
						return true
					end
				end
			end
			return false
		end,
	})
	predicates[Catalogue.INSIDE_ZONE] = function(context, condition)
		return zones:contains(condition.zone_id, context, context.payload.entity.position)
	end
	local evaluator = Evaluator.new(predicates, {
		applicable = function(rule, context)
			for id in pairs(Zones.referenced_ids(rule.when)) do
				if not zones:resolve(id, context) then
					return false
				end
			end
			return true
		end,
	})
	local enforcer = Construction.new({
		adapters = adapters,
		compiler = compiler,
		evaluator = evaluator,
		services = {},
		record = function(result)
			storage().last_enforcement = result
		end,
		feedback = function(result, context, boundary)
			feedback:emit(result, context, boundary)
		end,
		reject = function(boundary, _, context)
			local _, errors = rollback:apply(boundary, context)
			if errors then
				error(table.concat(errors, "; "))
			end
		end,
	})
	Construction.register_construction_events(script, defines, enforcer)
	remote.add_interface(
		"factorio_rules",
		Construction.cooperative_interface(enforcer, function()
			return game.tick
		end, {
			register_rule = function(rule)
				local ok, errors = rule_registry:register(rule)
				if ok then
					configure_policy()
				end
				return ok, errors
			end,
			replace_rule = function(rule)
				local ok, errors = rule_registry:replace(rule)
				if ok then
					configure_policy()
				end
				return ok, errors
			end,
			override_rule = function(id, fields, source)
				return rule_registry:override(id, fields, source)
			end,
			replace_external_rule = function(id, rule, source)
				return rule_registry:replace_external(id, rule, source)
			end,
			set_rule_override = function(id, fields)
				return rule_registry:set_override(id, fields)
			end,
			mutate_rules = function(commands)
				local result, errors = authoring:execute(commands, { origin = "remote" })
				if result then
					configure_policy()
				end
				return result, errors
			end,
			migrate_rules = function(options)
				return rule_registry:migrate(options)
			end,
			register_predicate_provider = function(name, descriptor, requirement)
				local result, errors =
					extensions:register_predicate_provider(name, descriptor, requirement)
				if result then
					configure_policy()
				end
				return result, errors
			end,
			register_action_provider = function(name, descriptor, requirement)
				local result, errors =
					extensions:register_action_provider(name, descriptor, requirement)
				if result then
					configure_policy()
				end
				return result, errors
			end,
			list_zones = function()
				return zones.list()
			end,
			save_zone = function(zone)
				if zone.id == NauvisMiner.ZONE_ID then
					return nil, { "built-in zone is read-only" }
				end
				local id, errors = ZoneStore.new(storage().rules):save(zone)
				if id then
					configure_policy()
				end
				return id, errors
			end,
			authoring_catalogue = function()
				return catalogue.describe()
			end,
			validate_authored_rule = function(rule)
				return catalogue:validate(rule)
			end,
			effective_rules = function()
				return rule_registry:effective()
			end,
			rule_warnings = function()
				return rule_registry:warnings()
			end,
		})
	)

	local function activate(message)
		State.initialize(storage())
		prepare_spawn_classification()
		configure_policy()
		for _, player in pairs(game.players) do
			rule_ui:ensure_button(player.index)
		end
		discovery:seed(generated_chunk_jobs())
		logger.debug(message)
	end

	-- on_load cannot write storage. Recreate only the in-memory policy graph so
	-- persisted rules remain authoritative while derived indexes are rebuilt.
	local function rebuild_loaded_policy()
		zones = zone_registry()
		rule_registry = RuleRegistry.load(storage().rules)
		authoring = RuleAuthoring.new(storage().rules, {
			authorize = function(context)
				return permissions:authorize(context)
			end,
			validate = function(rule)
				return catalogue:validate(rule)
			end,
			stage = function(rules)
				local staged_compiler = Compiler.new({
					predicate_requirements = extensions:predicate_requirements(),
					action_requirements = extensions:action_requirements(),
				})
				local _, errors = staged_compiler:replace(rules)
				if errors then
					return nil, errors
				end
				return true
			end,
		})
		local effective, errors = rule_registry:effective()
		assert(effective, errors and table.concat(errors, "; "))
		local changed, compile_errors = compiler:replace(effective)
		assert(changed ~= nil, compile_errors and table.concat(compile_errors, "; "))
		discovery:resume()
	end

	script.on_init(function()
		activate("Initialized persistent state")
	end)
	script.on_configuration_changed(function()
		activate("Configuration updated")
	end)
	script.on_load(rebuild_loaded_policy)

	script.on_event(defines.events.on_lua_shortcut, function(event)
		if event.prototype_name == Overlays.SHORTCUT_NAME then
			overlays:toggle(event.player_index)
		elseif event.prototype_name == RuleUI.SHORTCUT_NAME then
			rule_ui:open(event.player_index)
		elseif event.prototype_name == ZoneEditing.SHORTCUT_NAME then
			zone_editor:begin(event.player_index)
		end
	end)
	if defines.events.on_player_selected_area then
		script.on_event(defines.events.on_player_selected_area, function(event)
			zone_editor:select(event)
		end)
	end
	if defines.events.on_player_alt_selected_area then
		script.on_event(defines.events.on_player_alt_selected_area, function(event)
			zone_editor:select(event)
		end)
	end
	if defines.events.on_gui_click then
		script.on_event(defines.events.on_gui_click, function(event)
			rule_ui:handle_click(event)
		end)
	end
	if defines.events.on_gui_confirmed then
		script.on_event(defines.events.on_gui_confirmed, function(event)
			rule_ui:handle_click(event)
		end)
	end
	if defines.events.on_gui_checked_state_changed then
		script.on_event(defines.events.on_gui_checked_state_changed, function(event)
			rule_ui:handle_click(event)
		end)
	end

	script.on_event(defines.events.on_player_joined_game, function(event)
		overlays:sync_player(event.player_index)
		rule_ui:ensure_button(event.player_index)
	end)

	script.on_event(defines.events.on_chunk_generated, function(event)
		discovery:enqueue({
			surface_index = event.surface.index,
			chunk = { x = event.position.x, y = event.position.y },
			area = event.area,
		})
	end)

	script.on_event(defines.events.on_runtime_mod_setting_changed, function(event)
		if event.setting == "factorio-rules-nauvis-spawn-radius" then
			configure_policy()
		end
	end)
end

return M
