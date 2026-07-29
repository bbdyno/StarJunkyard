from __future__ import annotations

import importlib.util
import sys
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "select_ios_simulator", ROOT / "tools" / "select_ios_simulator.py"
)
assert SPEC and SPEC.loader
SELECTOR = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = SELECTOR
SPEC.loader.exec_module(SELECTOR)


class IOSSimulatorSelectorTests(unittest.TestCase):
    def test_prefers_known_available_iphone_over_ipad_and_unavailable_device(self) -> None:
        payload = {
            "devices": {
                "com.apple.CoreSimulator.SimRuntime.iOS-26-0": [
                    {"name": "iPad Pro", "udid": "IPAD", "isAvailable": True},
                    {"name": "iPhone 17 Pro", "udid": "OFF", "isAvailable": False},
                    {"name": "iPhone 16", "udid": "PHONE16", "isAvailable": True},
                    {"name": "iPhone 15", "udid": "PHONE15", "isAvailable": True},
                ]
            }
        }

        self.assertEqual("PHONE16", SELECTOR.select_simulator(payload))

    def test_fails_when_no_iphone_is_available(self) -> None:
        with self.assertRaisesRegex(ValueError, "no available iPhone"):
            SELECTOR.select_simulator({"devices": {}})


if __name__ == "__main__":
    unittest.main()
