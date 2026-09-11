local M = {}

M.RULE_ID = "factorio-rules:nauvis-spawn-miners"
M.ZONE_ID = "factorio-rules:nauvis-spawn"
M.INSIDE_PREDICATE = "factorio-rules:inside-nauvis-spawn"
M.SPAWN_PATCH_PREDICATE = "factorio-rules:on-spawn-patch"

function M.zone(radius)
	return {
		id = M.ZONE_ID,
		shape = { type = "circle", radius = radius },
		anchor = { type = "force-spawn" },
		scope = { surfaces = { "nauvis" } },
	}
end

function M.rule()
	return {
		schema_version = 1,
		definition_version = 1,
		id = M.RULE_ID,
		enabled = true,
		priority = 100,
		provenance = { source = "factorio-rules", kind = "builtin" },
		event = { domain = "construction", kind = "entity-built" },
		selector = { entity_types = { "mining-drill" } },
		scope = { surfaces = { "nauvis" } },
		when = {
			all = {
				{ predicate = M.INSIDE_PREDICATE },
				{ ["not"] = { predicate = M.SPAWN_PATCH_PREDICATE } },
			},
		},
		effects = {
			primary = {
				type = "deny",
				reason = "Mining drills inside the Nauvis spawn zone must be on a spawn resource patch.",
			},
			actions = {},
		},
	}
end

return M
