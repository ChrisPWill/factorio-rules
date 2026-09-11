local Rollback = require("runtime.rollback")

local function boundary()
	return { entity = { valid = true } }
end

local function setup(inserted, spilled)
	local destroys = 0
	local rollback = Rollback.new({
		capture = function()
			return { { name = "electric-mining-drill", count = 1, quality = "rare" } }
		end,
		destroy = function(subject)
			destroys = destroys + 1
			subject.entity.valid = false
			return true
		end,
		insert = function(_, _, stack)
			assert(stack.quality == "rare")
			return inserted
		end,
		spill = function(_, _, stack)
			assert(stack.quality == "rare")
			return spilled
		end,
	})
	return rollback, function()
		return destroys
	end
end

return {
	{
		name = "destroys then restores the consumed placement item",
		run = function()
			local rollback, destroys = setup(1, 0)
			local report, errors = rollback:apply(boundary(), {})
			assert(report.status == "reverted" and report.refunded == 1 and report.spilled == 0)
			assert(not errors and destroys() == 1)
		end,
	},
	{
		name = "spills overflow without duplicating inserted items",
		run = function()
			local rollback = setup(0, 1)
			local report, errors = rollback:apply(boundary(), {})
			assert(report.refunded == 0 and report.spilled == 1 and not errors)
		end,
	},
	{
		name = "does not refund when entity destruction fails",
		run = function()
			local insert_calls = 0
			local rollback = Rollback.new({
				capture = function()
					return { { name = "item", count = 1 } }
				end,
				destroy = function()
					return false
				end,
				insert = function()
					insert_calls = insert_calls + 1
				end,
				spill = function()
					return 0
				end,
			})
			local report, errors = rollback:apply(boundary(), {})
			assert(report == nil and #errors == 1 and insert_calls == 0)
		end,
	},
	{
		name = "repeated rollback does not duplicate refunds",
		run = function()
			local subject = boundary()
			local rollback = setup(1, 0)
			assert(rollback:apply(subject, {}))
			local report = assert(rollback:apply(subject, {}))
			assert(report.status == "already-reverted" and report.refunded == 0)
		end,
	},
}
