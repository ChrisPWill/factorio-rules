#!/usr/bin/env bash
set -euo pipefail

factorio_version="2.0.60"
factorio_sha256="69b5be1a867fd99524f9914dfee900a1ac386cf4e74c4a63768c05dc4d2b2b0b"

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cache_dir="$root_dir/.cache/factorio/$factorio_version"
archive="$cache_dir/factorio-headless_linux_${factorio_version}.tar.xz"
factorio_bin="$cache_dir/factorio/bin/x64/factorio"

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
nix flake check --print-build-logs
FACTORIO_PLAYER_SAVE= FACTORIO_BIN="$factorio_bin" make integration-test
if [[ -n "${FACTORIO_PLAYER_SAVE:-}" ]]; then
	FACTORIO_BIN="$factorio_bin" make integration-test
else
	echo "GUI tests not run: set FACTORIO_PLAYER_SAVE to a compatible save containing a player."
fi
