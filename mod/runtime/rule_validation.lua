local serializable = require("lib.serializable")

local M = {}

local function event_key(event)
	return event.domain .. "\0" .. event.kind
end

local function add_reference(references, kind, name)
	references[#references + 1] = { kind = kind, name = name }
end

local function visit_condition(condition, references)
	if condition.predicate then
		add_reference(references, "predicate", condition.predicate)
		return
	end
	if condition["not"] then
		visit_condition(condition["not"], references)
		return
	end
	for _, child in ipairs(condition.all or condition.any or {}) do
		visit_condition(child, references)
	end
end

local function rule_references(rule)
	local references = {
		{ kind = "event", name = event_key(rule.event) },
	}
	visit_condition(rule.when, references)
	for _, action in ipairs(rule.effects.actions) do
		add_reference(references, "action", action.type)
	end
	return references
end

local function severity(options, rule, reference)
	if rule.validation and rule.validation[reference.kind] then
		return rule.validation[reference.kind]
	end
	if type(options.severity) == "function" then
		return options.severity(rule, reference.kind, reference.name)
	end
	if type(options.severity) == "table" then
		return options.severity[reference.kind .. ":" .. reference.name]
			or options.severity[reference.kind]
	end
	return "disable"
end

local function available(registry, reference)
	local entries = registry[reference.kind .. "s"] or {}
	if reference.kind == "event" then
		return entries[reference.name] ~= nil
	end
	return entries[reference.name] == true or type(entries[reference.name]) == "table"
end

function M.validate(rules, registry, options)
	registry = registry or {}
	options = options or {}
	local copied, copy_errors = serializable.copy(rules, "rules", { strict_collections = true })
	if not copied or #copy_errors > 0 then
		return nil, copy_errors
	end

	local active, diagnostics, errors = {}, {}, {}
	for _, rule in ipairs(copied) do
		if rule.enabled then
			local disabled = false
			for _, reference in ipairs(rule_references(rule)) do
				if not available(registry, reference) then
					local reference_severity = severity(options, rule, reference)
					if reference_severity == "error" then
						errors[#errors + 1] = "rule "
							.. rule.id
							.. ": unavailable "
							.. reference.kind
							.. " "
							.. reference.name
					else
						disabled = true
						diagnostics[#diagnostics + 1] = {
							level = "warning",
							action = "disabled",
							rule_id = rule.id,
							kind = reference.kind,
							name = reference.name,
						}
					end
				end
			end
			if not disabled then
				active[#active + 1] = rule
			end
		end
	end
	if #errors > 0 then
		return nil, errors, diagnostics
	end
	return active, diagnostics, nil
end

return M
