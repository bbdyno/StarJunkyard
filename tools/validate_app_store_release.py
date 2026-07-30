#!/usr/bin/env python3
"""Validate repository-owned App Store release contracts without external access."""

from __future__ import annotations

import hashlib
import json
import plistlib
import re
import statistics
import struct
import sys
import zlib
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
RELEASE_DIR = ROOT / "release" / "app-store"


class ReleaseContractError(ValueError):
    pass


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ReleaseContractError(message)


def load_json(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise ReleaseContractError(f"cannot load {path.relative_to(ROOT)}: {error}") from error
    require(isinstance(value, dict), f"{path.relative_to(ROOT)} must contain an object")
    return value


def safe_repo_path(value: str, label: str) -> Path:
    relative = Path(value)
    require(not relative.is_absolute() and ".." not in relative.parts, f"{label}: unsafe path {value!r}")
    return ROOT / relative


def png_header(path: Path) -> tuple[int, int, int, bool, bool]:
    data = path.read_bytes()
    require(data.startswith(b"\x89PNG\r\n\x1a\n"), f"{path.relative_to(ROOT)} is not a PNG")
    require(data[12:16] == b"IHDR", f"{path.relative_to(ROOT)} has no leading IHDR")
    width, height, bit_depth, color_type, _, _, _ = struct.unpack(">IIBBBBB", data[16:29])
    offset = 8
    chunk_types: set[bytes] = set()
    while offset < len(data):
        length = struct.unpack(">I", data[offset : offset + 4])[0]
        chunk_type = data[offset + 4 : offset + 8]
        chunk_types.add(chunk_type)
        offset += length + 12
        if chunk_type == b"IEND":
            break
    has_transparency_chunk = b"tRNS" in chunk_types
    require(bit_depth == 8, f"{path.relative_to(ROOT)} must use 8-bit channels")
    has_srgb_profile = b"sRGB" in chunk_types or {b"gAMA", b"cHRM"} <= chunk_types
    return width, height, color_type, has_transparency_chunk, has_srgb_profile


def _paeth(left: int, up: int, upper_left: int) -> int:
    prediction = left + up - upper_left
    distances = (abs(prediction - left), abs(prediction - up), abs(prediction - upper_left))
    return (left, up, upper_left)[distances.index(min(distances))]


def read_rgb_png(path: Path) -> tuple[int, int, list[bytearray]]:
    """Decode the generated non-interlaced RGB icon for 64px readability checks."""

    data = path.read_bytes()
    offset = 8
    width = height = bit_depth = color_type = interlace = -1
    compressed = bytearray()
    while offset < len(data):
        length = struct.unpack(">I", data[offset : offset + 4])[0]
        chunk_type = data[offset + 4 : offset + 8]
        chunk_data = data[offset + 8 : offset + 8 + length]
        if chunk_type == b"IHDR":
            width, height, bit_depth, color_type, _, _, interlace = struct.unpack(">IIBBBBB", chunk_data)
        elif chunk_type == b"IDAT":
            compressed.extend(chunk_data)
        offset += length + 12
        if chunk_type == b"IEND":
            break
    require(bit_depth == 8 and color_type == 2 and interlace == 0,
            f"{path.relative_to(ROOT)} readability decoder requires non-interlaced 8-bit RGB")
    stride = width * 3
    raw = zlib.decompress(compressed)
    require(len(raw) == height * (stride + 1), f"{path.relative_to(ROOT)} has an unexpected data size")
    rows: list[bytearray] = []
    previous = bytearray(stride)
    cursor = 0
    for _ in range(height):
        filter_type = raw[cursor]
        cursor += 1
        encoded = raw[cursor : cursor + stride]
        cursor += stride
        require(filter_type <= 4, f"{path.relative_to(ROOT)} uses an unsupported PNG filter")
        decoded = bytearray(stride)
        for index, value in enumerate(encoded):
            left = decoded[index - 3] if index >= 3 else 0
            up = previous[index]
            upper_left = previous[index - 3] if index >= 3 else 0
            predictor = (0, left, up, (left + up) // 2, _paeth(left, up, upper_left))[filter_type]
            decoded[index] = (value + predictor) & 0xFF
        rows.append(decoded)
        previous = decoded
    return width, height, rows


def validate_small_icon_readability(path: Path) -> dict[str, float | int]:
    """Assert that star highlight and Mo's warm silhouette survive a 64px block reduction."""

    width, height, rows = read_rgb_png(path)
    require(width % 64 == 0 and height % 64 == 0, "app icon must reduce cleanly to a 64px review grid")
    block_width, block_height = width // 64, height // 64
    logical: list[tuple[int, int, int]] = []
    for logical_y in range(64):
        for logical_x in range(64):
            red = green = blue = 0
            for y in range(logical_y * block_height, (logical_y + 1) * block_height):
                row = rows[y]
                for x in range(logical_x * block_width, (logical_x + 1) * block_width):
                    index = x * 3
                    red += row[index]
                    green += row[index + 1]
                    blue += row[index + 2]
            area = block_width * block_height
            logical.append((red // area, green // area, blue // area))

    luminance = [(2126 * red + 7152 * green + 722 * blue) // 10_000 for red, green, blue in logical]
    central_bright = sum(
        luminance[y * 64 + x] >= 180
        for y in range(16, 49)
        for x in range(20, 56)
    )
    warm_character = 0
    for y in range(8, 50):
        for x in range(2, 34):
            red, green, blue = logical[y * 64 + x]
            pixel_luminance = luminance[y * 64 + x]
            if red > green * 1.25 and red > blue * 1.5 and pixel_luminance >= 30:
                warm_character += 1
    strong_edges = 0
    for y in range(64):
        for x in range(64):
            value = luminance[y * 64 + x]
            if x < 63 and abs(value - luminance[y * 64 + x + 1]) >= 45:
                strong_edges += 1
            if y < 63 and abs(value - luminance[(y + 1) * 64 + x]) >= 45:
                strong_edges += 1
    contrast = statistics.pstdev(luminance)
    require(central_bright >= 40, "64px icon loses the bright central star-core landmark")
    require(warm_character >= 250, "64px icon loses Mo's warm character silhouette")
    require(strong_edges >= 400 and contrast >= 35, "64px icon lacks a readable game-art silhouette")
    return {
        "centralBrightBlocks": central_bright,
        "warmCharacterBlocks": warm_character,
        "strongEdges": strong_edges,
        "luminanceContrast": contrast,
    }


def validate_blockers() -> set[str]:
    document = load_json(RELEASE_DIR / "submission-blockers.json")
    require(document.get("schemaVersion") == 1, "submission blocker schema mismatch")
    require(document.get("releaseState") == "repository_ready_external_blockers", "invalid release state")
    blockers = document.get("blockers", [])
    require(isinstance(blockers, list) and blockers, "external blockers must not be empty")
    identifiers = [item.get("id") for item in blockers]
    require(all(isinstance(identifier, str) and identifier.startswith("ASC-") for identifier in identifiers),
            "external blocker ids must use ASC- prefix")
    require(len(identifiers) == len(set(identifiers)), "external blocker ids must be unique")
    for item in blockers:
        require(item.get("state") == "external_required", f"{item.get('id')}: blocker state must be external_required")
        require(bool(item.get("owner")) and bool(item.get("resolution")), f"{item.get('id')}: owner and resolution required")
    return set(identifiers)


def validate_metadata(blocker_ids: set[str]) -> tuple[str, int]:
    metadata = load_json(RELEASE_DIR / "metadata.json")
    require(metadata.get("schemaVersion") == 1, "metadata schema mismatch")
    require(metadata.get("status") == "repository_ready_external_blockers", "metadata status mismatch")
    bundle_identifier = metadata.get("bundleIdentifier")
    require(bundle_identifier == "com.bbdyno.starjunkyard", "unexpected App Store bundle identifier")
    require(re.fullmatch(r"\d+\.\d+\.\d+", str(metadata.get("version", ""))) is not None,
            "version must use three numeric components")
    require(metadata.get("primaryLocale") in metadata.get("localizations", {}), "primary locale is missing")

    localizations = metadata.get("localizations", {})
    require(set(localizations) >= {"ko-KR", "en-US"}, "ko-KR and en-US metadata are required")
    for locale, values in localizations.items():
        require(isinstance(values, dict), f"{locale}: localization must be an object")
        name = values.get("name", "")
        subtitle = values.get("subtitle", "")
        promotional = values.get("promotionalText", "")
        description = values.get("description", "")
        keywords = values.get("keywords", "")
        notes = values.get("releaseNotes", "")
        require(2 <= len(name) <= 30, f"{locale}: name must contain 2-30 characters")
        require(len(subtitle) <= 30, f"{locale}: subtitle exceeds 30 characters")
        require(len(promotional) <= 170, f"{locale}: promotional text exceeds 170 characters")
        require(1 <= len(description) <= 4000, f"{locale}: description must contain 1-4000 characters")
        require(1 <= len(keywords.encode('utf-8')) <= 100, f"{locale}: keywords exceed 100 UTF-8 bytes")
        require(len(notes.encode("utf-8")) <= 4000, f"{locale}: release notes exceed 4000 bytes")
        require("<" not in description and ">" not in description, f"{locale}: description must be plain text")

    urls = metadata.get("urls", {})
    for key in ("privacyPolicy", "support"):
        field = urls.get(key, {})
        if field.get("value") is None:
            require(field.get("blocker") in blocker_ids, f"{key}: missing URL needs a valid external blocker")
        else:
            require(str(field["value"]).startswith("https://"), f"{key}: URL must use HTTPS")

    review = metadata.get("review", {})
    if review.get("contact") is None:
        require(review.get("blocker") in blocker_ids, "missing review contact needs a valid blocker")
    copyright_field = metadata.get("copyright", {})
    if copyright_field.get("value") is None:
        require(copyright_field.get("blocker") in blocker_ids, "missing copyright needs a valid blocker")

    declared_blockers = metadata.get("externalBlockerIds", [])
    require(set(declared_blockers) == blocker_ids, "metadata blocker list must match submission-blockers.json")
    return str(metadata["version"]), len(localizations)


def validate_project_configuration(version: str) -> None:
    project = (ROOT / "Project.swift").read_text(encoding="utf-8")
    required_fragments = (
        'bundleId: "com.bbdyno.starjunkyard"',
        '"TARGETED_DEVICE_FAMILY": "1,2"',
        f'"MARKETING_VERSION": "{version}"',
        '"ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon"',
        '"UIColorName": "LaunchBackground"',
        '"UIImageName": "LaunchEmblem"',
        '"LSApplicationCategoryType": "public.app-category.games"',
        '"ITSAppUsesNonExemptEncryption": false',
    )
    for fragment in required_fragments:
        require(fragment in project, f"Project.swift is missing {fragment}")
    match = re.search(r'"CURRENT_PROJECT_VERSION":\s*"(\d+)"', project)
    require(match is not None and int(match.group(1)) > 0, "CURRENT_PROJECT_VERSION must be a positive integer")


def validate_privacy_manifest(blocker_ids: set[str]) -> int:
    manifest_path = ROOT / "StarJunkyard" / "Resources" / "PrivacyInfo.xcprivacy"
    with manifest_path.open("rb") as stream:
        manifest = plistlib.load(stream)
    require(manifest.get("NSPrivacyTracking") is False, "privacy manifest must disable tracking")
    require(manifest.get("NSPrivacyTrackingDomains") == [], "tracking domains must be empty")
    require(manifest.get("NSPrivacyCollectedDataTypes") == [], "developer-collected data must be empty")
    accessed = manifest.get("NSPrivacyAccessedAPITypes", [])
    expected = {
        "NSPrivacyAccessedAPIType": "NSPrivacyAccessedAPICategoryUserDefaults",
        "NSPrivacyAccessedAPITypeReasons": ["CA92.1"],
    }
    require(expected in accessed, "UserDefaults CA92.1 required-reason declaration is missing")

    labels = load_json(RELEASE_DIR / "privacy-labels.json")
    require(labels.get("tracking") is False and labels.get("trackingDomains") == [], "privacy labels must disable tracking")
    require(labels.get("dataCollectedByDeveloper") == [], "privacy labels must declare no developer collection")
    require(labels.get("externalConfirmationBlocker") in blocker_ids, "privacy confirmation blocker is invalid")
    declared = {
        (item.get("category"), tuple(item.get("reasons", [])))
        for item in labels.get("requiredReasonAPIs", [])
    }
    require(("NSPrivacyAccessedAPICategoryUserDefaults", ("CA92.1",)) in declared,
            "privacy labels and manifest required reasons differ")
    return len(accessed)


def validate_visual_assets() -> tuple[int, dict[str, float | int]]:
    app_icon_contents = load_json(
        ROOT / "StarJunkyard" / "Resources" / "Assets.xcassets" / "AppIcon.appiconset" / "Contents.json"
    )
    icon_entries = app_icon_contents.get("images", [])
    require(any(item.get("filename") == "AppIcon-1024.png" and item.get("size") == "1024x1024"
                and item.get("platform") == "ios" for item in icon_entries),
            "asset catalog must declare the universal 1024x1024 iOS icon")

    visual = load_json(RELEASE_DIR / "visual-assets.json")
    require(visual.get("schemaVersion") == 1, "visual asset schema mismatch")
    require(len(visual.get("sourceReferences", [])) >= 3, "visual assets need recognizable game references")
    assets = visual.get("assets", [])
    require(len(assets) >= 4, "app icon and three launch scales are required")
    for asset in assets:
        path = safe_repo_path(str(asset.get("path", "")), "visual asset")
        require(path.is_file(), f"missing visual asset {path.relative_to(ROOT)}")
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        require(digest == asset.get("sha256"), f"{path.relative_to(ROOT)} sha256 mismatch")
        width, height, color_type, has_transparency_chunk, has_srgb_chunk = png_header(path)
        require([width, height] == [asset.get("width"), asset.get("height")],
                f"{path.relative_to(ROOT)} dimensions differ from manifest")
        if asset.get("opaque"):
            require(color_type in (0, 2, 3) and not has_transparency_chunk,
                    f"{path.relative_to(ROOT)} must not contain alpha or transparency")
        require(asset.get("colorSpace") == "sRGB", f"{path.relative_to(ROOT)} must declare sRGB")
        require(has_srgb_chunk, f"{path.relative_to(ROOT)} must embed the sRGB color space")

    icon_path = ROOT / "StarJunkyard" / "Resources" / "Assets.xcassets" / "AppIcon.appiconset" / "AppIcon-1024.png"
    readability = validate_small_icon_readability(icon_path)

    checklist = (RELEASE_DIR / "RELEASE_CHECKLIST.md").read_text(encoding="utf-8")
    require("모·리벳·별 코어" in checklist, "visual review must name recognizable game subjects")
    prompt_summary = visual.get("promptSummary", "")
    require(all(subject in prompt_summary for subject in ("Mo", "Rivet", "star core")),
            "visual prompt must name Mo, Rivet, and the star core")
    return len(assets), readability


def _storekit_products(configuration: dict[str, Any]) -> dict[str, str]:
    products: list[dict[str, Any]] = list(configuration.get("products", []))
    products.extend(configuration.get("nonRenewingSubscriptions", []))
    for group in configuration.get("subscriptionGroups", []):
        products.extend(group.get("subscriptions", []))
    result: dict[str, str] = {}
    for product in products:
        identifier = product.get("productID")
        require(isinstance(identifier, str) and identifier, "StoreKit product is missing productID")
        require(identifier not in result, f"duplicate StoreKit product {identifier}")
        result[identifier] = str(product.get("type"))
    return result


def validate_storekit(blocker_ids: set[str]) -> tuple[int, str]:
    contract = load_json(RELEASE_DIR / "storekit-release-contract.json")
    require(contract.get("schemaVersion") == 1, "StoreKit release contract schema mismatch")
    require(contract.get("externalBlocker") in blocker_ids, "StoreKit external blocker is invalid")
    catalog_path = safe_repo_path(str(contract.get("catalogPath", "")), "IAP catalog")
    configuration_path = safe_repo_path(str(contract.get("configurationPath", "")), "StoreKit configuration")
    source_root = safe_repo_path(str(contract.get("runtimeSourceRoot", "")), "StoreKit source root")
    catalog = load_json(catalog_path)
    products = catalog.get("products", [])
    identifiers = [item.get("id") for item in products]
    require(identifiers and len(identifiers) == len(set(identifiers)), "IAP catalog ids must be non-empty and unique")

    sources = "\n".join(path.read_text(encoding="utf-8") for path in source_root.rglob("*.swift"))
    runtime_active = any(marker in sources for marker in contract.get("runtimeMarkers", []))
    if runtime_active and contract.get("configurationRequiredWhenRuntimeMarkerExists"):
        require(configuration_path.is_file(), "StoreKit runtime is active but its configuration is missing")
    if not configuration_path.is_file():
        return len(products), "catalog-only"

    configuration = load_json(configuration_path)
    configured = _storekit_products(configuration)
    expected_type = {
        "consumable": "Consumable",
        "non_consumable": "NonConsumable",
        "non_renewing_subscription": "NonRenewingSubscription",
        "auto_renewable_subscription": "RecurringSubscription",
    }
    catalog_types: dict[str, str] = {}
    for product in products:
        require(product.get("type") in expected_type, f"unsupported catalog type {product.get('type')}")
        catalog_types[str(product["id"])] = expected_type[str(product["type"])]
    require(configured == catalog_types, "StoreKit product ids/types must exactly match the current IAP catalog")
    project = (ROOT / "Project.swift").read_text(encoding="utf-8")
    require("storeKitConfigurationPath" in project and str(contract["configurationPath"]) in project,
            "Project.swift scheme must reference the StoreKit configuration")
    return len(products), "configured"


def validate_screenshot_contract(blocker_ids: set[str]) -> int:
    contract = load_json(RELEASE_DIR / "screenshots.json")
    require(contract.get("externalBlocker") in blocker_ids, "screenshot blocker is invalid")
    require(contract.get("opaque") is True, "App Store screenshots must be opaque")
    require(contract.get("minimumPerRequiredDisplay") == 1, "at least one screenshot is required")
    require(contract.get("maximumPerDisplay") == 10, "screenshot maximum must be ten")
    displays = {item.get("id"): item for item in contract.get("requiredDisplays", [])}
    require({"iphone-6.9-portrait", "ipad-13-portrait"} <= set(displays),
            "iPhone 6.9-inch and iPad 13-inch contracts are required")
    require([1260, 2736] in displays["iphone-6.9-portrait"].get("acceptedPixelSizes", []),
            "iPhone 6.9-inch portrait size is missing")
    require([2064, 2752] in displays["ipad-13-portrait"].get("acceptedPixelSizes", []),
            "iPad 13-inch portrait size is missing")
    return len(displays)


def validate_export_template() -> None:
    with (RELEASE_DIR / "ExportOptions.template.plist").open("rb") as stream:
        options = plistlib.load(stream)
    require(options.get("method") == "app-store-connect", "export method must be app-store-connect")
    require(options.get("destination") == "export", "template must export locally and never upload")
    require("teamID" not in options, "repository template must not hardcode an external team ID")


def validate_release() -> list[str]:
    blocker_ids = validate_blockers()
    version, localization_count = validate_metadata(blocker_ids)
    validate_project_configuration(version)
    privacy_api_count = validate_privacy_manifest(blocker_ids)
    visual_count, icon_readability = validate_visual_assets()
    product_count, storekit_state = validate_storekit(blocker_ids)
    display_count = validate_screenshot_contract(blocker_ids)
    validate_export_template()
    return [
        f"version {version}",
        f"{localization_count} localizations",
        f"{visual_count} opaque visual assets",
        f"64px icon star={icon_readability['centralBrightBlocks']} Mo={icon_readability['warmCharacterBlocks']} edges={icon_readability['strongEdges']}",
        f"{privacy_api_count} required-reason API declarations",
        f"{product_count} catalog-driven IAP products ({storekit_state})",
        f"{display_count} required screenshot displays",
        f"{len(blocker_ids)} explicit external blockers",
    ]


def main() -> int:
    try:
        summary = validate_release()
    except (ReleaseContractError, KeyError, OSError, plistlib.InvalidFileException, TypeError) as error:
        print(f"App Store release validation failed: {error}", file=sys.stderr)
        return 1
    print("App Store release validation passed: " + ", ".join(summary))
    print("External App Store Connect actions remain blocked; see release/app-store/submission-blockers.json")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
