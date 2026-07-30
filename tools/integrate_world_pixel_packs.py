#!/usr/bin/env python3
"""Validate and safely promote the R3-R6 production pixel packs.

Contract checks are read-only. Promotion requires both issue fragments and only
writes after every entity, provenance, hash, PNG, and palette check succeeds.
"""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
import shutil
import subprocess
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Iterable


ROOT = Path(__file__).resolve().parents[1]
TOOLS = Path(__file__).resolve().parent
if str(TOOLS) not in sys.path:
    sys.path.insert(0, str(TOOLS))

from validate_project import load_palette, read_png_pixels  # noqa: E402


WORLD_PATH = Path("content/world_r1_r6.json")
MANIFEST_PATH = Path("art-export/asset-manifest.json")
PROMOTIONS_PATH = Path("content/world-pixel-pack-promotions.json")
PACK_REGIONS = {44: ("r03", "r04"), 45: ("r05", "r06")}
DEFAULT_FRAGMENTS = {
    44: Path("art-export/issue-44-r3-r4/manifest-fragment.json"),
    45: Path("art-export/issue-45-r5-r6/manifest-fragment.json"),
}
BRANCH_PACKS = {
    "issue/44-r3-r4-pixel-pack": (
        Path("tools/issue44_build_r3_r4_pixel_pack.py"),
        DEFAULT_FRAGMENTS[44],
        ("--all", "--verify-complete"),
    ),
    "issue/45-r5-r6-pixel-pack": (
        Path("tools/issue45_build_r5_r6_pixel_pack.py"),
        DEFAULT_FRAGMENTS[45],
        ("--all", "--verify-complete"),
    ),
}
EXACT_ENTITY_FIELDS = (
    "nameKo",
    "class",
    "behaviorId",
    "behaviorKo",
    "weakness",
    "secondaryWeaknesses",
    "breakSequenceKo",
)


class IntegrationError(RuntimeError):
    """A pixel pack failed the immutable integration contract."""


def require(condition: bool, message: str) -> None:
    if not condition:
        raise IntegrationError(message)


