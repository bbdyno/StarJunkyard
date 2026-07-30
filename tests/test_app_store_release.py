from __future__ import annotations

import importlib.util
import json
import sys
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "validate_app_store_release", ROOT / "tools" / "validate_app_store_release.py"
)
assert SPEC and SPEC.loader
VALIDATOR = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = VALIDATOR
SPEC.loader.exec_module(VALIDATOR)


class AppStoreReleaseTests(unittest.TestCase):
    def test_repository_release_contract_passes(self) -> None:
        summary = VALIDATOR.validate_release()

        self.assertTrue(any("localizations" in item for item in summary))
        self.assertTrue(any("external blockers" in item for item in summary))

    def test_storekit_count_follows_the_current_catalog(self) -> None:
        catalog = json.loads((ROOT / "content" / "ios-iap-catalog.json").read_text(encoding="utf-8"))
        blockers = VALIDATOR.validate_blockers()

        product_count, state = VALIDATOR.validate_storekit(blockers)

        self.assertEqual(len(catalog["products"]), product_count)
        self.assertIn(state, {"catalog-only", "configured"})

    def test_app_icon_keeps_game_subjects_at_small_display_size(self) -> None:
        icon = ROOT / "StarJunkyard" / "Resources" / "Assets.xcassets" / "AppIcon.appiconset" / "AppIcon-1024.png"

        metrics = VALIDATOR.validate_small_icon_readability(icon)

        self.assertGreaterEqual(metrics["centralBrightBlocks"], 40)
        self.assertGreaterEqual(metrics["warmCharacterBlocks"], 250)
        self.assertGreaterEqual(metrics["strongEdges"], 400)


if __name__ == "__main__":
    unittest.main()
