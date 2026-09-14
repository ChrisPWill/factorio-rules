#!/usr/bin/env bash
set -euo pipefail

factorio_bin="${FACTORIO_BIN:-}"
player_save="${FACTORIO_PLAYER_SAVE:-}"
if [[ -z "$factorio_bin" || ! -x "$factorio_bin" ]]; then
	echo "Set FACTORIO_BIN to an executable Factorio 2.0 headless binary." >&2
	exit 2
fi

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
factorio_root="$(cd "$(dirname "$factorio_bin")/../.." && pwd)"
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT
mkdir -p "$work_dir/mods" "$work_dir/write-data"

config_file="$work_dir/config.ini"
cat > "$config_file" <<EOF
[path]
read-data=$factorio_root/data
write-data=$work_dir/write-data

[general]
locale=en
EOF

python3 "$root_dir/scripts/package.py" >/dev/null
python3 - "$root_dir" "$work_dir/mods" <<'PYDRIVER'
import pathlib
import sys
import zipfile
root, destination = map(pathlib.Path, sys.argv[1:])
import json
info = json.loads((root / "mod/info.json").read_text())
archive = root / "dist" / f'{info["name"]}_{info["version"]}.zip' 
with zipfile.ZipFile(archive) as source, zipfile.ZipFile(destination / archive.name, "w") as target:
    for entry in source.infolist():
        data = source.read(entry.filename)
        if entry.filename.endswith("/control.lua") and "/scenarios/" not in entry.filename:
            data += b"\n" + (root / "tests/integration-driver.lua").read_bytes()
        target.writestr(entry, data)
PYDRIVER
cat > "$work_dir/mods/mod-list.json" <<'JSON'
{"mods":[{"name":"base","enabled":true},{"name":"factorio-rules","enabled":true},{"name":"factorio-rules-provider-test","enabled":true},{"name":"space-age","enabled":true},{"name":"quality","enabled":true},{"name":"elevated-rails","enabled":true}]}
JSON
mkdir -p "$work_dir/mods/factorio-rules-provider-test"
cat > "$work_dir/mods/factorio-rules-provider-test/info.json" <<'JSON'
{"name":"factorio-rules-provider-test","version":"0.1.0","title":"Rule extension provider test","author":"Test harness","factorio_version":"2.0","dependencies":["factorio-rules"]}
JSON
cat > "$work_dir/mods/factorio-rules-provider-test/control.lua" <<'LUA'
remote.add_interface("factorio-rules-provider-test", {
  matches = function(context, condition)
    assert(type(context) == "table" and type(condition) == "table")
    return condition.value == "match"
  end,
  act = function()
    storage.calls = (storage.calls or 0) + 1
  end,
  calls = function() return storage.calls or 0 end,
})
script.on_init(function()
  remote.call("factorio_rules", "register_predicate_provider", "factorio-rules-provider-test:matches", { interface = "factorio-rules-provider-test", function_name = "matches" })
  remote.call("factorio_rules", "register_action_provider", "factorio-rules-provider-test:act", { interface = "factorio-rules-provider-test", function_name = "act" })
  remote.call("factorio_rules", "register_rule", {
    schema_version = 1, definition_version = 1, id = "factorio-rules-provider-test:rule",
    provenance = { source = "factorio-rules-provider-test", kind = "test" },
    event = { domain = "construction", kind = "entity-built" }, selector = { entity_names = { "wooden-chest" }, sources = { "script" } }, scope = {},
    when = { predicate = "factorio-rules-provider-test:matches", value = "match" },
    effects = { primary = { type = "warn", reason = "provider warning" }, actions = { { type = "factorio-rules-provider-test:act" } } },
  })
end)
LUA

server_arguments=(--map-gen-seed 3885402781 --start-server-load-scenario factorio-rules/integration)
success_marker="[factorio-rules integration] HEADLESS TESTS PASSED"
if [[ -n "$player_save" ]]; then
	if [[ ! -f "$player_save" ]]; then
		echo "FACTORIO_PLAYER_SAVE must name an existing save archive." >&2
		exit 2
	fi
	cp -- "$player_save" "$work_dir/player-fixture.zip"
	mkdir -p "$work_dir/mods/factorio-rules-test"
	cat > "$work_dir/mods/factorio-rules-test/info.json" <<'JSON'
{"name":"factorio-rules-test","version":"0.1.0","title":"Rule GUI tests","author":"Test harness","factorio_version":"2.0","dependencies":["factorio-rules"]}
JSON
	cat > "$work_dir/mods/factorio-rules-test/control.lua" <<'LUA'
require("__factorio-rules__.scenarios.integration.control")
LUA
	python3 - "$work_dir/mods/mod-list.json" <<'PYMODS'
import json
import sys
with open(sys.argv[1]) as source:
    settings = json.load(source)
settings["mods"].append({"name": "factorio-rules-test", "enabled": True})
with open(sys.argv[1], "w") as target:
    json.dump(settings, target)
PYMODS
	server_arguments=(--start-server "$work_dir/player-fixture.zip")
	success_marker="[factorio-rules integration] GUI TESTS PASSED"
fi

load_log="$work_dir/factorio-load.log"
load_factorio_bin="${FACTORIO_GUI_BIN:-$factorio_bin}"
load_arguments=(--dump-data)
if [[ -n "${FACTORIO_GUI_BIN:-}" ]]; then
	load_arguments=(--dump-icon-sprites)
fi
if ! "$load_factorio_bin" \
	--config "$config_file" \
	--mod-directory "$work_dir/mods" \
	"${load_arguments[@]}" >"$load_log" 2>&1; then
	cat "$load_log"
	echo "Factorio failed while loading mod prototypes." >&2
	exit 1
fi
cat "$load_log"
if grep -Fq "Error loading mods" "$load_log"; then
	echo "Factorio reported a mod loading failure." >&2
	exit 1
fi

log_file="$work_dir/factorio.log"
python3 - "$factorio_root/data/server-settings.example.json" "$work_dir/server-settings.json" <<'PYSETTINGS'
import json
import sys
with open(sys.argv[1]) as source:
    settings = json.load(source)
settings.update(auto_pause=False, autosave_interval=0, require_user_verification=False,
                visibility={"public": False, "lan": False})
with open(sys.argv[2], "w") as target:
    json.dump(settings, target)
PYSETTINGS
"$factorio_bin" \
	--config "$config_file" \
	--mod-directory "$work_dir/mods" \
	--server-settings "$work_dir/server-settings.json" \
	"${server_arguments[@]}" >"$log_file" 2>&1 &
factorio_pid=$!

finished=false
for _ in {1..600}; do
	if grep -Fq "$success_marker" "$log_file"; then
		finished=true
		break
	fi
	if ! kill -0 "$factorio_pid" 2>/dev/null; then
		break
	fi
	sleep 0.1
done

if kill -0 "$factorio_pid" 2>/dev/null; then
	kill -TERM "$factorio_pid"
fi
wait "$factorio_pid" || true
cat "$log_file"

if grep -Fq "Error loading mods" "$log_file"; then
	echo "Factorio reported a mod loading failure." >&2
	exit 1
fi
if [[ "$finished" != true ]]; then
	echo "Factorio integration tests did not reach their success marker." >&2
	exit 1
fi
if grep -Fq "[factorio-rules integration] FAIL:" "$log_file"; then
	echo "Factorio integration assertion failed." >&2
	exit 1
fi
grep -Fq "$success_marker" "$log_file"
