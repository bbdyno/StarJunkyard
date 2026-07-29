from __future__ import annotations

import importlib.util
import sys
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "validate_android_pixel_shell", ROOT / "tools" / "validate_android_pixel_shell.py"
)
assert SPEC and SPEC.loader
VALIDATOR = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = VALIDATOR
SPEC.loader.exec_module(VALIDATOR)


class AndroidPixelShellTests(unittest.TestCase):
    def test_game_first_surface_contract_passes(self) -> None:
        summary = VALIDATOR.validate_android_pixel_shell()
        self.assertIn("one SurfaceView", summary)
        self.assertIn("360x800 integer Canvas", summary)


if __name__ == "__main__":
    unittest.main()
