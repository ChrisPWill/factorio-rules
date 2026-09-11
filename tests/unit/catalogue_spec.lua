local Catalogue = require("lib.rules.catalogue")
local Miner = require("lib.builtin.nauvis_miner")
local Evaluator = require("lib.rules.evaluator")
local Schema = require("lib.rules.schema")

local function catalogue()
	return Catalogue.new({
		predicates = {
			[Catalogue.ALWAYS] = function()
				return true
			end,
			[Miner.INSIDE_PREDICATE] = function()
				return true
			end,
			[Miner.SPAWN_PATCH_PREDICATE] = function()
				return false
			end,
		},
		reference_exists = function(_, name)
			return name == "nauvis" or name == "mining-drill"
		end,
	})
end

return {
	{
		name = "templates advertise only executable behavior and produce canonical outcomes",
		run = function()
			local owner = catalogue()
			local description = owner.describe()
			assert(not description.predicates[Catalogue.INSIDE_ZONE].available)
			assert(not owner:template("protected-zone", { zone_id = "missing:zone" }))
			local evaluator = Evaluator.new({
				[Catalogue.ALWAYS] = function()
					return true
				end,
			})
			for _, id in ipairs({ "surface-ban", "warning" }) do
				local rule = assert(owner:template(id, { scope = { surfaces = { "nauvis" } } }))
				local result = assert(evaluator:evaluate({ rule }, {
					domain = "construction",
					kind = "entity-built",
					surface = { name = "nauvis" },
					force = {},
					payload = { entity = {} },
				}))
				assert(result.outcome == (id == "warning" and "warn" or "deny"))
			end
			assert(owner:template("spawn-miners"))
			description.fields.surfaces.label = "changed"
			assert(owner.describe().fields.surfaces.label == "Surfaces")
		end,
	},
	{
		name = "authoring rejects unknown parameters references domains and undescribed extensions",
		run = function()
			local owner = catalogue()
			local rule = assert(owner:template("surface-ban"))
			for _, mutate in ipairs({
				function(r)
					r.when.unrecognized = true
				end,
				function(r)
					r.scope.surfaces = { "missing" }
				end,
				function(r)
					r.event.domain = "research"
				end,
				function(r)
					r.when.predicate = "external:opaque"
				end,
				function(r)
					r.selector.sources = { "unknown" }
				end,
				function(r)
					r.scope.surfaces = { named = "nauvis" }
				end,
			}) do
				local candidate = assert(Schema.normalize(rule))
				mutate(candidate)
				local valid, errors = owner:validate(candidate)
				assert(not valid and #errors > 0)
			end
		end,
	},
	{
		name = "canonical conditions enforce depth node and nonempty limits",
		run = function()
			local rule = assert(catalogue():template("surface-ban"))
			for _ = 1, Schema.MAX_CONDITION_DEPTH do
				rule.when = { ["not"] = rule.when }
			end
			assert(not Schema.normalize(rule))
			rule.when = { all = {} }
			assert(not Schema.normalize(rule))
			for _ = 1, Schema.MAX_CONDITION_NODES do
				rule.when.all[#rule.when.all + 1] = { predicate = Catalogue.ALWAYS }
			end
			assert(not Schema.normalize(rule))
		end,
	},
}
