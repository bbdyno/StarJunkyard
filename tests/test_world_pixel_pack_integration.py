from __future__ import annotations

import copy
import hashlib
import importlib.util
import json
import struct
import sys
import tempfile
import unittest
import zlib
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "integrate_world_pixel_packs",
    ROOT / "tools" / "integrate_world_pixel_packs.py",
)
assert SPEC and SPEC.loader
INTEGRATOR = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = INTEGRATOR
SPEC.loader.exec_module(INTEGRATOR)

GENERATOR_SPEC = importlib.util.spec_from_file_location(
    "generate_world_content_for_pack_test",
    ROOT / "tools" / "generate_world_content.py",
)
assert GENERATOR_SPEC and GENERATOR_SPEC.loader
GENERATOR = importlib.util.module_from_spec(GENERATOR_SPEC)
sys.modules[GENERATOR_SPEC.name] = GENERATOR
GENERATOR_SPEC.loader.exec_module(GENERATOR)


PALETTE = [
    (17, 29, 51),
    (228, 87, 46),
    (243, 167, 18),
    (123, 135, 148),
    (53, 167, 160),
    (240, 113, 103),
    (9, 11, 26),
    (74, 78, 155),
    (140, 110, 217),
    (216, 243, 255),
    (23, 18, 31),
    (107, 91, 62),
    (217, 180, 74),
    (228, 90, 157),
    (245, 235, 207),
    (80, 93, 107),
]


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write_json(path: Path, value: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def png_chunk(kind: bytes, data: bytes) -> bytes:
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)


def write_fixture_png(path: Path, width: int, height: int, marker: int, outside_palette: bool = False) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    rows: list[bytes] = []
    for y in range(height):
        row = bytearray([0])
        for x in range(width):
            if x < 8 and y == 0 and marker & (1 << x):
                color = (1, 2, 3) if outside_palette else PALETTE[(x + marker) % len(PALETTE)]
                row.extend((*color, 255))
            else:
                row.extend((0, 0, 0, 0))
        rows.append(bytes(row))
    payload = b"\x89PNG\r\n\x1a\n"
    payload += png_chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
    payload += png_chunk(b"IDAT", zlib.compress(b"".join(rows), level=9))
    payload += png_chunk(b"IEND", b"")
    path.write_bytes(payload)


