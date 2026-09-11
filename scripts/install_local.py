"""Install the canonical Nix package into a Factorio mods directory."""

import argparse
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess
import tempfile


MOD_ARCHIVE = re.compile(r"^factorio-rules_.+\.zip$")


def is_wsl(environ, proc_version=Path("/proc/version")):
    if environ.get("WSL_DISTRO_NAME") or environ.get("WSL_INTEROP"):
        return True
    try:
        return "microsoft" in proc_version.read_text().lower()
    except OSError:
        return False


def windows_mods_dir(environ, run):
    appdata = environ.get("APPDATA")
    if not appdata:
        appdata = run(
            ["cmd.exe", "/c", "echo", "%APPDATA%"],
            check=True,
            capture_output=True,
            text=True,
        ).stdout.strip()
    if not appdata:
        raise ValueError("Windows AppData is unavailable; pass --mods-dir explicitly")
    if appdata.startswith("/"):
        return Path(appdata) / "Factorio" / "mods"
    converted = run(
        ["wslpath", "-u", appdata], check=True, capture_output=True, text=True
    ).stdout.strip()
    if not converted:
        raise ValueError("Could not convert Windows AppData; pass --mods-dir explicitly")
    return Path(converted) / "Factorio" / "mods"


def resolve_mods_dir(environ=None, system=None, home=None, run=subprocess.run, proc_version=Path("/proc/version")):
    environ = os.environ if environ is None else environ
    system = platform.system() if system is None else system
    home = Path.home() if home is None else Path(home)
    if system == "Linux":
        if is_wsl(environ, proc_version):
            try:
                return windows_mods_dir(environ, run)
            except (OSError, subprocess.CalledProcessError) as error:
                raise ValueError(
                    "Could not find Windows Factorio mods; pass --mods-dir explicitly"
                ) from error
        return home / ".factorio" / "mods"
    if system == "Darwin":
        return home / "Library" / "Application Support" / "factorio" / "mods"
    if system == "Windows":
        appdata = environ.get("APPDATA")
        if appdata:
            return Path(appdata) / "Factorio" / "mods"
        raise ValueError("Windows AppData is unavailable; pass --mods-dir explicitly")
    raise ValueError(f"Unsupported platform {system}; pass --mods-dir explicitly")


def package_from_output(output):
    packages = sorted(Path(output).glob("*.zip"))
    if len(packages) != 1:
        raise ValueError(f"Expected one mod zip in {output}, found {len(packages)}")
    return packages[0]


def install(package, mods_dir):
    package = Path(package)
    mods_dir = Path(mods_dir)
    if not package.is_file() or not MOD_ARCHIVE.fullmatch(package.name):
        raise ValueError(f"Expected a Factorio Rules package zip, got {package}")
    mods_dir.mkdir(parents=True, exist_ok=True)
    destination = mods_dir / package.name
    with tempfile.NamedTemporaryFile(dir=mods_dir, prefix=package.name, suffix=".tmp", delete=False) as temporary:
        temporary_path = Path(temporary.name)
    try:
        shutil.copyfile(package, temporary_path)
        os.replace(temporary_path, destination)
    finally:
        temporary_path.unlink(missing_ok=True)
    for stale in mods_dir.glob("factorio-rules_*.zip"):
        if stale != destination:
            stale.unlink()
    return destination


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("package_output", help="Nix package output containing the canonical mod zip")
    parser.add_argument("--mods-dir", type=Path, help="Factorio mods directory override")
    args = parser.parse_args(argv)
    package = package_from_output(args.package_output)
    mods_dir = args.mods_dir or resolve_mods_dir()
    destination = install(package, mods_dir)
    print(f"Installed {destination.name} to {destination.parent}")


if __name__ == "__main__":
    main()
