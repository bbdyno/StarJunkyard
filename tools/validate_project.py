#!/usr/bin/env python3
"""Validate shared StarJunkyard contracts without third-party packages."""

from __future__ import annotations

import argparse
import hashlib
import json
import struct
import sys
import zlib
from decimal import Decimal, ROUND_HALF_UP, getcontext
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
COMMON_DIRS = ("content", "schemas", "golden", "art-source", "art-export", "tools")
RUNTIME_SUFFIXES = {".swift", ".kt", ".kts", ".java", ".m", ".mm", ".cpp", ".c"}


class ContractError(ValueError):
    pass


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ContractError(message)


def load_json(relative_path: str | Path) -> dict[str, Any]:
    path = ROOT / relative_path
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise ContractError(f"cannot load JSON {relative_path}: {error}") from error
    require(isinstance(value, dict), f"{relative_path} must contain a JSON object")
    return value


def canonical_digest(value: Any) -> str:
    payload = json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()


def load_palette(relative_path: str | Path) -> set[tuple[int, int, int]]:
    colors: set[tuple[int, int, int]] = set()
    for line in (ROOT / relative_path).read_text(encoding="utf-8").splitlines():
        fields = line.strip().split()
        if len(fields) >= 3 and all(field.isdigit() for field in fields[:3]):
            color = tuple(int(field) for field in fields[:3])
            require(all(0 <= channel <= 255 for channel in color), f"invalid palette color: {line}")
            colors.add(color)
    require(len(colors) == 16, f"common palette must have exactly 16 colors, found {len(colors)}")
    return colors


def _paeth(left: int, up: int, upper_left: int) -> int:
    prediction = left + up - upper_left
    distances = (abs(prediction - left), abs(prediction - up), abs(prediction - upper_left))
    return (left, up, upper_left)[distances.index(min(distances))]


