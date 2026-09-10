local AdapterRegistry = require("runtime.adapters.registry")
local construction = require("runtime.adapters.construction")

local function entity(overrides)
	local result = {
		valid = true,
		name = "electric-mining-drill",
		type = "mining-drill",
		position = { x = 12.5, y = -3 },
		direction = 2,
		unit_number = 99,
		quality = { name = "normal" },
		surface = { index = 1, name = "nauvis" },
		force = { index = 1, name = "player" },
	}
	for key, value in pairs(overrides or {}) do
		result[key] = value
	end
	return result
end

local function registry(capabilities)
	local result = AdapterRegistry.new({ capabilities = capabilities })
	construction.register(result)
	return result
end

return {
	{
		name = "normalizes every construction source through one context shape",
		run = function()
			for _, example in ipairs({
				{
					source = "on_built_entity",
					event = { tick = 1, player_index = 3 },
					actor = "player",
				},
				{
					source = "on_robot_built_entity",
					event = { tick = 2, robot = { unit_number = 8 } },
					actor = "robot",
				},
				{ source = "script_raised_built", event = { tick = 3 }, actor = "script" },
				{ source = "script_raised_revive", event = { tick = 4 }, actor = "script" },
			}) do
				local raw_entity = entity()
				example.event.entity = raw_entity
				local context, boundary, errors = registry():adapt(example.source, example.event)
				assert(context and not errors)
				assert(context.domain == "construction" and context.kind == "entity-built")
				assert(context.actor.kind == example.actor)
				assert(context.payload.entity.type == "mining-drill")
				assert(boundary.entity == raw_entity and boundary.event == example.event)
				assert(context.payload.entity ~= raw_entity)
			end
		end,
	},
	{
		name = "normalizes ghost identity without exposing the raw ghost",
		run = function()
			local raw_entity = entity({
				type = "entity-ghost",
				name = "entity-ghost",
				ghost_name = "electric-mining-drill",
				ghost_type = "mining-drill",
			})
			local context, boundary = registry():adapt("on_robot_built_entity", {
				tick = 2,
				robot = { unit_number = 8 },
				entity = raw_entity,
			})
			assert(context.payload.entity.ghost_type == "mining-drill")
			assert(context.payload.entity.ghost_name == "electric-mining-drill")
			assert(boundary.entity == raw_entity)
		end,
	},
	{
		name = "rejects invalid events at the adapter boundary",
		run = function()
			local context, _, errors = registry():adapt("on_built_entity", { player_index = 1 })
			assert(context == nil)
			assert(errors[1] == "event.entity: must be a valid built entity")
		end,
	},
	{
		name = "adds a new domain without changing registry or context",
		run = function()
			local adapters = registry()
			adapters:register("on_research_started", function(event)
				return {
					domain = "research",
					kind = "research-started",
					surface = { index = 1 },
					metadata = { tick = event.tick },
					payload = { technology = event.technology.name },
				}, { event = event }
			end)
			local context = assert(adapters:adapt("on_research_started", {
				tick = 5,
				technology = { name = "automation" },
			}))
			assert(context.domain == "research")
			assert(context.payload.technology == "automation")
		end,
	},
	{
		name = "passes the capability resolver into every adapted context",
		run = function()
			local capabilities = {
				resolve = function(_, name)
					return name == "zones" and { count = 2 } or nil
				end,
			}
			local context = assert(registry(capabilities):adapt("script_raised_built", {
				tick = 1,
				entity = entity(),
			}))
			assert(context:get_capability("zones").count == 2)
		end,
	},
}
