local M = {}

local function contains(values, expected)
	for _, value in ipairs(values or {}) do
		if value == expected then
			return true
		end
	end
	return false
end

function M.matches(rule, context)
	if rule.event.domain ~= context.domain or rule.event.kind ~= context.kind then
		return false, "event"
	end

	local selector = rule.selector
	local entity = context.payload.entity
	if selector.entity_types then
		local entity_type = entity and (entity.ghost_type or entity.type)
		if not contains(selector.entity_types, entity_type) then
			return false, "entity-type"
		end
	end
	if selector.entity_names then
		local entity_name = entity and (entity.ghost_name or entity.name)
		if not contains(selector.entity_names, entity_name) then
			return false, "entity-name"
		end
	end
	if selector.sources and not contains(selector.sources, context.payload.source) then
		return false, "source"
	end

	local scope = rule.scope
	if
		scope.surfaces
		and not contains(scope.surfaces, context.surface.name)
		and not contains(scope.surfaces, context.surface.index)
	then
		return false, "surface"
	end
	if scope.forces then
		local force = context.force
		if
			not force
			or (not contains(scope.forces, force.name) and not contains(scope.forces, force.index))
		then
			return false, "force"
		end
	end
	return true, nil
end

return M
