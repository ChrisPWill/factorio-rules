local Schema = require("lib.rules.schema")
local serializable = require("lib.serializable")

local M = {}
local SCHEMA_VERSION = 1
local FRAMEWORK_SCHEMA_VERSION = 1

local function copy(value, path)
	local result, errors = serializable.copy(value, path, { strict_collections = true })
	assert(#errors == 0, table.concat(errors, "; "))
	return result
end

local REPLACE_FIELDS = {
	effects = true,
	scope = true,
	selector = true,
	when = true,
	zone_ids = true,
}

local function is_array(value)
	for key in pairs(value or {}) do
		if type(key) == "number" then
			return true
		end
	end
	return false
end

local function merge(left, right)
	local result = copy(left or {}, "override")
	for key, value in pairs(right or {}) do
		if
			type(value) == "table"
			and type(result[key]) == "table"
			and not REPLACE_FIELDS[key]
			and not is_array(value)
		then
			result[key] = merge(result[key], value)
		else
			result[key] = copy(value, "override." .. key)
		end
	end
	return result
end

local function ensure_state(state)
	state.schema_version = state.schema_version or SCHEMA_VERSION
	assert(state.schema_version == SCHEMA_VERSION, "unsupported rule registry schema")
	state.sources = state.sources or {}
	state.patches = state.patches or {}
	state.overrides = state.overrides or {}
	state.warnings = state.warnings or {}
	state.next_patch = state.next_patch or 1
	state.next_source = state.next_source or 1
	state.framework_schema_version = state.framework_schema_version or FRAMEWORK_SCHEMA_VERSION
	state.source_versions = state.source_versions or {}
	state.override_versions = state.override_versions or {}
	return state
end

local function source_order(state, source)
	local entry = state.sources[source]
	if not entry then
		entry = { order = state.next_source, rules = {} }
		state.sources[source] = entry
		state.next_source = state.next_source + 1
	end
	entry.rules = entry.rules or {}
	return entry
end

local function normalize(rule)
	local normalized, errors = Schema.normalize(rule)
	if not normalized then
		return nil, errors
	end
	return normalized
end

local function validate_source(id, source)
	local owner = id:match("^([^:]+):")
	if owner ~= source then
		return nil, { "rule " .. id .. " must be registered by namespace " .. owner }
	end
	return true, nil
end

function M.new(target)
	local state = ensure_state(target or {})
	local registry = {}

	function registry.register(_self, rule)
		local normalized, errors = normalize(rule)
		if not normalized then
			return nil, errors
		end
		local source = normalized.provenance.source
		local source_ok, source_errors = validate_source(normalized.id, source)
		if not source_ok then
			return nil, source_errors
		end
		local entry = source_order(state, source)
		if entry.rules[normalized.id] then
			return nil, { "rule " .. normalized.id .. " is already registered by " .. source }
		end
		entry.rules[normalized.id] = normalized
		return true, nil
	end

	function registry.replace(_self, rule)
		local normalized, errors = normalize(rule)
		if not normalized then
			return nil, errors
		end
		local source = normalized.provenance.source
		local source_ok, source_errors = validate_source(normalized.id, source)
		if not source_ok then
			return nil, source_errors
		end
		local entry = source_order(state, source)
		if not entry.rules[normalized.id] then
			return nil, { "rule " .. normalized.id .. " is not registered by " .. source }
		end
		entry.rules[normalized.id] = normalized
		return true, nil
	end

	function registry.override(_self, id, fields, source)
		if type(id) ~= "string" or not id:match("^[%w_-]+:[%w_.-]+$") then
			return nil, { "override rule id must use the namespace:rule-name format" }
		end
		if type(fields) ~= "table" then
			return nil, { "override fields must be a table" }
		end
		if type(source) ~= "string" or source == "" then
			return nil, { "override source is required" }
		end
		state.patches[#state.patches + 1] = {
			sequence = state.next_patch,
			kind = "override",
			id = id,
			source = source,
			fields = copy(fields, "override.fields"),
		}
		state.next_patch = state.next_patch + 1
		return true, nil
	end

	function registry.replace_external(_self, id, rule, source)
		local normalized, errors = normalize(rule)
		if not normalized then
			return nil, errors
		end
		if normalized.id ~= id then
			return nil, { "replacement rule id must match target id" }
		end
		if type(source) ~= "string" or source == "" then
			return nil, { "replacement source is required" }
		end
		state.patches[#state.patches + 1] = {
			sequence = state.next_patch,
			kind = "replacement",
			id = id,
			source = source,
			rule = normalized,
		}
		state.next_patch = state.next_patch + 1
		return true, nil
	end

	function registry.set_override(_self, id, fields)
		if type(id) ~= "string" or type(fields) ~= "table" then
			return nil, { "save override requires a rule id and fields table" }
		end
		state.overrides[id] = merge(state.overrides[id], fields)
		if fields.definition_version then
			state.override_versions[id] = fields.definition_version
		end
		return true, nil
	end

	function registry.clear_override(_self, id)
		state.overrides[id] = nil
		state.override_versions[id] = nil
		return true, nil
	end

	function registry.migrate(_self, options)
		options = options or {}
		local target_framework = options.framework_schema_version or FRAMEWORK_SCHEMA_VERSION
		if
			type(target_framework) ~= "number"
			or target_framework < state.framework_schema_version
		then
			return nil, { "target framework schema version must not move backwards" }
		end
		local staged = copy(state, "migration")
		local function fail(message)
			return nil, { "rule migration failed: " .. message }
		end
		local framework_migrations = options.framework_migrations or {}
		while staged.framework_schema_version < target_framework do
			local from = staged.framework_schema_version
			local migration = framework_migrations[from]
			if type(migration) ~= "function" then
				return fail("no migration from framework schema " .. from)
			end
			local ok, result = pcall(migration, staged.overrides)
			if not ok or type(result) ~= "table" then
				return fail("framework schema " .. from .. " migration returned invalid overrides")
			end
			staged.overrides = result
			staged.framework_schema_version = from + 1
		end
		local definitions = {}
		for source, entry in pairs(staged.sources) do
			for id, rule in pairs(entry.rules or {}) do
				definitions[id] = { source = source, version = rule.definition_version }
			end
		end
		for id, fields in pairs(staged.overrides) do
			local definition = definitions[id]
			local from = staged.override_versions[id] or fields.definition_version
			if definition and from and from < definition.version then
				local migration = (options.rule_migrations or {})[id]
					or (options.rule_migrations or {})[definition.source]
				if type(migration) ~= "function" then
					return fail("no definition migration for " .. id .. " from version " .. from)
				end
				local ok, result = pcall(
					migration,
					copy(fields, "migration.override." .. id),
					from,
					definition.version
				)
				if not ok or type(result) ~= "table" then
					return fail("definition migration for " .. id .. " returned invalid fields")
				end
				staged.overrides[id] = result
				staged.override_versions[id] = definition.version
			end
		end
		for source, version in pairs(options.source_versions or {}) do
			staged.source_versions[source] = version
		end
		for key in pairs(state) do
			state[key] = nil
		end
		for key, value in pairs(staged) do
			state[key] = value
		end
		return true, nil
	end

	function registry.effective(_self)
		local rules, by_id, provenance = {}, {}, {}
		local sources = {}
		for source, entry in pairs(state.sources) do
			sources[#sources + 1] = { source = source, entry = entry }
		end
		table.sort(sources, function(left, right)
			return left.entry.order < right.entry.order
				or (left.entry.order == right.entry.order and left.source < right.source)
		end)
		for _, source in ipairs(sources) do
			for id, rule in pairs(source.entry.rules) do
				if by_id[id] then
					return nil, { "duplicate globally namespaced rule " .. id }
				end
				by_id[id] = copy(rule, "rules." .. id)
				provenance[id] = { { source = source.source, kind = "source" } }
			end
		end
		table.sort(state.patches, function(left, right)
			return left.sequence < right.sequence
		end)
		for _, patch in ipairs(state.patches) do
			if by_id[patch.id] then
				if patch.kind == "replacement" then
					by_id[patch.id] = copy(patch.rule, "replacement." .. patch.id)
				else
					by_id[patch.id] = merge(by_id[patch.id], patch.fields)
				end
				provenance[patch.id][#provenance[patch.id] + 1] = {
					source = patch.source,
					kind = patch.kind,
				}
			end
		end
		state.warnings = {}
		for id, fields in pairs(state.overrides) do
			if by_id[id] then
				by_id[id] = merge(by_id[id], fields)
				provenance[id][#provenance[id] + 1] = { source = "save", kind = "override" }
			else
				state.warnings[#state.warnings + 1] = "orphaned override retained for " .. id
			end
		end
		for id, rule in pairs(by_id) do
			rule.provenance = merge(rule.provenance, { lineage = provenance[id] })
			rules[#rules + 1] = rule
		end
		table.sort(rules, function(left, right)
			return left.id < right.id
		end)
		return rules, nil
	end

	function registry.warnings(_self)
		return copy(state.warnings, "warnings")
	end

	function registry.state(_self)
		return state
	end

	return registry
end

return M
