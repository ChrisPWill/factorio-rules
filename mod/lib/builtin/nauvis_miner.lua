local M = {}

M.RULE_ID = "factorio-rules:nauvis-spawn-miners"
M.ZONE_ID = "factorio-rules:nauvis-spawn"
M.INSIDE_PREDICATE = "factorio-rules:inside-nauvis-spawn"
M.SPAWN_PATCH_PREDICATE = "factorio-rules:on-spawn-patch"
M.INITIAL_SPAWN_RADIUS = 128

function M.is_in_initial_spawn_area(center, position)
	local x = position.x - center.x
	local y = position.y - center.y
	return x * x + y * y <= M.INITIAL_SPAWN_RADIUS * M.INITIAL_SPAWN_RADIUS
end

function M.initial_spawn_patch_ids(tracker, patch_ids, center)
	local selected, seen = {}, {}
	for _, patch_id in ipairs(patch_ids) do
		if not seen[patch_id] then
			seen[patch_id] = true
			for _, member in ipairs(tracker:members(patch_id) or {}) do
				if M.is_in_initial_spawn_area(center, member) then
					selected[#selected + 1] = patch_id
					break
				end
			end
		end
	end
	return selected
end

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
