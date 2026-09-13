#!/usr/bin/env bash
set -euo pipefail

factorio_version="2.0.77"
factorio_sha256="c4efc11529f74d37c96933e291e0db73fd9f5aa4738913d9301b24680b3e947f"

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cache_dir="$root_dir/.cache/factorio/$factorio_version"
archive="$cache_dir/factorio-headless_linux_${factorio_version}.tar.xz"
factorio_bin="$cache_dir/factorio/bin/x64/factorio"
gui_fixture="$root_dir/tests/fixtures/gui-test-fixture.zip"
gui_fixture_checksum="$root_dir/tests/fixtures/gui-test-fixture.sha256"

mkdir -p "$cache_dir"

if [[ ! -f "$archive" ]] || ! echo "$factorio_sha256  $archive" | sha256sum --check --status; then
	echo "Downloading Factorio headless $factorio_version..."
	curl --fail --location --retry 3 \
		"https://factorio.com/get-download/${factorio_version}/headless/linux64" \
		--output "$archive.part"
	echo "$factorio_sha256  $archive.part" | sha256sum --check
	mv "$archive.part" "$archive"
fi

if [[ ! -x "$factorio_bin" ]]; then
	echo "Extracting Factorio headless $factorio_version..."
	tar --extract --xz --file "$archive" --directory "$cache_dir"
fi

cd "$root_dir"
if [[ ! -f "$gui_fixture" || ! -f "$gui_fixture_checksum" ]]; then
	echo "Missing required GUI integration fixture: tests/fixtures/gui-test-fixture.zip" >&2
	exit 1
fi
sha256sum --check --status "$gui_fixture_checksum"
nix flake check --print-build-logs
FACTORIO_PLAYER_SAVE= FACTORIO_BIN="$factorio_bin" make integration-test
FACTORIO_PLAYER_SAVE="$gui_fixture" FACTORIO_BIN="$factorio_bin" make integration-test
sha256sum --check --status "$gui_fixture_checksum"
