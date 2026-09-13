local Registry = require("lib.rules.registry")
local Serializable = require("lib.serializable")

local M = {}

local function copy(value, path)
	local result, errors = Serializable.copy(value, path, { strict_collections = true })
	if #errors > 0 then
		return nil, errors
	end
	return result
end

local function replace(target, source)
	for key in pairs(target) do
		target[key] = nil
	end
	for key, value in pairs(source) do
		target[key] = value
	end
end

local function diagnostic(path, message)
	return { { field = path, message = message } }
end

local function find_source(state, id)
	for source, entry in pairs(state.sources or {}) do
		local rule = entry.rules and entry.rules[id]
		if rule then
			return rule, source
		end
	end
end

local function save_owned(rule)
	return rule and rule.provenance and rule.provenance.kind == "save"
end

function M.new(state, options)
	assert(type(state) == "table", "authoring state is required")
	assert(
		type(options) == "table" and type(options.validate) == "function",
		"rule validation is required"
	)
	local authoring = {}

	local function revision(id)
		return state.rule_revisions[id] or 1
	end

	local function generated_id(staged)
		local next_id = staged.next_rule_id or 1
		while find_source(staged, "factorio-rules:rule-" .. next_id) do
			next_id = next_id + 1
		end
		staged.next_rule_id = next_id + 1
		return "factorio-rules:rule-" .. next_id
	end

	local function validate(rule, path)
		local normalized, errors = options.validate(rule)
		if not normalized then
			local diagnostics = {}
			for _, message in ipairs(errors or {}) do
				diagnostics[#diagnostics + 1] = { field = path, message = message }
			end
			return nil, diagnostics
		end
		return normalized
	end

	function authoring.list()
		local rules = assert(Registry.new(state):effective())
		for _, rule in ipairs(rules) do
			rule.revision = revision(rule.id)
		end
		return rules
	end

	function authoring.revision(_self, id)
		return revision(id)
	end

	function authoring.execute(_self, commands, context)
		if options.authorize then
			local allowed, authorization_errors = options.authorize(context, commands)
			if not allowed then
				return nil, authorization_errors or diagnostic("authorization", "is not permitted")
			end
		end
		if type(commands) ~= "table" or #commands == 0 then
			return nil, diagnostic("commands", "must be a nonempty array")
		end
		local staged, errors = copy(state, "transaction")
		if not staged then
			return nil, diagnostic("commands", table.concat(errors, "; "))
		end
		staged.next_rule_id = staged.next_rule_id or 1
		staged.rule_revisions = staged.rule_revisions or {}
		local registry = Registry.new(staged)
		local changed, results = {}, {}

		local function require_revision(command, rule, index)
			if command.revision ~= (staged.rule_revisions[rule.id] or 1) then
				return nil, diagnostic("commands[" .. index .. "].revision", "is stale")
			end
			return true
		end
		local function commit_rule(rule)
			local ok, registry_errors = registry:replace(rule)
			if not ok then
				return nil, diagnostic("commands", table.concat(registry_errors, "; "))
			end
			changed[rule.id] = true
			return true
		end

		for index, command in ipairs(commands) do
			if type(command) ~= "table" or type(command.kind) ~= "string" then
				return nil, diagnostic("commands[" .. index .. "]", "must provide a command kind")
			end
			if command.kind == "create" then
				local candidate, copy_errors = copy(command.rule, "commands[" .. index .. "].rule")
				if not candidate then
					return nil,
						diagnostic(
							"commands[" .. index .. "].rule",
							table.concat(copy_errors, "; ")
						)
				end
				candidate.id = generated_id(staged)
				candidate.provenance = { source = "factorio-rules", kind = "save" }
				local normalized, validation_errors =
					validate(candidate, "commands[" .. index .. "].rule")
				if not normalized then
					return nil, validation_errors
				end
				local ok, registry_errors = registry:register(normalized)
				if not ok then
					return nil,
						diagnostic(
							"commands[" .. index .. "].rule",
							table.concat(registry_errors, "; ")
						)
				end
				changed[normalized.id] = true
				results[#results + 1] = { id = normalized.id, revision = 1 }
			else
				local rule = find_source(staged, command.id)
				if not rule then
					return nil, diagnostic("commands[" .. index .. "].id", "does not name a rule")
				end
				local fresh, revision_errors = require_revision(command, rule, index)
				if not fresh then
					return nil, revision_errors
				end
				if command.kind == "update" then
					if not save_owned(rule) then
						return nil,
							diagnostic(
								"commands[" .. index .. "]",
								"source-owned rules may only use overrides"
							)
					end
					local candidate, copy_errors =
						copy(command.rule, "commands[" .. index .. "].rule")
					if not candidate then
						return nil,
							diagnostic(
								"commands[" .. index .. "].rule",
								table.concat(copy_errors, "; ")
							)
					end
					candidate.id = rule.id
					candidate.provenance = { source = "factorio-rules", kind = "save" }
					local normalized, validation_errors =
						validate(candidate, "commands[" .. index .. "].rule")
					if not normalized then
						return nil, validation_errors
					end
					local ok, replace_errors = commit_rule(normalized)
					if not ok then
						return nil, replace_errors
					end
				elseif command.kind == "duplicate" then
					local candidate = assert(copy(rule, "commands[" .. index .. "].rule"))
					candidate.id = generated_id(staged)
					candidate.provenance = { source = "factorio-rules", kind = "save" }
					if command.name ~= nil then
						candidate.name = command.name
					end
					local normalized, validation_errors =
						validate(candidate, "commands[" .. index .. "].rule")
					if not normalized then
						return nil, validation_errors
					end
					local ok, register_errors = registry:register(normalized)
					if not ok then
						return nil,
							diagnostic(
								"commands[" .. index .. "]",
								table.concat(register_errors, "; ")
							)
					end
					changed[normalized.id] = true
					results[#results + 1] = { id = normalized.id, revision = 1 }
				elseif command.kind == "set-enabled" then
					if type(command.enabled) ~= "boolean" then
						return nil,
							diagnostic("commands[" .. index .. "].enabled", "must be a boolean")
					end
					if save_owned(rule) then
						local candidate = assert(copy(rule, "commands[" .. index .. "].rule"))
						candidate.enabled = command.enabled
						local ok, replace_errors = commit_rule(candidate)
						if not ok then
							return nil, replace_errors
						end
					else
						assert(registry:set_override(rule.id, { enabled = command.enabled }))
						changed[rule.id] = true
					end
				elseif command.kind == "set-priority" then
					if type(command.priority) ~= "number" or command.priority % 1 ~= 0 then
						return nil,
							diagnostic("commands[" .. index .. "].priority", "must be an integer")
					end
					if save_owned(rule) then
						local candidate = assert(copy(rule, "commands[" .. index .. "].rule"))
						candidate.priority = command.priority
						local normalized, validation_errors =
							validate(candidate, "commands[" .. index .. "].rule")
						if not normalized then
							return nil, validation_errors
						end
						local ok, replace_errors = commit_rule(normalized)
						if not ok then
							return nil, replace_errors
						end
					else
						assert(registry:set_override(rule.id, { priority = command.priority }))
						changed[rule.id] = true
					end
				elseif command.kind == "delete" then
					if not save_owned(rule) then
						return nil,
							diagnostic(
								"commands[" .. index .. "]",
								"source-owned rules cannot be deleted"
							)
					end
					staged.sources[rule.provenance.source].rules[rule.id] = nil
					staged.overrides[rule.id] = nil
					changed[rule.id] = true
				elseif command.kind == "reset" then
					if save_owned(rule) then
						return nil,
							diagnostic(
								"commands[" .. index .. "]",
								"save-owned rules do not have source overrides"
							)
					end
					assert(registry:clear_override(rule.id))
					changed[rule.id] = true
				else
					return nil, diagnostic("commands[" .. index .. "].kind", "is unsupported")
				end
			end
		end

		local effective, effective_errors = registry:effective()
		if not effective then
			return nil, diagnostic("commands", table.concat(effective_errors, "; "))
		end
		if options.stage then
			local staged_ok, stage_errors = options.stage(effective)
			if not staged_ok then
				return nil, diagnostic("commands", table.concat(stage_errors or {}, "; "))
			end
		end
		for id in pairs(changed) do
			if find_source(staged, id) then
				staged.rule_revisions[id] = (staged.rule_revisions[id] or 1) + 1
			else
				staged.rule_revisions[id] = nil
			end
		end
		for _, result in ipairs(results) do
			result.revision = staged.rule_revisions[result.id]
		end
		replace(state, staged)
		return { results = results, rules = authoring.list() }
	end

	return authoring
end

return M
