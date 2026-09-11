local AdapterRegistry = require("__factorio-rules__.runtime.adapters.registry")
local ConstructionAdapters = require("__factorio-rules__.runtime.adapters.construction")
local Compiler = require("__factorio-rules__.lib.rules.compiler")
local Evaluator = require("__factorio-rules__.lib.rules.evaluator")
local Construction = require("__factorio-rules__.runtime.construction")

local checks = {
	{
		name = "allowed entities can be placed and inspected",
		run = function(surface)
			local entity = surface.create_entity({
				name = "stone-furnace",
				position = { 0, 0 },
				force = "player",
			})
			assert(entity and entity.valid, "stone-furnace was not created")
			assert(entity.name == "stone-furnace", "unexpected entity prototype")
			assert(entity.position.x == 0 and entity.position.y == 0, "unexpected entity position")
		end,
	},
	{
		name = "denied player builds are removed by the enforcement path",
		run = function(surface)
			local adapters = AdapterRegistry.new()
			ConstructionAdapters.register(adapters)
			local compiler = Compiler.new()
			assert(compiler:replace({
				{
					id = "integration:deny-mining-drills",
					enabled = true,
					priority = 1,
					event = { domain = "construction", kind = "entity-built" },
					selector = { entity_types = { "mining-drill" } },
					scope = {},
					when = { predicate = "always" },
					effects = {
						primary = { type = "deny", reason = "integration policy" },
						actions = {},
					},
				},
			}))
			local evaluator = Evaluator.new({
				always = function()
					return true
				end,
			})
			local recorded = {}
			local enforcer = Construction.new({
				adapters = adapters,
				compiler = compiler,
				evaluator = evaluator,
				record = function(result)
					recorded[#recorded + 1] = result
				end,
				reject = function(boundary)
					boundary.entity.destroy()
				end,
			})
			local entity = surface.create_entity({
				name = "electric-mining-drill",
				position = { 2, 0 },
				force = "player",
			})
			assert(entity and entity.valid, "electric-mining-drill was not created")
			local result = assert(enforcer:handle("on_built_entity", { entity = entity }))
			assert(result.outcome == "deny", "mining drill should be denied")
			assert(not entity.valid, "denied mining drill should be removed")
			assert(#recorded == 1 and recorded[1].rule_id == "integration:deny-mining-drills")

			local ghost = surface.create_entity({
				name = "entity-ghost",
				inner_name = "electric-mining-drill",
				position = { 4, 0 },
				force = "player",
			})
			assert(ghost and ghost.valid, "electric-mining-drill ghost was not created")
			result = assert(enforcer:handle("script_raised_built", { entity = ghost }))
			assert(result.outcome == "deny", "mining drill ghost should be denied")
			assert(not ghost.valid, "denied mining drill ghost should be removed")
			assert(#recorded == 2, "ghost denial should be recorded")
		end,
	},
}

script.on_init(function()
	local surface = game.surfaces[1]
	for _, check in ipairs(checks) do
		local ok, err = pcall(check.run, surface)
		if not ok then
			error("[factorio-rules integration] FAIL: " .. check.name .. ": " .. tostring(err))
		end
		log("[factorio-rules integration] PASS: " .. check.name)
	end
	log("[factorio-rules integration] ALL TESTS PASSED")
end)
