"""Validate and reproducibly package only the mod's distributable files."""

import json
from pathlib import Path
import re
import sys
import zipfile

ROOT = Path(__file__).resolve().parents[1]
MOD = ROOT / "mod"


def validate():
    info = json.loads((MOD / "info.json").read_text())
    for field in ("name", "version", "title", "author", "factorio_version"):
        if not isinstance(info.get(field), str) or not info[field]:
            raise ValueError(f"Missing or invalid info.json field: {field}")
    if not re.fullmatch(r"[A-Za-z0-9_-]+", info["name"]):
        raise ValueError("Invalid mod name")
    if not re.fullmatch(r"\d+\.\d+\.\d+", info["version"]) or any(
        int(part) > 65535 for part in info["version"].split(".")
    ):
        raise ValueError("Invalid mod version")
    if info["factorio_version"] != "2.0":
        raise ValueError("This project targets Factorio 2.0")
    for name in ("control.lua", "data.lua", "settings.lua"):
        if not (MOD / name).is_file():
            raise ValueError(f"Missing entry point: {name}")
    return info


def build(output_dir=None):
    info = validate()
    stem = f'{info["name"]}_{info["version"]}'
    output_dir = Path(output_dir) if output_dir else ROOT / "dist"
    output_dir.mkdir(parents=True, exist_ok=True)
    target = output_dir / f"{stem}.zip"
    # Stored entries avoid compression-library differences across machines.
    with zipfile.ZipFile(target, "w", compression=zipfile.ZIP_STORED) as archive:
        for source in sorted(MOD.rglob("*")):
            if source.is_symlink():
                raise ValueError(f"Symlinks are not distributable: {source}")
            if not source.is_file():
                continue
            relative = source.relative_to(MOD)
            if any(part.startswith(".") for part in relative.parts):
                continue
            if source.suffix not in {".lua", ".json", ".cfg", ".png", ".ogg", ".txt"}:
                raise ValueError(f"Unexpected distributable file: {relative}")
            entry = zipfile.ZipInfo(f"{stem}/{relative.as_posix()}", (1980, 1, 1, 0, 0, 0))
            entry.create_system = 3
            entry.external_attr = 0o100644 << 16
            archive.writestr(entry, source.read_bytes())
    return target


if __name__ == "__main__":
    if sys.argv[1:] == ["--validate"]:
        validate()
        print("Mod metadata and entry points are valid")
    elif not sys.argv[1:]:
        print(build())
    else:
        sys.exit("Usage: python3 scripts/package.py [--validate]")