def write_palette(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    lines = ["GIMP Palette", "Name: fixture", "Columns: 16", "#"]
    lines.extend(f"{red:3d} {green:3d} {blue:3d} fixture" for red, green, blue in PALETTE)
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


class PixelPackFixture:
    def __init__(self, root: Path) -> None:
        self.root = root
        self.world_path = root / "content/world_r1_r6.json"
        self.manifest_path = root / "art-export/asset-manifest.json"
        self.world_path.parent.mkdir(parents=True, exist_ok=True)
        self.manifest_path.parent.mkdir(parents=True, exist_ok=True)
        self.world_path.write_bytes((ROOT / "content/world_r1_r6.json").read_bytes())
        self.manifest_path.write_bytes((ROOT / "art-export/asset-manifest.json").read_bytes())
        self.world = INTEGRATOR.load_json(self.world_path)
        self.world_hash = sha256(self.world_path)
        self.marker = 1

    def make_fragment(self, issue: int) -> Path:
        region_ids = INTEGRATOR.PACK_REGIONS[issue]
        package = f"issue-{issue}-fixture"
        regions: list[dict] = []
        assets: list[dict] = []
        enemy_by_region = {
            region_id: [enemy for enemy in self.world["enemies"] if enemy["regionId"] == region_id]
            for region_id in region_ids
        }

        for region_id in region_ids:
            canonical_region = next(region for region in self.world["regions"] if region["id"] == region_id)
            palette_file = f"art-source/{package}/palettes/{region_id}_fixture.gpl"
            write_palette(self.root / palette_file)
            regions.append({
                "id": region_id,
                "nameKo": canonical_region["nameKo"],
                "paletteFile": palette_file,
                "paletteAnchors": ["#111D33", "#E4572E", "#F3A712", "#7B8794"],
                "eliteStageAllocation": INTEGRATOR.expected_elite_allocation(self.world, region_id),
            })
            for enemy in enemy_by_region[region_id]:
                if enemy["class"] == "normal":
                    kind, canvas, pivot, prefix = "enemy_medium", [48, 48], [24, 42], "enemy"
                elif enemy["class"] == "elite":
                    kind, canvas, pivot, prefix = "enemy_large", [64, 64], [32, 58], "elite"
                else:
                    kind, canvas, pivot, prefix = "boss", [128, 96], [64, 90], "boss"
                identifier = f"{prefix}_{region_id}_{enemy['id']}"
                assets.append(self.make_asset(
                    issue=issue,
                    package=package,
                    region_id=region_id,
                    identifier=identifier,
                    entity_id=enemy["id"],
                    name=enemy["nameKo"],
                    enemy_class=enemy["class"],
                    kind=kind,
                    canvas=canvas,
                    pivot=pivot,
                    palette_file=palette_file,
                    contract=enemy,
                ))
            background_id = f"background_{region_id}_fixture"
            assets.append(self.make_asset(
                issue=issue,
                package=package,
                region_id=region_id,
                identifier=background_id,
                entity_id=background_id,
                name=canonical_region["nameKo"] + " 배경",
                enemy_class="background",
                kind="background",
                canvas=[360, 572],
                pivot=[0, 572],
                palette_file=palette_file,
                contract=None,
            ))

        fragment = {
            "schemaVersion": 1,
            "issue": issue,
            "sourceContract": {
                "path": "issue-38/content/world_r1_r6.json",
                "sha256": self.world_hash,
            },
            "regions": regions,
            "assets": assets,
        }
        path = self.root / f"art-export/{package}/manifest-fragment.json"
        write_json(path, fragment)
        return path

    def make_asset(
        self,
        *,
        issue: int,
        package: str,
        region_id: str,
        identifier: str,
        entity_id: str,
        name: str,
        enemy_class: str,
        kind: str,
        canvas: list[int],
        pivot: list[int],
        palette_file: str,
        contract: dict | None,
    ) -> dict:
        marker = self.marker
        self.marker += 1
        source_file = f"art-source/{package}/originals/{identifier}.png"
        output_file = f"art-export/{package}/production/{identifier}.png"
        source_path = self.root / source_file
        source_path.parent.mkdir(parents=True, exist_ok=True)
        source_path.write_bytes(f"fixture-imagegen-source-{issue}-{marker}-{identifier}".encode())
        write_fixture_png(self.root / output_file, canvas[0], canvas[1], marker)
        asset = {
            "id": identifier,
            "regionId": region_id,
            "entityId": entity_id,
            "nameKo": name,
            "nameEn": identifier,
            "class": enemy_class,
            "kind": kind,
            "behaviorId": contract["behaviorId"] if contract else "static_battle_lane",
            "behaviorKo": contract["behaviorKo"] if contract else "전투 배경",
            "weakness": contract["weakness"] if contract else "none",
            "secondaryWeaknesses": contract["secondaryWeaknesses"] if contract else [],
            "breakSequenceKo": contract["breakSequenceKo"] if contract else "해당 없음",
            "canvas": canvas,
            "pivot": pivot,
            "paletteFile": palette_file,
            "scalePolicy": "integer_nearest",
            "status": "production_ready",
            "sourceFile": source_file,
            "imagegenCallArtifacts": [f"exec-{issue}-{marker:04d}-{identifier}.png"],
            "file": output_file,
            "sourceSha256": sha256(source_path),
            "sha256": sha256(self.root / output_file),
            "verified": {
                "binaryAlpha": True,
                "transparentCorners": enemy_class != "background",
                "strictPalette": True,
                "greenFringePixels": 0,
            },
        }
        return asset


class WorldPixelPackIntegrationTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.fixture = PixelPackFixture(self.root)

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def load_fragment(self, path: Path) -> dict:
        return json.loads(path.read_text(encoding="utf-8"))

    def save_fragment(self, path: Path, fragment: dict) -> None:
        write_json(path, fragment)

    def validate(self, *paths: Path) -> list:
        evidence = INTEGRATOR.EvidenceRegistry()
        return [
            INTEGRATOR.validate_fragment(
                self.root,
                path,
                self.fixture.world,
                self.fixture.world_hash,
                evidence,
            )
            for path in paths
        ]

    def test_check_contracts_is_read_only_at_r2_checkpoint(self) -> None:
        before = self.fixture.world_path.read_bytes()
        summary = INTEGRATOR.check_world_contracts(self.fixture.world)
        self.assertIn("32 entities", summary)
        self.assertEqual(120, self.fixture.world["slice"]["productionStageEnd"])
        self.assertEqual(before, self.fixture.world_path.read_bytes())

    def test_registered_pack_branches_route_to_their_own_builder_and_fragment(self) -> None:
        builder44, fragment44, arguments44 = INTEGRATOR.current_pack_config("issue/44-r3-r4-pixel-pack")
        builder45, fragment45, arguments45 = INTEGRATOR.current_pack_config("issue/45-r5-r6-pixel-pack")
        self.assertEqual(Path("tools/issue44_build_r3_r4_pixel_pack.py"), builder44)
        self.assertEqual(INTEGRATOR.DEFAULT_FRAGMENTS[44], fragment44)
        self.assertEqual(Path("tools/issue45_build_r5_r6_pixel_pack.py"), builder45)
        self.assertEqual(INTEGRATOR.DEFAULT_FRAGMENTS[45], fragment45)
        self.assertEqual(("--all", "--verify-complete"), arguments44)
        self.assertEqual(arguments44, arguments45)
        with self.assertRaisesRegex(INTEGRATOR.IntegrationError, "not a registered"):
            INTEGRATOR.current_pack_config("issue/38-r2-r6-content")

    def test_exact_entity_fields_reject_any_contract_drift(self) -> None:
        path = self.fixture.make_fragment(44)
        original = self.load_fragment(path)
        asset_index = next(index for index, asset in enumerate(original["assets"]) if asset["class"] != "background")
        mutations = {
            "entityId": "not_a_canonical_entity",
            "nameKo": "이름 변경 금지",
            "behaviorId": "changed_behavior",
            "behaviorKo": "행동 변경 금지",
            "weakness": "heat",
            "secondaryWeaknesses": ["heat"],
            "breakSequenceKo": "파괴 순서 변경 금지",
        }
        for field_name, value in mutations.items():
            with self.subTest(field=field_name):
                fragment = copy.deepcopy(original)
                fragment["assets"][asset_index][field_name] = value
                self.save_fragment(path, fragment)
                with self.assertRaises(INTEGRATOR.IntegrationError):
                    self.validate(path)
        self.save_fragment(path, original)

    def test_rejects_reused_imagegen_and_hash_evidence(self) -> None:
        path = self.fixture.make_fragment(44)
        original = self.load_fragment(path)
        scenarios = ("artifact", "source", "output")
        for scenario in scenarios:
            with self.subTest(scenario=scenario):
                fragment = copy.deepcopy(original)
                first, second = fragment["assets"][0], fragment["assets"][1]
                if scenario == "artifact":
                    second["imagegenCallArtifacts"] = first["imagegenCallArtifacts"]
                elif scenario == "source":
                    second["sourceFile"] = first["sourceFile"]
                    second["sourceSha256"] = first["sourceSha256"]
                else:
                    second["file"] = first["file"]
                    second["sha256"] = first["sha256"]
                    second["canvas"] = first["canvas"]
                self.save_fragment(path, fragment)
                with self.assertRaisesRegex(INTEGRATOR.IntegrationError, "reused provenance"):
                    self.validate(path)
        self.save_fragment(path, original)

    def test_rejects_planned_missing_hash_and_out_of_palette_assets(self) -> None:
        path = self.fixture.make_fragment(44)
        original = self.load_fragment(path)

        planned = copy.deepcopy(original)
        planned["assets"][0]["status"] = "planned"
        self.save_fragment(path, planned)
        with self.assertRaisesRegex(INTEGRATOR.IntegrationError, "not production_ready"):
            self.validate(path)

        wrong_hash = copy.deepcopy(original)
        wrong_hash["assets"][0]["sha256"] = "0" * 64
        self.save_fragment(path, wrong_hash)
        with self.assertRaisesRegex(INTEGRATOR.IntegrationError, "sha256 mismatch"):
            self.validate(path)

        outside = copy.deepcopy(original)
        asset = outside["assets"][0]
        output = self.root / asset["file"]
        write_fixture_png(output, asset["canvas"][0], asset["canvas"][1], 1, outside_palette=True)
        asset["sha256"] = sha256(output)
        self.save_fragment(path, outside)
        with self.assertRaisesRegex(INTEGRATOR.IntegrationError, "outside strict palette"):
            self.validate(path)

    def test_complete_packs_build_final_promotion_without_touching_canonical_fields(self) -> None:
        issue44 = self.fixture.make_fragment(44)
        issue45 = self.fixture.make_fragment(45)
        packs = self.validate(issue44, issue45)
        manifest = INTEGRATOR.load_json(self.fixture.manifest_path)
        updated_world, updated_manifest, promotions, copy_plan = INTEGRATOR.build_integration(
            self.root,
            self.fixture.world,
            manifest,
            packs,
        )
        self.assertEqual(360, updated_world["slice"]["productionStageEnd"])
        self.assertEqual(32, len(promotions["enemies"]))
        self.assertEqual(4, len(promotions["regions"]))
        self.assertEqual(36, len(copy_plan))
        self.assertEqual(len(manifest["assets"]) + 36, len(updated_manifest["assets"]))
        for before in self.fixture.world["enemies"]:
            after = next(enemy for enemy in updated_world["enemies"] if enemy["id"] == before["id"])
            for field_name in INTEGRATOR.EXACT_ENTITY_FIELDS:
                self.assertEqual(before[field_name], after[field_name])
        regenerated = GENERATOR.apply_pixel_pack_promotions(
            GENERATOR.build(promotions_path=None),
            promotions,
        )
        self.assertEqual(updated_world, regenerated)

    def test_apply_requires_both_packs_and_writes_only_after_validation(self) -> None:
        issue44 = self.fixture.make_fragment(44)
        pack44 = self.validate(issue44)
        with self.assertRaisesRegex(INTEGRATOR.IntegrationError, "requires complete"):
            INTEGRATOR.build_integration(
                self.root,
                self.fixture.world,
                INTEGRATOR.load_json(self.fixture.manifest_path),
                pack44,
            )
        self.assertEqual(120, INTEGRATOR.load_json(self.fixture.world_path)["slice"]["productionStageEnd"])
        self.assertFalse((self.root / INTEGRATOR.PROMOTIONS_PATH).exists())

        issue45 = self.fixture.make_fragment(45)
        packs = self.validate(issue44, issue45)
        INTEGRATOR.apply_integration(
            self.root,
            self.fixture.world_path,
            self.fixture.manifest_path,
            packs,
        )
        integrated = INTEGRATOR.load_json(self.fixture.world_path)
        self.assertEqual(360, integrated["slice"]["productionStageEnd"])
        self.assertTrue((self.root / INTEGRATOR.PROMOTIONS_PATH).is_file())
        self.assertTrue(all(enemy["assetStatus"] == "production_ready" for enemy in integrated["enemies"]))
        self.assertTrue((self.root / "art-export/production/sprites/background_r06_fixture.png").is_file())


if __name__ == "__main__":
    unittest.main()
