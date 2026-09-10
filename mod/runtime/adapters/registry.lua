local Context = require("lib.rules.context")

local M = {}

function M.new(options)
	options = options or {}
	local adapters = {}
	local registry = {}

	function registry.register(_self, source, adapter)
		assert(
			type(source) == "string" and source ~= "",
			"adapter source must be a nonempty string"
		)
		assert(type(adapter) == "function", "adapter must be a function")
		assert(not adapters[source], "adapter already registered for " .. source)
		adapters[source] = adapter
	end

	function registry.adapt(_self, source, event)
		local adapter = adapters[source]
		if not adapter then
			return nil, nil, { "event.source: no adapter registered for " .. tostring(source) }
		end
		local spec, boundary, adapter_errors = adapter(event)
		if not spec then
			return nil, boundary, adapter_errors or { "event: adapter did not produce a context" }
		end
		spec.capabilities = options.capabilities
		local context, context_errors = Context.new(spec)
		if not context then
			return nil, boundary, context_errors
		end
		return context, boundary or {}, nil
	end

	return registry
end

return M