def read_png_pixels(path: Path) -> tuple[int, int, set[tuple[int, int, int]], bool]:
    """Decode non-interlaced 8-bit RGB/RGBA/indexed PNGs for palette validation."""

    data = path.read_bytes()
    require(data.startswith(b"\x89PNG\r\n\x1a\n"), f"{path} is not a PNG")
    offset = 8
    width = height = bit_depth = color_type = interlace = -1
    palette: list[tuple[int, int, int]] = []
    transparency = b""
    compressed = bytearray()

    while offset < len(data):
        require(offset + 12 <= len(data), f"truncated PNG chunk in {path}")
        length = struct.unpack(">I", data[offset : offset + 4])[0]
        chunk_type = data[offset + 4 : offset + 8]
        chunk_data = data[offset + 8 : offset + 8 + length]
        require(offset + 12 + length <= len(data), f"truncated PNG payload in {path}")
        if chunk_type == b"IHDR":
            width, height, bit_depth, color_type, _, _, interlace = struct.unpack(">IIBBBBB", chunk_data)
        elif chunk_type == b"PLTE":
            require(len(chunk_data) % 3 == 0, f"invalid PLTE in {path}")
            palette = [tuple(chunk_data[index : index + 3]) for index in range(0, len(chunk_data), 3)]
        elif chunk_type == b"tRNS":
            transparency = bytes(chunk_data)
        elif chunk_type == b"IDAT":
            compressed.extend(chunk_data)
        elif chunk_type == b"IEND":
            break
        offset += length + 12

    require(width > 0 and height > 0, f"missing IHDR in {path}")
    require(bit_depth == 8, f"{path} must use 8-bit channels")
    require(interlace == 0, f"{path} must be non-interlaced")
    require(color_type in (2, 3, 6), f"{path} must be RGB, indexed, or RGBA")
    channels = {2: 3, 3: 1, 6: 4}[color_type]
    row_size = width * channels
    raw = zlib.decompress(bytes(compressed))
    require(len(raw) == height * (row_size + 1), f"unexpected decompressed size in {path}")

    previous = bytearray(row_size)
    rows: list[bytearray] = []
    cursor = 0
    for _ in range(height):
        filter_type = raw[cursor]
        cursor += 1
        encoded = raw[cursor : cursor + row_size]
        cursor += row_size
        require(filter_type <= 4, f"unsupported PNG filter {filter_type} in {path}")
        decoded = bytearray(row_size)
        for index, value in enumerate(encoded):
            left = decoded[index - channels] if index >= channels else 0
            up = previous[index]
            upper_left = previous[index - channels] if index >= channels else 0
            predictor = (0, left, up, (left + up) // 2, _paeth(left, up, upper_left))[filter_type]
            decoded[index] = (value + predictor) & 0xFF
        rows.append(decoded)
        previous = decoded

    colors: set[tuple[int, int, int]] = set()
    has_partial_alpha = False
    for row in rows:
        for index in range(0, len(row), channels):
            if color_type == 2:
                red, green, blue = row[index : index + 3]
                alpha = 255
            elif color_type == 6:
                red, green, blue, alpha = row[index : index + 4]
            else:
                palette_index = row[index]
                require(palette_index < len(palette), f"palette index out of range in {path}")
                red, green, blue = palette[palette_index]
                alpha = transparency[palette_index] if palette_index < len(transparency) else 255
            has_partial_alpha |= alpha not in (0, 255)
            if alpha != 0:
                colors.add((red, green, blue))
    return width, height, colors, has_partial_alpha


def validate_schema_documents() -> None:
    identifiers: set[str] = set()
    for path in sorted((ROOT / "schemas").glob("*.schema.json")):
        schema = load_json(path.relative_to(ROOT))
        require(schema.get("$schema") == "https://json-schema.org/draft/2020-12/schema", f"{path.name}: unsupported draft")
        identifier = schema.get("$id")
        require(isinstance(identifier, str) and identifier, f"{path.name}: missing $id")
        require(identifier not in identifiers, f"duplicate schema $id: {identifier}")
        identifiers.add(identifier)
    require(len(identifiers) >= 3, "content, asset, and golden schemas are required")


def validate_content(content: dict[str, Any], manifest: dict[str, Any]) -> set[str]:
    require(content.get("schemaVersion") == manifest.get("schemaVersion") == 1, "schema version mismatch")
    require(content.get("contentVersion") == manifest.get("contentVersion"), "content version mismatch")
    slice_data = content["slice"]
    stages = content["stages"]
    expected_numbers = list(range(slice_data["stageStart"], slice_data["stageEnd"] + 1))
    actual_numbers = [stage["number"] for stage in stages]
    require(actual_numbers == expected_numbers, "stages must be unique, ordered, and contiguous")

    enemy_ids = [enemy["id"] for enemy in content["enemies"]]
    require(len(enemy_ids) == len(set(enemy_ids)), "enemy ids must be unique")
    enemy_by_id = {enemy["id"]: enemy for enemy in content["enemies"]}
    drone_ids = [drone["id"] for drone in content["drones"]]
    require(len(drone_ids) == len(set(drone_ids)), "drone ids must be unique")

    getcontext().prec = 50
    for stage in stages:
        number = stage["number"]
        expected_hp = int((Decimal(50) * Decimal("1.105") ** (number - 1)).quantize(Decimal(1), rounding=ROUND_HALF_UP))
        expected_reward = int((Decimal(10) * Decimal("1.095") ** (number - 1)).quantize(Decimal(1), rounding=ROUND_HALF_UP))
        require(stage["baseHp"] == expected_hp, f"stage {number}: baseHp must be precomputed as {expected_hp}")
        require(stage["baseReward"] == expected_reward, f"stage {number}: baseReward must be precomputed as {expected_reward}")
        require(all(enemy_id in enemy_by_id for enemy_id in stage["wave"]), f"stage {number}: unknown enemy id")
        if number % 10 == 0:
            require(len(stage["wave"]) == 1, f"stage {number}: boss stage must contain one enemy")
            require(enemy_by_id[stage["wave"][0]]["class"] == "boss", f"stage {number}: wave is not a boss")
            require(stage.get("timeLimitMs") == 45000, f"stage {number}: slice boss limit must be 45 seconds")
        else:
            require("bossTier" not in stage and "timeLimitMs" not in stage, f"stage {number}: non-boss has boss fields")
            expected_count = 7 if number % 5 == 0 else 8
            require(len(stage["wave"]) == expected_count, f"stage {number}: expected {expected_count} enemies")

    sprite_ids = {content["player"]["spriteId"]}
    sprite_ids.update(drone["spriteId"] for drone in content["drones"])
    sprite_ids.update(enemy["spriteId"] for enemy in content["enemies"])
    return sprite_ids


def validate_assets(asset_manifest: dict[str, Any], required_ids: set[str], palette: set[tuple[int, int, int]], release: bool) -> None:
    require(asset_manifest.get("logicalViewport") == [360, 800], "asset viewport must be 360x800 portrait")
    assets = asset_manifest.get("assets", [])
    asset_ids = [asset["id"] for asset in assets]
    require(len(asset_ids) == len(set(asset_ids)), "asset ids must be unique")
    require(required_ids <= set(asset_ids), f"missing asset ids: {sorted(required_ids - set(asset_ids))}")
    require("background_r01_back_alley" in asset_ids, "R1 combat background is missing")
    profiles = asset_manifest.get("animationProfiles", {})
    require(profiles.get("actor_mo_base", {}).get("attackFrames") == 4, "Mo needs four attack steps")
    require(profiles.get("drone_riv0_base", {}).get("hoverFrames") == 4, "Rivet needs four hover steps")
    require(profiles.get("enemy_normal", {}).get("hitFrames") == 3, "normal enemies need three hit steps")
    allowed_canvas: dict[str, set[tuple[int, int]]] = {
        "actor": {(48, 64)},
        "drone": {(32, 32), (48, 40)},
        "enemy_small": {(32, 32)},
        "enemy_medium": {(48, 48)},
        "enemy_large": {(64, 64)},
    }

    for asset in assets:
        identifier = asset["id"]
        canvas = tuple(asset["canvas"])
        pivot = tuple(asset["pivot"])
        require(asset["scalePolicy"] == "integer_nearest", f"{identifier}: nearest integer scaling required")
        require(all(isinstance(value, int) for value in (*canvas, *pivot)), f"{identifier}: canvas and pivot must be integer")
        require(0 <= pivot[0] <= canvas[0] and 0 <= pivot[1] <= canvas[1], f"{identifier}: pivot outside canvas")
        if asset["kind"] in allowed_canvas:
            require(canvas in allowed_canvas[asset["kind"]], f"{identifier}: invalid canvas {canvas}")
        if asset["kind"] == "boss":
            require(80 <= canvas[0] <= 288 and 80 <= canvas[1] <= 224, f"{identifier}: boss canvas outside budget")

        status = asset["status"]
        if release:
            require(status == "production_ready", f"{identifier}: {status} asset cannot enter a release build")
        if status == "production_ready":
            require("file" in asset and "sha256" in asset, f"{identifier}: production asset needs file and sha256")
            relative_file = Path(asset["file"])
            require(not relative_file.is_absolute() and ".." not in relative_file.parts, f"{identifier}: unsafe asset path")
            path = ROOT / relative_file
            require(path.is_file(), f"{identifier}: missing {relative_file}")
            require(hashlib.sha256(path.read_bytes()).hexdigest() == asset["sha256"], f"{identifier}: sha256 mismatch")
            width, height, colors, has_partial_alpha = read_png_pixels(path)
            require((width, height) == canvas, f"{identifier}: PNG canvas does not match manifest")
            require(not has_partial_alpha, f"{identifier}: anti-aliased partial alpha is forbidden")
            require(colors <= palette, f"{identifier}: colors outside common16: {sorted(colors - palette)}")


def validate_golden(manifest: dict[str, Any], content: dict[str, Any]) -> None:
    valid_stages = {stage["number"] for stage in content["stages"]}
    for relative_path in manifest["goldenFiles"]:
        fixture = load_json(relative_path)
        require(fixture.get("schemaVersion") == 1, f"{relative_path}: schema version mismatch")
        require(fixture.get("contentVersion") == manifest["contentVersion"], f"{relative_path}: content version mismatch")
        require(fixture["input"]["stage"] in valid_stages, f"{relative_path}: stage outside content")
        digest = canonical_digest(fixture["expectedState"])
        require(fixture.get("expectedDigest") == digest, f"{relative_path}: expected digest is {digest}")


def validate_no_shared_runtime() -> None:
    violations: list[str] = []
    for directory in COMMON_DIRS:
        for path in (ROOT / directory).rglob("*"):
            if path.is_file() and path.suffix in RUNTIME_SUFFIXES:
                violations.append(str(path.relative_to(ROOT)))
    require(not violations, f"shared runtime code is forbidden: {violations}")


def validate_project(release: bool = False) -> list[str]:
    manifest = load_json("content/manifest.json")
    require(manifest.get("logicalViewport") == {"width": 360, "height": 800, "orientation": "portrait"}, "manifest viewport mismatch")
    require(len(manifest.get("contentFiles", [])) == 1, "vertical slice must have one content entrypoint")
    content = load_json(manifest["contentFiles"][0])
    asset_manifest = load_json(manifest["assetManifest"])
    palette = load_palette(manifest["palette"])

    validate_schema_documents()
    required_ids = validate_content(content, manifest)
    validate_assets(asset_manifest, required_ids, palette, release)
    validate_golden(manifest, content)
    validate_no_shared_runtime()
    return [
        f"content {manifest['contentVersion']}",
        f"{len(content['stages'])} stages",
        f"{len(asset_manifest['assets'])} pixel assets ({'release' if release else 'development'} mode)",
        f"{len(manifest['goldenFiles'])} golden fixtures",
    ]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--release", action="store_true", help="reject planned and placeholder assets")
    args = parser.parse_args()
    try:
        summary = validate_project(release=args.release)
    except (ContractError, KeyError, TypeError) as error:
        print(f"validation failed: {error}", file=sys.stderr)
        return 1
    print("validation passed: " + ", ".join(summary))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
