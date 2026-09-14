local Serializable = require("lib.serializable")

-- Drafts are runtime-only editing sessions. Authoritative rule state remains
-- behind authoring.execute, so typing in a form cannot change enforcement.
local M = {}

local function clone(value, path)
	local result, errors = Serializable.copy(value, path, { strict_collections = true })
	if not result then
		return nil, table.concat(errors, "; ")
	end
	return result
end

function M.new()
	local drafts = {}
	local api = {}

	function api.open(player_index, rule, revision)
		assert(type(player_index) == "number", "player index is required")
		local copy, err = clone(rule, "draft.rule")
		if not copy then
			return nil, err
		end
		drafts[player_index] = {
			rule = copy,
			base_revision = revision,
			dirty = false,
		}
		return api.snapshot(player_index)
	end

	function api.update(player_index, rule)
		local draft = drafts[player_index]
		if not draft then
			return nil, "draft is not open"
		end
		local copy, err = clone(rule, "draft.rule")
		if not copy then
			return nil, err
		end
		draft.rule = copy
		draft.dirty = true
		return api.snapshot(player_index)
	end

	function api.snapshot(player_index)
		local draft = drafts[player_index]
		if not draft then
			return nil
		end
		local copy, err = clone(draft.rule, "draft.snapshot")
		if not copy then
			return nil, err
		end
		return {
			rule = copy,
			base_revision = draft.base_revision,
			dirty = draft.dirty,
		}
	end

	function api.cancel(player_index)
		drafts[player_index] = nil
	end

	function api.clear(player_index)
		api.cancel(player_index)
	end

	return api
end

return M
