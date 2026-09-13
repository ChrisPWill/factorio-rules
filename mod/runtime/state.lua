local M = {}

local function new_resource_patches()
	return { schema_version = 1, next_id = 1, patches = {}, cells = {}, aliases = {} }
end

local function new_spawn_patches()
	return { schema_version = 1, windows = {} }
end

local INITIALIZERS = {
	rules = function()
		return {
			schema_version = 1,
			sources = {},
			patches = {},
			overrides = {},
			warnings = {},
			next_patch = 1,
			next_source = 1,
			framework_schema_version = 1,
			source_versions = {},
			override_versions = {},
			zones = {},
			next_zone_id = 1,
			next_rule_id = 1,
			rule_revisions = {},
		}
	end,
	violations = function()
		return {}
	end,
	overlays = function()
		return { players = {}, forced = {}, entries = {}, objects = {} }
	end,
	resource_patches = new_resource_patches,
	spawn_patches = new_spawn_patches,
	resource_discovery = function()
		return {
			schema_version = 1,
			queue = {},
			head = 1,
			queued = {},
			processed = {},
			active = false,
			validation_pending = false,
			validation_warnings = {},
		}
	end,
}

function M.initialize(target)
	-- Only lifecycle events that allow writes call this; on_load must not mutate storage.
	target = target or storage
	target.rules = target.rules or INITIALIZERS.rules()
	target.rules.sources = target.rules.sources or {}
	target.rules.patches = target.rules.patches or {}
	target.rules.overrides = target.rules.overrides or {}
	target.rules.warnings = target.rules.warnings or {}
	target.rules.next_patch = target.rules.next_patch or 1
	target.rules.next_source = target.rules.next_source or 1
	target.rules.framework_schema_version = target.rules.framework_schema_version or 1
	target.rules.source_versions = target.rules.source_versions or {}
	target.rules.override_versions = target.rules.override_versions or {}
	target.rules.zones = target.rules.zones or {}
	target.rules.next_zone_id = target.rules.next_zone_id or 1
	target.rules.next_rule_id = target.rules.next_rule_id or 1
	target.rules.rule_revisions = target.rules.rule_revisions or {}
	for index = 1, #target.rules.zones do
		local zone = target.rules.zones[index]
		local number = tonumber(
			type(zone.id) == "string" and zone.id:match("^factorio%-rules:zone%-(%d+)$") or nil
		)
		if number and number >= target.rules.next_zone_id then
			target.rules.next_zone_id = number + 1
		end
	end
	target.violations = target.violations or INITIALIZERS.violations()
	target.overlays = target.overlays or INITIALIZERS.overlays()
	target.resource_patches = target.resource_patches or INITIALIZERS.resource_patches()
	target.spawn_patches = target.spawn_patches or INITIALIZERS.spawn_patches()
	target.resource_discovery = target.resource_discovery or INITIALIZERS.resource_discovery()
	return target
end

function M.reset_resource_cache(target)
	target = target or storage
	target.resource_patches = new_resource_patches()
	target.spawn_patches = new_spawn_patches()
end

return M
