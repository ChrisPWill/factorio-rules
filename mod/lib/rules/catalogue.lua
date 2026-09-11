local Schema = require("lib.rules.schema")
local Serializable = require("lib.serializable")
local Miner = require("lib.builtin.nauvis_miner")

local M = {}
M.ALWAYS = "factorio-rules:always"
M.INSIDE_ZONE = "factorio-rules:inside-zone"

local function copy(value)
	return assert(Serializable.copy(value, "catalogue", { strict_collections = true }))
end

local predicates = {
	[M.ALWAYS] = { label = "Always", parameters = {} },
	[M.INSIDE_ZONE] = {
		label = "Inside zone",
		parameters = { zone_id = { type = "string", reference = "zone", required = true } },
	},
	[Miner.INSIDE_PREDICATE] = { label = "Inside Nauvis spawn", parameters = {} },
	[Miner.SPAWN_PATCH_PREDICATE] = { label = "On a starting resource patch", parameters = {} },
}
for _, descriptor in pairs(predicates) do
	descriptor.domain = "construction"
end

local fields = {
	entity_names = { label = "Entities", type = "array", reference = "entity" },
	entity_types = { label = "Entity types", type = "array", reference = "entity_type" },
	sources = {
		label = "Built by",
		type = "array",
		values = { "player", "robot", "script", "script-revive" },
	},
	surfaces = { label = "Surfaces", type = "array", reference = "surface" },
	forces = { label = "Forces", type = "array", reference = "force" },
}

local templates = {
	{ id = "surface-ban", label = "Restrict construction", predicate = M.ALWAYS },
	{ id = "protected-zone", label = "Protect a zone", predicate = M.INSIDE_ZONE },
	{
		id = "required-zone",
		label = "Require construction inside a zone",
		predicate = M.INSIDE_ZONE,
	},
	{ id = "warning", label = "Warn on construction", predicate = M.ALWAYS },
	{
		id = "spawn-miners",
		label = "Restrict miners to starting patches",
		predicate = Miner.SPAWN_PATCH_PREDICATE,
	},
}

