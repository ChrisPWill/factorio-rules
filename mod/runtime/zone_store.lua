local Zones = require("lib.zones")
local Serializable = require("lib.serializable")

local M = {}

function M.new(state)
	local store = {}
	function store.list()
		return assert(Serializable.copy(state.zones or {}, "zones"))
	end
	function store.get(_self, id)
		for _, zone in ipairs(store.list()) do
			if zone.id == id then
				return zone
			end
		end
	end
	function store.save(self, zone)
		local definitions = self.list()
		local candidate = assert(Serializable.copy(zone, "zone"))
		local next_id = state.next_zone_id or 1
		if not candidate.id then
			repeat
				candidate.id = "factorio-rules:zone-" .. next_id
				next_id = next_id + 1
			until not self:get(candidate.id)
		end
		local suffix = tonumber(candidate.id:match("^factorio%-rules:zone%-(%d+)$"))
		if suffix then
			next_id = math.max(next_id, suffix + 1)
		end
		candidate.name = candidate.name or candidate.id
		if type(candidate.name) ~= "string" or #candidate.name == 0 or #candidate.name > 100 then
			return nil, { "zone.name: must contain 1 to 100 bytes" }
		end
		local replaced = false
		for index, existing in ipairs(definitions) do
			if existing.id == candidate.id then
				definitions[index] = candidate
				replaced = true
				break
			end
		end
		if not replaced then
			definitions[#definitions + 1] = candidate
		end
		local valid, errors = Zones.new(definitions)
		if not valid then
			return nil, errors
		end
		state.zones = definitions
		state.next_zone_id = next_id
		return candidate.id
	end
	return store
end

return M
