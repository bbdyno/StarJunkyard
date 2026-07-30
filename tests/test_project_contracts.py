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
ECONOMY_SPEC = importlib.util.spec_from_file_location("economy_simulation", ROOT / "tools" / "economy_simulation.py")
assert ECONOMY_SPEC and ECONOMY_SPEC.loader
ECONOMY = importlib.util.module_from_spec(ECONOMY_SPEC)
sys.modules[ECONOMY_SPEC.name] = ECONOMY
ECONOMY_SPEC.loader.exec_module(ECONOMY)
GENERATOR_SPEC = importlib.util.spec_from_file_location("generate_r1_content", ROOT / "tools" / "generate_r1_content.py")
assert GENERATOR_SPEC and GENERATOR_SPEC.loader
GENERATOR = importlib.util.module_from_spec(GENERATOR_SPEC)
sys.modules[GENERATOR_SPEC.name] = GENERATOR
GENERATOR_SPEC.loader.exec_module(GENERATOR)


class ProjectContractTests(unittest.TestCase):
    def test_development_contracts_pass(self) -> None:
        summary = VALIDATOR.validate_project(release=False)
        self.assertIn("60 stages", summary)
        self.assertIn("3 golden fixtures", summary)
        self.assertIn("2 economy golden fixtures", summary)
        self.assertIn("6 ethical iOS IAP products", summary)

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

    def test_storekit_configuration_matches_typed_catalog(self) -> None:
        self.assertEqual(6, VALIDATOR.validate_ios_iap_catalog())

    def test_golden_states_match_reference_simulation(self) -> None:
        manifest = VALIDATOR.load_json("content/manifest.json")
        for relative_path in manifest["goldenFiles"]:
            fixture = VALIDATOR.load_json(relative_path)
            self.assertEqual(fixture["expectedState"], SIMULATION.simulate(fixture["input"]))

    def test_r1_stage_rules_are_complete_through_region_boss(self) -> None:
        content = VALIDATOR.load_json("content/r1_vertical_slice.json")
        self.assertEqual(content["stages"], GENERATOR.build()["stages"])
        self.assertEqual(list(range(1, 61)), [stage["number"] for stage in content["stages"]])
        for stage in content["stages"]:
            number = stage["number"]
            expected = (
                "regionBoss" if number == 60
                else "boss" if number % 10 == 0
                else "elite" if number % 5 == 0
                else "normal"
            )
            self.assertEqual(expected, stage["encounterClass"])
        self.assertEqual(6, content["stages"][59]["bossTier"])
        self.assertEqual(1, content["stages"][59]["firstClearReward"]["starCores"])

    def test_offline_contract_uses_last_clear_at_seventy_percent(self) -> None:
        content = VALIDATOR.load_json("content/r1_vertical_slice.json")
        stage_43 = content["stages"][42]
        full_cycle = ECONOMY.battle_reward(stage_43, content)
        state = ECONOMY.simulate(
            {"activeSeconds": 1800, "offlineSeconds": 75, "purchases": []},
            content,
        )
        self.assertEqual(43, state["highestClearedStage"])
        self.assertEqual(1, state["offlineCycles"])
        self.assertEqual(full_cycle["credits"] * 700_000 // 1_000_000, state["offlineReward"]["credits"])
        self.assertEqual(0, state["offlineReward"]["starCores"])

    def test_economy_golden_states_match_reproducible_simulation(self) -> None:
        manifest = VALIDATOR.load_json("content/manifest.json")
        for relative_path in manifest["economyGoldenFiles"]:
            fixture = VALIDATOR.load_json(relative_path)
            self.assertEqual(fixture["expectedState"], ECONOMY.simulate(fixture["input"]))

    def test_first_day_reaches_a_funded_r2_launch(self) -> None:
        fixture = VALIDATOR.load_json("golden/economy/first_day.json")
        state = fixture["expectedState"]
        self.assertEqual(60, state["highestClearedStage"])
        self.assertTrue(state["launchEligible"])
        self.assertEqual(6, len(state["purchasedSinkIds"]))
        self.assertEqual(0, state["walletAfterLaunch"]["starCores"])
        self.assertTrue(all(value >= 0 for value in state["walletAfterLaunch"].values()))
        self.assertEqual(28_800, state["offlineSecondsApplied"])


if __name__ == "__main__":
    unittest.main()
