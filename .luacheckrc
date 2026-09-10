std = "lua52"
max_line_length = 100
exclude_files = { "dist/**", ".cache/**", "vendor/**" }

files["mod/control.lua"] = { read_globals = { "script" } }
files["mod/settings.lua"] = { read_globals = { "data" } }
files["mod/data.lua"] = { read_globals = { "data" } }
files["mod/runtime/state.lua"] = { globals = { "storage" } }
files["mod/runtime/logger.lua"] = { read_globals = { "settings", "log" } }
files["mod/scenarios/**"] = { read_globals = { "script", "game", "log" } }
