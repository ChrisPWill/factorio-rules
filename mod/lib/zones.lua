local serializable = require("lib.serializable")

local M = {}

function M.referenced_ids(rules)
	local referenced = {}
	for _, rule in ipairs(rules or {}) do
		for _, zone_id in ipairs(rule.zone_ids or {}) do
			referenced[zone_id] = true
		end
	end
	return referenced
end

function M.delete_unused(definitions, rules)
	local referenced = M.referenced_ids(rules)
	local kept, removed = {}, {}
	for _, zone in ipairs(definitions or {}) do
		if referenced[zone.id] then
			kept[#kept + 1] = zone
		else
			removed[#removed + 1] = zone.id
		end
	end
	return kept, removed
end

local function add_error(errors, path, message)
	errors[#errors + 1] = path .. ": " .. message
end

local function positive_number(value)
	return type(value) == "number" and value > 0
end

local function valid_position(value)
	return type(value) == "table" and type(value.x) == "number" and type(value.y) == "number"
end

local function valid_scope_values(values)
	if type(values) ~= "table" then
		return false
	end
	local count = 0
	for key, value in pairs(values) do
		if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then
			return false
		end
		count = count + 1
		if type(value) ~= "string" and type(value) ~= "number" then
			return false
		end
	end
	return count == #values
end

local function validate(zone, index, ids, errors)
	local path = "zones[" .. index .. "]"
	if type(zone) ~= "table" then
		add_error(errors, path, "must be a table")
		return
	end
	if type(zone.id) ~= "string" or not zone.id:match("^[%w_-]+:[%w_.-]+$") then
		add_error(errors, path .. ".id", "must use the namespace:zone-name format")
	elseif ids[zone.id] then
		add_error(errors, path .. ".id", "must be unique")
	else
		ids[zone.id] = true
	end

	local shape = zone.shape
	if type(shape) ~= "table" then
		add_error(errors, path .. ".shape", "must be a table")
	elseif shape.type == "circle" then
		if not positive_number(shape.radius) then
			add_error(errors, path .. ".shape.radius", "must be a positive number")
		end
	elseif shape.type == "rectangle" then
		if not positive_number(shape.width) then
			add_error(errors, path .. ".shape.width", "must be a positive number")
		end
		if not positive_number(shape.height) then
			add_error(errors, path .. ".shape.height", "must be a positive number")
		end
	else
		add_error(errors, path .. ".shape.type", "must be circle or rectangle")
	end

	local anchor = zone.anchor
	if type(anchor) ~= "table" then
		add_error(errors, path .. ".anchor", "must be a table")
	elseif anchor.type == "absolute" then
		if not valid_position(anchor.position) then
			add_error(errors, path .. ".anchor.position", "must contain numeric x and y")
		end
	elseif anchor.type ~= "force-spawn" then
		add_error(errors, path .. ".anchor.type", "must be absolute or force-spawn")
	end

	zone.scope = zone.scope or {}
	for _, key in ipairs({ "surfaces", "forces" }) do
		if zone.scope[key] ~= nil and not valid_scope_values(zone.scope[key]) then
			add_error(errors, path .. ".scope." .. key, "must be an array of names or indexes")
		end
	end
end

local function includes(values, reference)
	if not values then
		return true
	end
	if not reference then
		return false
	end
	for _, value in ipairs(values) do
		if value == reference.name or value == reference.index then
			return true
		end
	end
	return false
end

local function in_scope(zone, context)
	return includes(zone.scope.surfaces, context.surface)
		and includes(zone.scope.forces, context.force)
end

function M.new(definitions, options)
	local copied, errors = serializable.copy(definitions, "zones", { strict_collections = true })
	if type(copied) ~= "table" then
		return nil, errors
	end
	for key in pairs(copied) do
		if type(key) ~= "number" then
			add_error(errors, "zones", "must be an array")
			break
		end
	end
	local ids = {}
	for index, zone in ipairs(copied) do
		validate(zone, index, ids, errors)
	end
	if #errors > 0 then
		return nil, errors
	end

	local by_id = {}
	for _, zone in ipairs(copied) do
		by_id[zone.id] = zone
	end
	local zones = {}

	function zones.list()
		return serializable.copy(copied, "zones", { strict_collections = true })
	end

	function zones.resolve(_self, id, context)
		local zone = by_id[id]
		if not zone then
			return nil, "unknown zone " .. tostring(id)
		end
		if not in_scope(zone, context) then
			return nil, nil
		end
		if zone.anchor.type == "absolute" then
			return zone, { x = zone.anchor.position.x, y = zone.anchor.position.y }
		end
		if not options or type(options.force_spawn) ~= "function" then
			return nil, "force-spawn resolver is unavailable"
		end
		if not context.force then
			return nil, "force-spawn anchor requires a force context"
		end
		local position = options.force_spawn(context.surface, context.force)
		if not valid_position(position) then
			return nil, "force-spawn resolver returned an invalid position"
		end
		return zone, { x = position.x, y = position.y }
	end

	function zones.contains(self, id, context, position)
		if not valid_position(position) then
			return nil, "position must contain numeric x and y"
		end
		local zone, center_or_error = self:resolve(id, context)
		if not zone then
			return center_or_error and nil or false, center_or_error
		end
		local dx = position.x - center_or_error.x
		local dy = position.y - center_or_error.y
		if zone.shape.type == "circle" then
			return dx * dx + dy * dy <= zone.shape.radius * zone.shape.radius, nil
		end
		return math.abs(dx) <= zone.shape.width / 2 and math.abs(dy) <= zone.shape.height / 2, nil
	end

	return zones, nil
end

return M
