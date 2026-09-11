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
	player_indices = function()
		local result = {}
		for _, player in pairs(game.players) do
			result[#result + 1] = player.index
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

local function generated_chunk_jobs()
	local jobs = {}
	for _, surface in pairs(game.surfaces) do
		for chunk in surface.get_chunks() do
			jobs[#jobs + 1] = {
				surface_index = surface.index,
				chunk = { x = chunk.x, y = chunk.y },
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
	return { { surface_index = surface.index, names = names } }
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
	patch_for = function(surface_index, resource_name, position)
		return patch_tracker():patch_for(surface_index, resource_name, position)
	end,
	all_patches = function()
		return patch_tracker().all()
	end,
	expected_resources = expected_resources,
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
local enforcer = Construction.new({
	adapters = adapters,
	compiler = compiler,
	evaluator = Evaluator.new({}),
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
	overlays:replace({})
	discovery:seed(generated_chunk_jobs())
	logger.debug("Initialized persistent state")
end)

script.on_configuration_changed(function()
	state.initialize()
	overlays:replace({})
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