def load_json(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise IntegrationError(f"cannot read {path}: {error}") from error
    require(isinstance(value, dict), f"{path}: root must be an object")
    return value


def safe_path(root: Path, relative: str, label: str) -> Path:
    candidate = Path(relative)
    require(not candidate.is_absolute() and ".." not in candidate.parts, f"{label}: unsafe path {relative!r}")
    return root / candidate


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def canonical_world_hash(world_path: Path) -> str:
    return sha256(world_path)


def check_world_contracts(world: dict[str, Any]) -> str:
    regions = world.get("regions", [])
    enemies = world.get("enemies", [])
    stages = world.get("stages", [])
    require([region.get("id") for region in regions] == [f"r{number:02d}" for number in range(1, 7)], "world must keep ordered R1-R6 regions")
    require([stage.get("number") for stage in stages] == list(range(1, 361)), "world must keep S001-S360")
    require(world.get("slice", {}).get("productionStageEnd") in {120, 360}, "productionStageEnd must be the R2 checkpoint or final world")
    enemy_ids = [enemy.get("id") for enemy in enemies]
    require(len(enemy_ids) == 48 and len(set(enemy_ids)) == 48, "world must define 48 unique enemies")

    for issue, region_ids in PACK_REGIONS.items():
        for region_id in region_ids:
            region = next((item for item in regions if item.get("id") == region_id), None)
            require(region is not None, f"issue {issue}: missing region {region_id}")
            owned = [enemy for enemy in enemies if enemy.get("regionId") == region_id]
            require(len(owned) == 8, f"{region_id}: expected eight canonical entities")
            require(sum(enemy.get("class") == "normal" for enemy in owned) == 4, f"{region_id}: expected four normals")
            require(sum(enemy.get("class") == "elite" for enemy in owned) == 2, f"{region_id}: expected two elites")
            require(sum(enemy.get("class") == "boss" for enemy in owned) == 2, f"{region_id}: expected two bosses")
            for enemy in owned:
                for field_name in EXACT_ENTITY_FIELDS:
                    require(field_name in enemy, f"{region_id}/{enemy.get('id')}: missing {field_name}")
    return "R3-R6 contracts ready: 4 regions / 32 entities / 4 backgrounds"


@dataclass
class EvidenceRegistry:
    artifacts: set[str] = field(default_factory=set)
    source_hashes: set[str] = field(default_factory=set)
    output_hashes: set[str] = field(default_factory=set)
    transparent_hashes: set[str] = field(default_factory=set)

    def add_unique(self, bucket: set[str], value: str, label: str) -> None:
        require(value not in bucket, f"{label}: reused provenance value {value}")
        bucket.add(value)


@dataclass(frozen=True)
class ValidatedPack:
    issue: int
    regions: tuple[str, ...]
    fragment: dict[str, Any]
    path: Path


def expected_elite_allocation(world: dict[str, Any], region_id: str) -> list[dict[str, Any]]:
    enemies = {enemy["id"]: enemy for enemy in world["enemies"]}
    return [
        {"localStage": stage["localStage"], "entityId": stage["wave"][-1]}
        for stage in world["stages"]
        if stage["regionId"] == region_id and stage["encounterClass"] == "elite"
        and enemies[stage["wave"][-1]]["class"] == "elite"
    ]


def validate_elite_allocation(world: dict[str, Any], region_id: str, allocation: Any) -> None:
    require(isinstance(allocation, list), f"{region_id}: elite stage allocation is required")
    expected = expected_elite_allocation(world, region_id)
    normalized: list[dict[str, Any]] = []
    region = next(item for item in world["regions"] if item["id"] == region_id)
    for item in allocation:
        require(isinstance(item, dict), f"{region_id}: elite allocation entries must be objects")
        require(set(item) <= {"localStage", "globalStage", "entityId"}, f"{region_id}: unknown elite allocation field")
        local_stage = item.get("localStage")
        if "globalStage" in item:
            require(item["globalStage"] == region["stageStart"] + local_stage - 1, f"{region_id}: global elite stage drift")
        normalized.append({"localStage": local_stage, "entityId": item.get("entityId")})
    require(normalized == expected, f"{region_id}: elite stage allocation drift")


def validate_png_asset(root: Path, asset: dict[str, Any], palette: set[tuple[int, int, int]]) -> None:
    identifier = asset["id"]
    output = safe_path(root, asset["file"], identifier)
    require(output.is_file(), f"{identifier}: production file is missing")
    require(sha256(output) == asset.get("sha256"), f"{identifier}: production sha256 mismatch")
    width, height, colors, partial_alpha = read_png_pixels(output)
    require([width, height] == asset.get("canvas"), f"{identifier}: PNG canvas mismatch")
    require(not partial_alpha, f"{identifier}: partial alpha is forbidden")
    require(colors <= palette, f"{identifier}: colors outside strict palette: {sorted(colors - palette)}")
    require((0, 255, 0) not in colors, f"{identifier}: chroma fringe reached production output")


def validate_fragment(
    root: Path,
    path: Path,
    world: dict[str, Any],
    world_hash: str,
    evidence: EvidenceRegistry,
) -> ValidatedPack:
    fragment = load_json(path)
    issue = fragment.get("issue")
    require(issue in PACK_REGIONS, f"{path}: issue must be 44 or 45")
    expected_regions = PACK_REGIONS[issue]
    require(fragment.get("schemaVersion") == 1, f"issue {issue}: fragment schemaVersion must be 1")
    source = fragment.get("sourceContract", {})
    require(source.get("path") == "issue-38/content/world_r1_r6.json", f"issue {issue}: source contract path drift")
    require(source.get("sha256") == world_hash, f"issue {issue}: source world hash drift")

    region_contracts = fragment.get("regions", [])
    require([region.get("id") for region in region_contracts] == list(expected_regions), f"issue {issue}: region order/ownership mismatch")
    canonical_regions = {region["id"]: region for region in world["regions"]}
    palette_by_region: dict[str, tuple[str, set[tuple[int, int, int]]]] = {}
    for region in region_contracts:
        region_id = region["id"]
        require(region.get("nameKo") == canonical_regions[region_id]["nameKo"], f"{region_id}: nameKo drift")
        validate_elite_allocation(world, region_id, region.get("eliteStageAllocation"))
        palette_file = region.get("paletteFile")
        require(isinstance(palette_file, str), f"{region_id}: paletteFile is required")
        palette_path = safe_path(root, palette_file, region_id)
        require(palette_path.is_file(), f"{region_id}: palette file is missing")
        palette_id = palette_path.stem
        palette = load_palette(palette_path.relative_to(root).as_posix()) if root == ROOT else _load_palette_at(palette_path)
        require(len(palette) == 16, f"{region_id}: production palette must contain exactly 16 colors")
        anchors = region.get("paletteAnchors", [])
        anchor_colors = {tuple(bytes.fromhex(anchor.removeprefix("#"))) for anchor in anchors}
        require(anchor_colors <= palette, f"{region_id}: palette anchors are not in the GPL palette")
        palette_by_region[region_id] = (palette_id, palette)

    assets = fragment.get("assets", [])
    require(len(assets) == 18, f"issue {issue}: expected exactly 18 assets")
    asset_ids = [asset.get("id") for asset in assets]
    require(len(set(asset_ids)) == len(asset_ids), f"issue {issue}: duplicate asset id")
    canonical_enemies = {enemy["id"]: enemy for enemy in world["enemies"]}

    for region_id in expected_regions:
        region_assets = [asset for asset in assets if asset.get("regionId") == region_id]
        require(len(region_assets) == 9, f"{region_id}: expected eight enemies and one background")
        background_assets = [asset for asset in region_assets if asset.get("class") == "background"]
        require(len(background_assets) == 1, f"{region_id}: expected one background")
        expected_entities = {enemy["id"] for enemy in world["enemies"] if enemy["regionId"] == region_id}
        actual_entities = {asset.get("entityId") for asset in region_assets if asset.get("class") != "background"}
        require(actual_entities == expected_entities, f"{region_id}: entity set drift")

    for asset in assets:
        identifier = asset.get("id")
        require(isinstance(identifier, str) and identifier, f"issue {issue}: asset id is required")
        region_id = asset.get("regionId")
        require(region_id in expected_regions, f"{identifier}: region ownership drift")
        require(asset.get("status") == "production_ready", f"{identifier}: asset is not production_ready")
        require(asset.get("scalePolicy") == "integer_nearest", f"{identifier}: integer nearest scaling required")
        verified = asset.get("verified", {})
        require(verified.get("binaryAlpha") is True, f"{identifier}: binary alpha evidence missing")
        require(verified.get("strictPalette") is True, f"{identifier}: strict palette evidence missing")
        require(verified.get("greenFringePixels") == 0, f"{identifier}: green fringe evidence failed")
        require(asset.get("paletteFile") == next(region["paletteFile"] for region in region_contracts if region["id"] == region_id), f"{identifier}: palette file drift")

        artifacts = asset.get("imagegenCallArtifacts")
        require(isinstance(artifacts, list) and artifacts, f"{identifier}: ImageGen artifact evidence missing")
        for artifact in artifacts:
            require(isinstance(artifact, str) and artifact.startswith("exec-") and artifact.endswith(".png"), f"{identifier}: invalid ImageGen artifact {artifact!r}")
            evidence.add_unique(evidence.artifacts, artifact, identifier)

        source_file = asset.get("sourceFile")
        source_hash = asset.get("sourceSha256")
        require(isinstance(source_file, str) and isinstance(source_hash, str), f"{identifier}: source file/hash evidence missing")
        source_path = safe_path(root, source_file, identifier)
        require(source_path.is_file() and sha256(source_path) == source_hash, f"{identifier}: source sha256 mismatch")
        evidence.add_unique(evidence.source_hashes, source_hash, identifier)

        output_hash = asset.get("sha256")
        require(isinstance(output_hash, str), f"{identifier}: output sha256 missing")
        evidence.add_unique(evidence.output_hashes, output_hash, identifier)
        if asset.get("transparentFile") is not None:
            transparent_path = safe_path(root, asset["transparentFile"], identifier)
            transparent_hash = asset.get("transparentSha256")
            require(isinstance(transparent_hash, str), f"{identifier}: transparent sha256 missing")
            require(transparent_path.is_file() and sha256(transparent_path) == transparent_hash, f"{identifier}: transparent sha256 mismatch")
            evidence.add_unique(evidence.transparent_hashes, transparent_hash, identifier)

        if asset.get("class") == "background":
            require(asset.get("kind") == "background", f"{identifier}: background kind mismatch")
            require(asset.get("canvas") == [360, 572] and asset.get("pivot") == [0, 572], f"{identifier}: background canvas/pivot mismatch")
        else:
            entity_id = asset.get("entityId")
            require(entity_id in canonical_enemies, f"{identifier}: unknown entityId {entity_id!r}")
            canonical = canonical_enemies[entity_id]
            require(canonical["regionId"] == region_id, f"{identifier}: entity belongs to another region")
            for field_name in EXACT_ENTITY_FIELDS:
                require(asset.get(field_name) == canonical.get(field_name), f"{identifier}: {field_name} drift")

        validate_png_asset(root, asset, palette_by_region[region_id][1])

    return ValidatedPack(issue=issue, regions=expected_regions, fragment=fragment, path=path)


def _load_palette_at(path: Path) -> set[tuple[int, int, int]]:
    colors: set[tuple[int, int, int]] = set()
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        fields = raw_line.strip().split()
        if len(fields) >= 3 and all(field.isdigit() for field in fields[:3]):
            colors.add(tuple(int(field) for field in fields[:3]))
    require(colors, f"{path}: palette has no colors")
    return colors


def build_integration(
    root: Path,
    world: dict[str, Any],
    manifest: dict[str, Any],
    packs: Iterable[ValidatedPack],
) -> tuple[dict[str, Any], dict[str, Any], dict[str, Any], list[tuple[Path, Path]]]:
    pack_list = list(packs)
    require({pack.issue for pack in pack_list} == set(PACK_REGIONS), "promotion requires complete issue #44 and #45 packs")
    updated_world = copy.deepcopy(world)
    updated_manifest = copy.deepcopy(manifest)
    enemy_by_id = {enemy["id"]: enemy for enemy in updated_world["enemies"]}
    region_by_id = {region["id"]: region for region in updated_world["regions"]}
    existing_asset_ids = {asset["id"] for asset in updated_manifest["assets"]}
    promotions: dict[str, Any] = {"schemaVersion": 1, "productionStageEnd": 360, "regions": {}, "enemies": {}}
    copy_plan: list[tuple[Path, Path]] = []

    for pack in sorted(pack_list, key=lambda item: item.issue):
        region_contracts = {region["id"]: region for region in pack.fragment["regions"]}
        for region_id, region in region_contracts.items():
            palette_file = region["paletteFile"]
            palette_id = Path(palette_file).stem
            previous = updated_manifest["paletteFiles"].get(palette_id)
            require(previous in {None, palette_file}, f"{palette_id}: common palette id collision")
            updated_manifest["paletteFiles"][palette_id] = palette_file

        for asset in pack.fragment["assets"]:
            identifier = asset["id"]
            require(identifier not in existing_asset_ids, f"{identifier}: common asset id collision")
            existing_asset_ids.add(identifier)
            destination_relative = Path("art-export/production/sprites") / f"{identifier}.png"
            source_path = safe_path(root, asset["file"], identifier)
            destination_path = root / destination_relative
            copy_plan.append((source_path, destination_path))
            palette_id = Path(asset["paletteFile"]).stem
            updated_manifest["assets"].append({
                "id": identifier,
                "kind": asset["kind"],
                "canvas": asset["canvas"],
                "pivot": asset["pivot"],
                "scalePolicy": "integer_nearest",
                "status": "production_ready",
                "paletteId": palette_id,
                "file": destination_relative.as_posix(),
                "sha256": asset["sha256"],
            })
            if asset["class"] == "background":
                region_id = asset["regionId"]
                region_by_id[region_id]["backgroundSpriteId"] = identifier
                promotions["regions"][region_id] = {"backgroundSpriteId": identifier}
            else:
                entity_id = asset["entityId"]
                enemy_by_id[entity_id]["spriteId"] = identifier
                enemy_by_id[entity_id]["assetStatus"] = "production_ready"
                promotions["enemies"][entity_id] = {
                    "spriteId": identifier,
                    "assetStatus": "production_ready",
                }

    updated_world["slice"]["productionStageEnd"] = 360
    require(all(enemy.get("assetStatus") == "production_ready" and enemy.get("spriteId") for enemy in updated_world["enemies"]), "promotion left unfinished enemies")
    require(all(region.get("backgroundSpriteId") for region in updated_world["regions"]), "promotion left unfinished backgrounds")
    return updated_world, updated_manifest, promotions, copy_plan


def write_json_atomic(path: Path, value: dict[str, Any]) -> None:
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    temporary.replace(path)


def apply_integration(
    root: Path,
    world_path: Path,
    manifest_path: Path,
    packs: Iterable[ValidatedPack],
) -> None:
    world = load_json(world_path)
    manifest = load_json(manifest_path)
    updated_world, updated_manifest, promotions, copy_plan = build_integration(root, world, manifest, packs)
    for source, destination in copy_plan:
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, destination)
    write_json_atomic(root / PROMOTIONS_PATH, promotions)
    write_json_atomic(world_path, updated_world)
    write_json_atomic(manifest_path, updated_manifest)


