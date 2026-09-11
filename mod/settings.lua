data:extend({
	{
		type = "bool-setting",
		name = "factorio-rules-debug",
		setting_type = "runtime-global",
		default_value = false,
		order = "a",
	},
	{
		type = "int-setting",
		name = "factorio-rules-violation-history-limit",
		setting_type = "runtime-global",
		default_value = 20,
		minimum_value = 0,
		maximum_value = 200,
		order = "b",
	},
})
