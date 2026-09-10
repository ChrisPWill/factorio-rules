local M = {}

local function entity_payload(entity)
	local payload = {
		name = entity.name,
		type = entity.type,
		position = { x = entity.position.x, y = entity.position.y },
		direction = entity.direction,
		unit_number = entity.unit_number,
	}
	if entity.quality then
		payload.quality = entity.quality.name
	end
	if entity.type == "entity-ghost" then
		payload.ghost_name = entity.ghost_name
		payload.ghost_type = entity.ghost_type
	end
	return payload
end

local function player_actor(event)
	if not event.player_index then
		return nil
	end
	return { kind = "player", player_index = event.player_index }
end

local function robot_actor(event)
	if not event.robot then
		return nil
	end
	return { kind = "robot", unit_number = event.robot.unit_number }
end

local function normalize(source, actor_factory)
	return function(event)
		if type(event) ~= "table" or not event.entity or event.entity.valid == false then
			return nil, nil, { "event.entity: must be a valid built entity" }
		end
		local entity = event.entity
		local actor = actor_factory and actor_factory(event) or { kind = "script" }
		return {
			domain = "construction",
			kind = "entity-built",
			surface = { index = entity.surface.index, name = entity.surface.name },
			force = { index = entity.force.index, name = entity.force.name },
			actor = actor,
			metadata = { tick = event.tick },
			payload = { source = source, entity = entity_payload(entity) },
		},
			{
				event = event,
				entity = entity,
				robot = event.robot,
			},
			nil
	end
end

function M.register(registry)
	registry:register("on_built_entity", normalize("player", player_actor))
	registry:register("on_robot_built_entity", normalize("robot", robot_actor))
	registry:register("script_raised_built", normalize("script"))
	registry:register("script_raised_revive", normalize("script-revive"))
end

return M
