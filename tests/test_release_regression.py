from __future__ import annotations

import importlib.util
import sys
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "release_regression", ROOT / "tools" / "release_regression.py"
)
assert SPEC and SPEC.loader
REGRESSION = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = REGRESSION
SPEC.loader.exec_module(REGRESSION)


class ReleaseRegressionTests(unittest.TestCase):
    def test_complete_plan_builds_release_and_tests_both_families(self) -> None:
        steps = REGRESSION.build_steps(ROOT / "Derived" / "Test", "PHONE", "TABLET", skip_ios=False)
        commands = [step.command for step in steps]

        self.assertTrue(any("Release" in command and "generic/platform=iOS" in command for command in commands))
        self.assertTrue(any("platform=iOS Simulator,id=PHONE" in command for command in commands))
        self.assertTrue(any("platform=iOS Simulator,id=TABLET" in command for command in commands))
        self.assertTrue(any("tools/validate_app_store_release.py" in command for command in commands))

    def test_device_selection_rejects_cross_family_and_prefers_known_models(self) -> None:
        payload = {
            "devices": {
                "runtime": [
                    {"name": "iPhone 15", "udid": "PHONE15", "isAvailable": True},
                    {"name": "iPhone 17", "udid": "PHONE17", "isAvailable": True},
                    {"name": "iPad Pro 13-inch (M4)", "udid": "IPAD13", "isAvailable": True},
                    {"name": "iPad Pro 13-inch (M5)", "udid": "OFF", "isAvailable": False},
                ]
            }
        }

        self.assertEqual("PHONE17", REGRESSION.select_device(payload, "iPhone"))
        self.assertEqual("IPAD13", REGRESSION.select_device(payload, "iPad"))

    def test_non_macos_plan_contains_only_repository_contracts(self) -> None:
        steps = REGRESSION.build_steps(ROOT / "Derived" / "Test", "PHONE", "TABLET", skip_ios=True)

        self.assertEqual(3, len(steps))
        self.assertFalse(any(step.command[0] in {"tuist", "xcodebuild"} for step in steps))


if __name__ == "__main__":
    unittest.main()
