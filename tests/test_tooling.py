"""Regression tests for packaging and the Lua harness's failure contract."""

import importlib.util
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
