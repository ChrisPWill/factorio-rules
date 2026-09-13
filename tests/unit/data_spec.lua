-- luacheck: globals data
local extended
local previous_data = data
data = {
	extend = function(_self, prototypes)
		extended = prototypes
	end,
}

local ok, error_message = pcall(dofile, "mod/data.lua")
data = previous_data
assert(ok, error_message)

local shortcuts = {}
for _, prototype in ipairs(extended or {}) do
	if prototype.type == "shortcut" then
		shortcuts[prototype.name] = prototype
	end
end

return {
	{
		name = "loads shortcut prototypes through the data stage",
		run = function()
			local overlays = assert(shortcuts["factorio-rules-toggle-zones"])
			local manager = assert(shortcuts["factorio-rules-manage-rules"])
			assert(manager.action == "lua")
			assert(manager.icon == overlays.icon and manager.small_icon == overlays.small_icon)
			assert(manager.order == "a[factorio-rules]")
		end,
	},
}