def current_pack_config(branch: str) -> tuple[Path, Path, tuple[str, ...]]:
    require(branch in BRANCH_PACKS, f"branch {branch!r} is not a registered pixel-pack branch")
    return BRANCH_PACKS[branch]


def build_current_pack(root: Path) -> Path:
    try:
        branch = subprocess.check_output(
            ["git", "branch", "--show-current"],
            cwd=root,
            text=True,
        ).strip()
    except subprocess.CalledProcessError as error:
        raise IntegrationError("cannot resolve current pixel-pack branch") from error
    builder, fragment, builder_arguments = current_pack_config(branch)
    builder_path = root / builder
    require(builder_path.is_file(), f"{branch}: builder is missing: {builder}")
    try:
        subprocess.run([sys.executable, str(builder_path), *builder_arguments], cwd=root, check=True)
    except subprocess.CalledProcessError as error:
        raise IntegrationError(f"{branch}: pixel-pack builder failed") from error
    require((root / fragment).is_file(), f"{branch}: builder did not emit {fragment}")
    return fragment


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--fragment", action="append", type=Path, default=[], help="fragment path relative to the repository")
    parser.add_argument("--check-contracts", action="store_true", help="validate the canonical R3-R6 world contract without writing")
    parser.add_argument("--build-current-pack", action="store_true", help="run the registered branch builder and exact-match its fragment")
    parser.add_argument("--apply", action="store_true", help="copy assets and promote the common manifest/world after all checks")
    return parser.parse_args()