-- Handlers establish availability; descriptors alone never advertise executable behavior.
function M.new(options)
	options = options or {}
	local definitions = { predicates = copy(predicates), actions = {} }
	for kind, entries in pairs(options.descriptors or {}) do
		assert(definitions[kind], "unknown descriptor kind")
		for name, descriptor in pairs(entries) do
			definitions[kind][name] = copy(descriptor)
		end
	end
	local catalogue = {}
	local function available(kind, name)
		return type((options[kind] or {})[name]) == "function"
	end

	function catalogue.describe()
		local result = {
			event = { domain = "construction", kind = "entity-built", label = "Entity constructed" },
			fields = copy(fields),
			predicates = {},
			actions = {},
			templates = {},
			outcomes = { "deny", "warn" },
			notification = {
				label = "Violation message",
				type = "string",
				required = true,
				max_length = 500,
				delivery = "actor-or-force",
			},
			priority = { label = "Priority", type = "integer", min = -1000000, max = 1000000 },
			limits = { depth = Schema.MAX_CONDITION_DEPTH, nodes = Schema.MAX_CONDITION_NODES },
		}
		for kind, entries in pairs(definitions) do
			for name, descriptor in pairs(entries) do
				result[kind][name] = copy(descriptor)
				result[kind][name].available = available(kind, name)
			end
		end
		for _, template in ipairs(templates) do
			local item = copy(template)
			item.available = available("predicates", item.predicate)
			if item.id == "spawn-miners" then
				item.available = item.available and available("predicates", Miner.INSIDE_PREDICATE)
			end
			result.templates[#result.templates + 1] = item
		end
		return result
	end

	function catalogue.validate(_self, input)
		local rule, errors = Schema.normalize(input)
		if not rule then
			return nil, errors
		end
		errors = {}
		local function fail(path, message)
			errors[#errors + 1] = path .. ": " .. message
		end
		local function validate_value(value, descriptor, path)
			if value == nil and not descriptor.required then
				return
			end
			if
				type(value) ~= descriptor.type
				and not (
					descriptor.type == "integer"
					and type(value) == "number"
					and value % 1 == 0
				)
			then
				fail(path, "must be " .. descriptor.type)
				return
			end
			if
				type(value) == "string" and (value == "" or #value > (descriptor.max_length or 200))
			then
				fail(path, "invalid string length")
			end
			if
				descriptor.min and value < descriptor.min
				or descriptor.max and value > descriptor.max
			then
				fail(path, "outside allowed range")
			end
			if descriptor.values then
				local found = false
				for _, allowed in ipairs(descriptor.values) do
					if value == allowed then
						found = true
					end
				end
				if not found then
					fail(path, "unsupported value")
				end
			end
			if
				descriptor.reference
				and (
					not options.reference_exists
					or not options.reference_exists(descriptor.reference, value)
				)
			then
				fail(path, "unavailable " .. descriptor.reference .. " reference")
			end
		end
		local function known_fields(node, allowed, path)
			for key in pairs(node) do
				if not allowed[key] then
					fail(path .. "." .. tostring(key), "unsupported field; editing would lose data")
				end
			end
		end
		known_fields(rule, {
			schema_version = true,
			definition_version = true,
			id = true,
			name = true,
			enabled = true,
			priority = true,
			provenance = true,
			event = true,
			selector = true,
			scope = true,
			when = true,
			effects = true,
			zone_ids = true,
		}, "rule")
		known_fields(rule.event, { domain = true, kind = true }, "rule.event")
		known_fields(rule.effects, { primary = true, actions = true }, "rule.effects")
		known_fields(rule.effects.primary, { type = true, reason = true }, "rule.effects.primary")
		local function parameters(node, descriptor, discriminator, path)
			for key in pairs(node) do
				if key ~= discriminator and not descriptor.parameters[key] then
					fail(path .. "." .. key, "unsupported parameter; editing would lose data")
				end
			end
			for key, parameter in pairs(descriptor.parameters) do
				validate_value(node[key], parameter, path .. "." .. key)
			end
		end
		local function behavior(kind, name, node, discriminator, path)
			local descriptor = definitions[kind][name]
			if not descriptor or not available(kind, name) then
				fail(path, "unavailable or read-only " .. name)
				return
			end
			if descriptor.domain ~= rule.event.domain then
				fail(path, "incompatible event domain")
			end
			parameters(node, descriptor, discriminator, path)
		end
		local function condition(node, path)
			if node.predicate then
				behavior("predicates", node.predicate, node, "predicate", path)
				return
			end
			local key = node.all and "all" or node.any and "any" or "not"
			for field in pairs(node) do
				if field ~= key then
					fail(path .. "." .. field, "unsupported condition field")
				end
			end
			if key == "not" then
				condition(node[key], path .. ".not")
			else
				for i, child in ipairs(node[key]) do
					condition(child, path .. "." .. key .. "[" .. i .. "]")
				end
			end
		end
		if rule.event.domain ~= "construction" or rule.event.kind ~= "entity-built" then
			fail("rule.event", "unsupported authoring event")
		end
		for _, group in ipairs({ "selector", "scope" }) do
			for key, values in pairs(rule[group]) do
				local descriptor = fields[key]
				local valid_group = group == "scope" and (key == "surfaces" or key == "forces")
					or group == "selector"
						and (key == "entity_names" or key == "entity_types" or key == "sources")
				if not descriptor or not valid_group then
					fail("rule." .. group .. "." .. key, "unsupported field")
				elseif type(values) ~= "table" then
					fail("rule." .. group .. "." .. key, "must be an array")
				else
					for index, item in pairs(values) do
						local path = "rule." .. group .. "." .. key .. "[" .. tostring(index) .. "]"
						if type(index) ~= "number" then
							fail(path, "must be an array")
						else
							validate_value(item, {
								type = "string",
								reference = descriptor.reference,
								values = descriptor.values,
								required = true,
							}, path)
						end
					end
				end
			end
		end
		condition(rule.when, "rule.when")
		for i, action in ipairs(rule.effects.actions) do
			behavior("actions", action.type, action, "type", "rule.effects.actions[" .. i .. "]")
		end
		validate_value(
			rule.effects.primary.reason,
			catalogue.describe().notification,
			"rule.effects.primary.reason"
		)
		validate_value(rule.priority, catalogue.describe().priority, "rule.priority")
		if #errors > 0 then
			return nil, errors
		end
		return rule
	end

	function catalogue.template(self, id, config)
		config = config or {}
		local selected
		for _, item in ipairs(self.describe().templates) do
			if item.id == id then
				selected = item
			end
		end
		if not selected or not selected.available then
			return nil, { "template: unavailable " .. tostring(id) }
		end
		local rule = Miner.rule()
		rule.id = config.id or "save:draft"
		rule.provenance = { source = rule.id:match("^([^:]+):"), kind = "save" }
		if id ~= "spawn-miners" then
			rule.selector = copy(config.selector or {})
			rule.scope = copy(config.scope or {})
			rule.when = { predicate = selected.predicate }
			if selected.predicate == M.INSIDE_ZONE then
				rule.when.zone_id = config.zone_id
			end
			if id == "required-zone" then
				if not rule.scope.surfaces or #rule.scope.surfaces == 0 then
					return nil, { "rule.scope.surfaces: required for outside-zone restriction" }
				end
				rule.when = { ["not"] = rule.when }
			end
		end
		rule.effects.primary = {
			type = id == "warning" and "warn" or "deny",
			reason = config.reason or selected.label,
		}
		return self:validate(rule)
	end
	return catalogue
end

return M
