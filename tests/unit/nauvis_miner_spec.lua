local Compiler = require("lib.rules.compiler")
local Evaluator = require("lib.rules.evaluator")
local NauvisMiner = require("lib.builtin.nauvis_miner")
local Schema = require("lib.rules.schema")
local Zones = require("lib.zones")

local function context(position, on_patch, surface_name)
	return {
		domain = "construction",
		kind = "entity-built",
		surface = { index = 1, name = surface_name or "nauvis" },
		force = { index = 1, name = "player" },
		payload = {
			source = "player",
			entity = { name = "electric-mining-drill", type = "mining-drill", position = position },
		},
		metadata = { on_patch = on_patch },
	}
end

return {
	{
		name = "defines a valid canonical built-in rule",
		run = function()
			local normalized, errors = Schema.normalize(NauvisMiner.rule())
			assert(normalized and not errors and normalized.id == NauvisMiner.RULE_ID)
		end,
	},
	{
		name = "denies only off-patch miners inside the configured zone",
		run = function()
			local zones = assert(Zones.new({ NauvisMiner.zone(500) }, {
				force_spawn = function()
					return { x = 0, y = 0 }
				end,
			}))
			local evaluator = Evaluator.new({
				[NauvisMiner.INSIDE_PREDICATE] = function(candidate)
					return zones:contains(
						NauvisMiner.ZONE_ID,
						candidate,
						candidate.payload.entity.position
					)
				end,
				[NauvisMiner.SPAWN_PATCH_PREDICATE] = function(candidate)
					return candidate.metadata.on_patch
				end,
			})
			local compiler = Compiler.new()
			assert(compiler:replace({ NauvisMiner.rule() }))
			for _, example in ipairs({
				{ position = { x = 100, y = 0 }, on_patch = false, expected = "deny" },
				{ position = { x = 100, y = 0 }, on_patch = true, expected = "allow" },
				{ position = { x = 501, y = 0 }, on_patch = false, expected = "allow" },
			}) do
				local candidate = context(example.position, example.on_patch)
				local result = assert(evaluator:evaluate(compiler:candidates(candidate), candidate))
				assert(result.outcome == example.expected)
			end
			local off_surface = context({ x = 0, y = 0 }, false, "vulcanus")
			assert(#compiler:candidates(off_surface) == 0)
		end,
	},
}
