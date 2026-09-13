"""Regression tests for packaging and the Lua harness's failure contract."""

import importlib.util
import hashlib
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("package", ROOT / "scripts/package.py")
package = importlib.util.module_from_spec(spec)
spec.loader.exec_module(package)

install_spec = importlib.util.spec_from_file_location("install_local", ROOT / "scripts/install_local.py")
install_local = importlib.util.module_from_spec(install_spec)
install_spec.loader.exec_module(install_local)


class PackagingTests(unittest.TestCase):
    def test_reproducible_and_installable(self):
        with tempfile.TemporaryDirectory() as tmp:
            first = package.build(Path(tmp) / "first")
            second = package.build(Path(tmp) / "second")
            self.assertEqual(first.read_bytes(), second.read_bytes())
            with zipfile.ZipFile(first) as archive:
                self.assertIsNone(archive.testzip())
                names = archive.namelist()
                self.assertEqual(names, sorted(names))
                stem = first.stem
                self.assertIn(f"{stem}/info.json", names)
                self.assertIn(f"{stem}/control.lua", names)
                self.assertTrue(all(name.startswith(f"{stem}/") for name in names))
                self.assertFalse(any("tests/" in name or "AGENTS" in name for name in names))


class GuiFixtureTests(unittest.TestCase):
    def test_fixture_is_present_and_matches_its_pinned_checksum(self):
        fixture = ROOT / "tests/fixtures/gui-test-fixture.zip"
        checksum = ROOT / "tests/fixtures/gui-test-fixture.sha256"
        self.assertTrue(fixture.is_file())
        self.assertTrue(checksum.is_file())
        expected, recorded_path = checksum.read_text().split()
        self.assertEqual(recorded_path, "tests/fixtures/gui-test-fixture.zip")
        self.assertEqual(hashlib.sha256(fixture.read_bytes()).hexdigest(), expected)


class LocalInstallTests(unittest.TestCase):
    def test_resolves_native_and_wsl_mods_paths(self):
        home = Path("/home/tester")
        self.assertEqual(
            install_local.resolve_mods_dir({}, "Linux", home, proc_version=Path("/missing")),
            home / ".factorio" / "mods",
        )
        self.assertEqual(
            install_local.resolve_mods_dir({}, "Darwin", home),
            home / "Library" / "Application Support" / "factorio" / "mods",
        )
        self.assertEqual(
            install_local.resolve_mods_dir(
                {"WSL_DISTRO_NAME": "Ubuntu", "APPDATA": "/mnt/c/Users/test/AppData/Roaming"},
                "Linux",
                home,
            ),
            Path("/mnt/c/Users/test/AppData/Roaming/Factorio/mods"),
        )

    def test_converts_windows_appdata_when_running_under_wsl(self):
        calls = []

        def run(command, **_):
            calls.append(command)
            return type("Result", (), {"stdout": "/mnt/c/Users/test/AppData/Roaming\n"})()

        self.assertEqual(
            install_local.resolve_mods_dir(
                {"WSL_INTEROP": "1", "APPDATA": "C:\\Users\\test\\AppData\\Roaming"},
                "Linux",
                "/home/tester",
                run=run,
            ),
            Path("/mnt/c/Users/test/AppData/Roaming/Factorio/mods"),
        )
        self.assertEqual(calls, [["wslpath", "-u", "C:\\Users\\test\\AppData\\Roaming"]])

    def test_installs_canonical_zip_and_only_replaces_this_mod(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            output = root / "output"
            output.mkdir()
            package_path = output / "factorio-rules_0.1.0.zip"
            package_path.write_bytes(b"current package")
            mods = root / "mods"
            mods.mkdir()
            (mods / "factorio-rules_0.0.9.zip").write_bytes(b"stale package")
            (mods / "other-mod_1.0.0.zip").write_bytes(b"other package")

            package = install_local.package_from_output(output)
            destination = install_local.install(package, mods)

            self.assertEqual(destination, mods / package.name)
            self.assertEqual(destination.read_bytes(), b"current package")
            self.assertFalse((mods / "factorio-rules_0.0.9.zip").exists())
            self.assertEqual((mods / "other-mod_1.0.0.zip").read_bytes(), b"other package")


class HarnessTests(unittest.TestCase):
    def run_spec(self, source):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "example.lua"
            path.write_text(source)
            return subprocess.run(
                [os.environ.get("LUA", "lua"), "tests/run.lua", str(path)],
                cwd=ROOT, capture_output=True, text=True,
            )

    def test_failure_is_nonzero_and_later_cases_still_run(self):
        result = self.run_spec('''return {
          {name="fails", run=function() assert(false, "expected failure") end},
          {name="later", run=function() end}
        }''')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("expected failure", result.stderr)
        self.assertIn("ok -", result.stdout)
        self.assertIn("2 tests, 1 failures", result.stdout)

    def test_invalid_and_empty_suites_fail(self):
        for source in ("return {}", "error('broken spec')", 'return {{name="missing run"}}'):
            with self.subTest(source=source):
                self.assertNotEqual(self.run_spec(source).returncode, 0)

    def test_no_specs_fails(self):
        result = subprocess.run([os.environ.get("LUA", "lua"), "tests/run.lua"],
                                cwd=ROOT, capture_output=True)
        self.assertNotEqual(result.returncode, 0)


if __name__ == "__main__":
    unittest.main()
