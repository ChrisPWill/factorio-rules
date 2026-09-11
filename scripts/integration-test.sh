#!/usr/bin/env bash
set -euo pipefail

factorio_bin="${FACTORIO_BIN:-}"
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
cp "$root_dir"/dist/factorio-rules_*.zip "$work_dir/mods/"
cat > "$work_dir/mods/mod-list.json" <<'JSON'
{"mods":[{"name":"base","enabled":true},{"name":"factorio-rules","enabled":true},{"name":"space-age","enabled":true},{"name":"quality","enabled":true},{"name":"elevated-rails","enabled":true}]}
JSON

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
"$factorio_bin" \
	--config "$config_file" \
	--mod-directory "$work_dir/mods" \
	--map-gen-seed 3885402781 \
	--start-server-load-scenario factorio-rules/integration >"$log_file" 2>&1 &
factorio_pid=$!

finished=false
for _ in {1..100}; do
	if grep -Fq "[factorio-rules integration] ALL TESTS PASSED" "$log_file"; then
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
grep -Fq "[factorio-rules integration] ALL TESTS PASSED" "$log_file"
