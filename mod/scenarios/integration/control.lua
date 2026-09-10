local checks = {
	{
		name = "entities can be placed and inspected",
		run = function(surface)
			local entity = surface.create_entity({
				name = "stone-furnace",
				position = { 0, 0 },
				force = "player",
			})
			assert(entity and entity.valid, "stone-furnace was not created")
			assert(entity.name == "stone-furnace", "unexpected entity prototype")
			assert(entity.position.x == 0 and entity.position.y == 0, "unexpected entity position")
		end,
	},
}

script.on_init(function()
	local surface = game.surfaces[1]
	for _, check in ipairs(checks) do
		local ok, err = pcall(check.run, surface)
		if not ok then
			error("[factorio-rules integration] FAIL: " .. check.name .. ": " .. tostring(err))
		end
		log("[factorio-rules integration] PASS: " .. check.name)
	end
	log("[factorio-rules integration] ALL TESTS PASSED")
end)