def main() -> int:
    arguments = parse_arguments()
    world_path = ROOT / WORLD_PATH
    manifest_path = ROOT / MANIFEST_PATH
    world = load_json(world_path)
    summary = check_world_contracts(world)
    if arguments.build_current_pack:
        arguments.fragment.append(build_current_pack(ROOT))
    if arguments.check_contracts and not arguments.fragment and not arguments.apply:
        print(summary + f"; productionStageEnd={world['slice']['productionStageEnd']}; no files changed")
        return 0

    fragment_paths = arguments.fragment
    if arguments.apply and not fragment_paths:
        fragment_paths = list(DEFAULT_FRAGMENTS.values())
    require(fragment_paths, "provide --fragment or use --check-contracts")
    evidence = EvidenceRegistry()
    world_hash = canonical_world_hash(world_path)
    packs = [
        validate_fragment(ROOT, ROOT / path if not path.is_absolute() else path, world, world_hash, evidence)
        for path in fragment_paths
    ]
    require(len({pack.issue for pack in packs}) == len(packs), "duplicate issue fragment")
    if arguments.apply:
        apply_integration(ROOT, world_path, manifest_path, packs)
        print("pixel packs promoted: issues 44+45 / productionStageEnd=360")
    else:
        print(f"pixel pack fragments validated: {sorted(pack.issue for pack in packs)}; no files changed")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except IntegrationError as error:
        print(f"pixel pack integration failed: {error}", file=sys.stderr)
        raise SystemExit(1)
