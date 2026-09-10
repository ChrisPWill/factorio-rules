local Context = require("lib.rules.context")

local function valid_spec()
	return {
		domain = "construction",
		kind = "entity-built",
		surface = { index = 1, name = "nauvis" },
		force = { index = 1, name = "player" },
		actor = { kind = "player", player_index = 1 },
		metadata = { tick = 42 },
		payload = {
			source = "player",
			entity = {
				name = "electric-mining-drill",
				type = "mining-drill",
				position = { x = 10, y = 20 },
			},
		},
	}
end

local function contains(errors, text)
	for _, message in ipairs(errors or {}) do
		if message:find(text, 1, true) then
			return true
		end
	end
	return false
end

return {
	{
		name = "copies normalized common and domain data",
		run = function()
			local spec = valid_spec()
			local context, errors = Context.new(spec)
			assert(context and not errors)
			assert(context.domain == "construction")
			assert(context.payload.entity.type == "mining-drill")
			spec.payload.entity.position.x = 999
			assert(context.payload.entity.position.x == 10)
		end,
	},
	{
		name = "rejects raw objects and callbacks in normalized data",
		run = function()
			local spec = valid_spec()
			spec.payload.raw_entity = function() end
			local context, errors = Context.new(spec)
			assert(context == nil)
			assert(
				contains(errors, "context.payload.raw_entity: must contain only serializable data")
			)
		end,
	},
	{
		name = "resolves expensive capabilities lazily and once",
		run = function()
			local calls = 0
			local spec = valid_spec()
			spec.capabilities = {
				resolve = function(_, name, context)
					calls = calls + 1
					assert(name == "resource-patch")
					assert(context.surface.index == 1)
					return { patch_id = 7 }
				end,
			}
			local context = assert(Context.new(spec))
			assert(calls == 0)
			assert(context:get_capability("resource-patch").patch_id == 7)
			assert(context:get_capability("resource-patch").patch_id == 7)
			assert(calls == 1)
		end,
	},
	{
		name = "reports normalization boundary errors",
		run = function()
			local spec = valid_spec()
			spec.domain = nil
			spec.surface.index = 0
			local context, errors = Context.new(spec)
			assert(context == nil)
			assert(contains(errors, "context.domain:"))
			assert(contains(errors, "context.surface.index:"))
		end,
	},
}
