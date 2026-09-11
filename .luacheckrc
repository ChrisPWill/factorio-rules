std = "lua52"
max_line_length = 100
exclude_files = { "dist/**", ".cache/**", "vendor/**" }

files["mod/control.lua"] = { globals = { "storage" }, read_globals = { "defines", "game", "log", "remote", "rendering", "script", "settings" } }
files["mod/settings.lua"] = { read_globals = { "data" } }
files["mod/data.lua"] = { read_globals = { "data" } }
files["mod/runtime/state.lua"] = { globals = { "storage" } }
files["mod/runtime/logger.lua"] = { read_globals = { "settings", "log" } }
files["mod/scenarios/**"] = { read_globals = { "defines", "script", "game", "log", "rendering" } }
