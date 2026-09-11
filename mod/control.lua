local state = require("runtime.state")
local logger = require("runtime.logger")
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

local adapters = AdapterRegistry.new()
ConstructionAdapters.register(adapters)
local compiler = Compiler.new()
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
		return storage.violations
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
})
local overlays = Overlays.factorio({
	state = function()
		return storage.overlays
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
	return ResourcePatches.new(storage.resource_patches)
end

local function spawn_classifier()
	return SpawnPatches.new(storage.spawn_patches, patch_tracker())
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
	return assert(Zones.new({
		NauvisMiner.zone(settings.global["factorio-rules-nauvis-spawn-radius"].value),
	}, {
		force_spawn = function(surface_reference, force_reference)
			local surface = assert(game.get_surface(surface_reference.index), "surface unavailable")
			local force = assert(game.forces[force_reference.index], "force unavailable")
			return force.get_spawn_position(surface)
		end,
	}))
end

local zones = zone_registry()
assert(compiler:replace({ NauvisMiner.rule() }))

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
	return entries
end

local function configure_policy()
	zones = zone_registry()
	local changed, errors = compiler:replace({ NauvisMiner.rule() })
	assert(changed ~= nil, errors and table.concat(errors, "; "))
	assert(overlays:replace(overlay_entries()))
end

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
			assert(classifier:observe(target.surface, target.force, ids))
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
		return storage.resource_discovery
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
		storage.resource_patches = {
			schema_version = 1,
			next_id = 1,
			patches = {},
			cells = {},
			aliases = {},
		}
		storage.spawn_patches = { schema_version = 1, windows = {} }
	end,
})
local evaluator = Evaluator.new({
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
				right_bottom = { x = math.floor(position.x) + 1, y = math.floor(position.y) + 1 },
			}
		local matched = spawn_classifier():has_spawn_resource(context.surface, context.force, area)
		return matched == nil or matched
	end,
})
local enforcer = Construction.new({
	adapters = adapters,
	compiler = compiler,
	evaluator = evaluator,
	record = function(result)
		storage.last_enforcement = result
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
	end)
)

script.on_init(function()
	state.initialize()
	prepare_spawn_classification()
	configure_policy()
	discovery:seed(generated_chunk_jobs())
	logger.debug("Initialized persistent state")
end)

script.on_configuration_changed(function()
	state.initialize()
	prepare_spawn_classification()
	configure_policy()
	discovery:seed(generated_chunk_jobs())
	logger.debug("Configuration updated")
end)

script.on_event(defines.events.on_lua_shortcut, function(event)
	if event.prototype_name == Overlays.SHORTCUT_NAME then
		overlays:toggle(event.player_index)
	end
end)

script.on_event(defines.events.on_player_joined_game, function(event)
	overlays:sync_player(event.player_index)
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
