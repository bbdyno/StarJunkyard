from __future__ import annotations

import importlib.util
import sys
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("validate_project", ROOT / "tools" / "validate_project.py")
assert SPEC and SPEC.loader
VALIDATOR = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = VALIDATOR
SPEC.loader.exec_module(VALIDATOR)
SIMULATION_SPEC = importlib.util.spec_from_file_location("reference_simulation", ROOT / "tools" / "reference_simulation.py")
assert SIMULATION_SPEC and SIMULATION_SPEC.loader
SIMULATION = importlib.util.module_from_spec(SIMULATION_SPEC)
sys.modules[SIMULATION_SPEC.name] = SIMULATION
SIMULATION_SPEC.loader.exec_module(SIMULATION)


class ProjectContractTests(unittest.TestCase):
    def test_development_contracts_pass(self) -> None:
        summary = VALIDATOR.validate_project(release=False)
        self.assertIn("20 stages", summary)
        self.assertIn("3 golden fixtures", summary)
        self.assertIn("5 ethical iOS IAP products", summary)

    def test_release_accepts_only_verified_production_assets(self) -> None:
        summary = VALIDATOR.validate_project(release=True)
        self.assertIn("11 pixel assets (release mode)", summary)

        asset_manifest = VALIDATOR.load_json("art-export/asset-manifest.json")
        self.assertTrue(
            all(asset["status"] == "production_ready" for asset in asset_manifest["assets"])
        )

    def test_release_rejects_any_asset_returned_to_planned(self) -> None:
        asset_manifest = VALIDATOR.load_json("art-export/asset-manifest.json")
        asset_manifest["assets"][0]["status"] = "planned"
        palette = VALIDATOR.load_palette("art-source/palettes/common16.gpl")

        with self.assertRaisesRegex(VALIDATOR.ContractError, "cannot enter a release build"):
            VALIDATOR.validate_assets(asset_manifest, set(), palette, release=True)

    def test_canonical_digest_ignores_key_order(self) -> None:
        left = {"stage": 1, "state": {"hp": 0, "clear": True}}
        right = {"state": {"clear": True, "hp": 0}, "stage": 1}
        self.assertEqual(VALIDATOR.canonical_digest(left), VALIDATOR.canonical_digest(right))

    def test_palette_has_exactly_sixteen_colors(self) -> None:
        colors = VALIDATOR.load_palette("art-source/palettes/common16.gpl")
        self.assertEqual(16, len(colors))

    def test_golden_states_match_reference_simulation(self) -> None:
        manifest = VALIDATOR.load_json("content/manifest.json")
        for relative_path in manifest["goldenFiles"]:
            fixture = VALIDATOR.load_json(relative_path)
            self.assertEqual(fixture["expectedState"], SIMULATION.simulate(fixture["input"]))


if __name__ == "__main__":
    unittest.main()
