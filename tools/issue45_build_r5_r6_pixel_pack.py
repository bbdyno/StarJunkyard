#!/usr/bin/env python3
"""Build and verify the isolated Issue #45 R5/R6 strict pixel pack.

Sprite inputs must first pass through ImageGen's official remove_chroma_key.py
helper using soft matte, despill, and edge-contract 1. Backgrounds remain opaque.
This script only writes Issue #45-owned exports, its fragment, and QA sheets.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Any

from PIL import Image, ImageDraw, ImageFont, ImageOps


ROOT = Path(__file__).resolve().parents[1]
FRAGMENT_PATH = ROOT / "art-export/issue-45-r5-r6/manifest-fragment.json"
CONTACT_SHEET_DIR = ROOT / "docs/screenshots"
EXPECTED_SOURCE_SHA = "f8922a8ce4d98d01f19477a38b7bb3291c52b20914576a4231067e635818338a"
EXPECTED_ELITES = {
    "r05": ("docking_golem", "dish_starfish"),
    "r06": ("time_compressor", "memory_incinerator_librarian"),
}
BACKGROUND = (18, 20, 28, 255)
PANEL = (28, 35, 51, 255)
WHITE = (242, 240, 233, 255)
MUTED = (184, 195, 209, 255)
ACCENT = (242, 193, 78, 255)
CHECKER_A = (52, 58, 72, 255)
CHECKER_B = (96, 104, 122, 255)


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def pixel_data(image: Image.Image) -> Any:
    """Use Pillow's current flat iterator with compatibility for older releases."""
    flattened = getattr(image, "get_flattened_data", None)
    return flattened() if flattened is not None else image.getdata()


def load_fragment() -> dict[str, Any]:
    return json.loads(FRAGMENT_PATH.read_text(encoding="utf-8"))


def load_palette(relative_path: str) -> list[tuple[int, int, int]]:
    colors: list[tuple[int, int, int]] = []
    path = ROOT / relative_path
    for line in path.read_text(encoding="utf-8").splitlines():
        fields = line.split()
        if len(fields) >= 3 and all(field.isdigit() for field in fields[:3]):
            colors.append(tuple(int(field) for field in fields[:3]))
    if len(colors) != 16 or len(set(colors)) != 16:
        raise ValueError(f"{relative_path}: strict palette needs 16 unique colors")
    return colors


def nearest_color(
    red: int,
    green: int,
    blue: int,
    palette: list[tuple[int, int, int]],
) -> tuple[int, int, int]:
    return min(
        palette,
        key=lambda color: (
            (red - color[0]) ** 2
            + (green - color[1]) ** 2
            + (blue - color[2]) ** 2
        ),
    )


def strict_quantize(
    image: Image.Image,
    palette: list[tuple[int, int, int]],
    *,
    transparent: bool,
) -> Image.Image:
    source = image.convert("RGBA")
    output = Image.new("RGBA", source.size)
    pixels = output.load()
    for y in range(source.height):
        for x in range(source.width):
            red, green, blue, alpha = source.getpixel((x, y))
            if transparent and alpha < 128:
                pixels[x, y] = (0, 0, 0, 0)
            else:
                pixels[x, y] = (*nearest_color(red, green, blue, palette), 255)
    return output


def inspect_transparent_intermediate(image: Image.Image) -> dict[str, int | bool]:
    rgba = image.convert("RGBA")
    alpha_values = list(pixel_data(rgba.getchannel("A")))
    if min(alpha_values) != 0 or max(alpha_values) != 255:
        raise ValueError("official helper output must include transparent and opaque pixels")
    corners = (
        rgba.getpixel((0, 0))[3],
        rgba.getpixel((rgba.width - 1, 0))[3],
        rgba.getpixel((0, rgba.height - 1))[3],
        rgba.getpixel((rgba.width - 1, rgba.height - 1))[3],
    )
    if any(corners):
        raise ValueError("transparent intermediate corners must be fully transparent")
    fringe = sum(
        1
        for red, green, blue, alpha in pixel_data(rgba)
        if alpha > 0 and green > 180 and green > red * 1.45 and green > blue * 1.35
    )
    if fringe:
        raise ValueError(f"transparent intermediate has {fringe} green fringe pixels")
    opaque = sum(alpha >= 128 for alpha in alpha_values)
    coverage = opaque / len(alpha_values)
    if not 0.02 <= coverage <= 0.90:
        raise ValueError(f"implausible transparent subject coverage: {coverage:.3f}")
    return {
        "officialChromaHelper": True,
        "transparentEdgePixels": sum(0 < alpha < 255 for alpha in alpha_values),
        "transparentCorners": True,
        "greenFringePixels": 0,
    }


def opaque_bbox(image: Image.Image) -> tuple[int, int, int, int]:
    binary_alpha = image.convert("RGBA").getchannel("A").point(
        lambda alpha: 255 if alpha >= 128 else 0
    )
    bounds = binary_alpha.getbbox()
    if bounds is None:
        raise ValueError("transparent intermediate contains no visible subject")
    return bounds


def build_sprite(
    source: Image.Image,
    canvas: tuple[int, int],
    palette: list[tuple[int, int, int]],
) -> Image.Image:
    cropped = source.convert("RGBA").crop(opaque_bbox(source))
    max_width, max_height = canvas[0] - 2, canvas[1] - 2
    ratio = min(max_width / cropped.width, max_height / cropped.height)
    target = (
        max(1, int(cropped.width * ratio)),
        max(1, int(cropped.height * ratio)),
    )
    fitted = cropped.resize(target, Image.Resampling.NEAREST)
    fitted = strict_quantize(fitted, palette, transparent=True)
    output = Image.new("RGBA", canvas)
    x = (canvas[0] - target[0]) // 2
    y = canvas[1] - target[1] - 1
    output.alpha_composite(fitted, (x, y))
    return output


def build_background(
    source: Image.Image,
    canvas: tuple[int, int],
    palette: list[tuple[int, int, int]],
) -> Image.Image:
    fitted = ImageOps.fit(
        source.convert("RGB"),
        canvas,
        method=Image.Resampling.NEAREST,
        centering=(0.5, 0.5),
    )
    return strict_quantize(fitted, palette, transparent=False)


def inspect_pixels(
    image: Image.Image,
    palette: set[tuple[int, int, int]],
    *,
    transparent: bool,
) -> dict[str, int | bool]:
    rgba = image.convert("RGBA")
    alphas = set(pixel_data(rgba.getchannel("A")))
    if not alphas <= {0, 255}:
        raise ValueError(f"partial alpha values remain: {sorted(alphas - {0, 255})[:8]}")
    colors = {
        (red, green, blue)
        for red, green, blue, alpha in pixel_data(rgba)
        if alpha == 255
    }
    outside = colors - palette
    if outside:
        raise ValueError(f"colors outside strict palette: {sorted(outside)}")
    corners = (
        rgba.getpixel((0, 0))[3],
        rgba.getpixel((rgba.width - 1, 0))[3],
        rgba.getpixel((0, rgba.height - 1))[3],
        rgba.getpixel((rgba.width - 1, rgba.height - 1))[3],
    )
    transparent_corners = all(alpha == 0 for alpha in corners)
    if transparent and not transparent_corners:
        raise ValueError("sprite corners must remain transparent")
    if not transparent and alphas != {255}:
        raise ValueError("background must be fully opaque")
    fringe = sum(
        1
        for red, green, blue, alpha in pixel_data(rgba)
        if alpha == 255 and green > 180 and green > red * 1.45 and green > blue * 1.35
    )
    if fringe:
        raise ValueError(f"detected {fringe} possible chroma fringe pixels")
    opaque = sum(alpha == 255 for alpha in pixel_data(rgba.getchannel("A")))
    coverage = opaque / (rgba.width * rgba.height)
    if transparent and not 0.04 <= coverage <= 0.88:
        raise ValueError(f"implausible sprite coverage: {coverage:.3f}")
    return {
        "binaryAlpha": True,
        "transparentCorners": transparent_corners,
        "strictPalette": True,
        "greenFringePixels": 0,
    }


def build_asset(asset: dict[str, Any]) -> None:
    source_path = ROOT / asset["sourceFile"]
    if not source_path.is_file():
        raise FileNotFoundError(source_path)
    palette = load_palette(asset["paletteFile"])
    canvas = tuple(asset["canvas"])
    is_background = asset["class"] == "background"
    edge_inspection: dict[str, int | bool]
    if is_background:
        intermediate_path = source_path
        edge_inspection = {
            "officialChromaHelper": False,
            "transparentEdgePixels": 0,
            "transparentCorners": False,
            "greenFringePixels": 0,
        }
        built = build_background(Image.open(source_path), canvas, palette)
    else:
        intermediate_path = ROOT / asset["transparentFile"]
        if not intermediate_path.is_file():
            raise FileNotFoundError(
                f"{intermediate_path} missing; run the official chroma helper first"
            )
        intermediate = Image.open(intermediate_path)
        edge_inspection = inspect_transparent_intermediate(intermediate)
        built = build_sprite(intermediate, canvas, palette)

    output_path = ROOT / asset["file"]
    output_path.parent.mkdir(parents=True, exist_ok=True)
    built.save(output_path, optimize=False)
    strict_inspection = inspect_pixels(
        built,
        set(palette),
        transparent=not is_background,
    )
    asset.update(
        {
            "status": "production_ready",
            "sourceSha256": sha256(source_path),
            "sha256": sha256(output_path),
            "verified": {**edge_inspection, **strict_inspection},
        }
    )
    if not is_background:
        asset["transparentSha256"] = sha256(intermediate_path)


def font(size: int) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    paths = (
        Path("/System/Library/Fonts/AppleSDGothicNeo.ttc"),
        Path("/System/Library/Fonts/Supplemental/Arial.ttf"),
    )
    for path in paths:
        if path.is_file():
            return ImageFont.truetype(str(path), size=size)
    return ImageFont.load_default()


def checkerboard(size: tuple[int, int], tile: int = 8) -> Image.Image:
    board = Image.new("RGBA", size, CHECKER_A)
    draw = ImageDraw.Draw(board)
    for y in range(0, size[1], tile):
        for x in range(0, size[0], tile):
            if (x // tile + y // tile) % 2:
                draw.rectangle((x, y, x + tile - 1, y + tile - 1), fill=CHECKER_B)
    return board


def build_contact_sheet(fragment: dict[str, Any], region_id: str) -> Path:
    assets = [asset for asset in fragment["assets"] if asset["regionId"] == region_id]
    if len(assets) != 9 or any(asset["status"] != "production_ready" for asset in assets):
        raise ValueError(f"{region_id}: contact sheet requires all nine verified assets")
    region = next(item for item in fragment["regions"] if item["id"] == region_id)
    sheet = Image.new("RGBA", (1560, 900), BACKGROUND)
    draw = ImageDraw.Draw(sheet)
    draw.text((32, 22), f"{region_id.upper()} · {region['nameKo']} · ISSUE #45 STRICT PIXEL QA", font=font(28), fill=WHITE)
    draw.text((32, 60), "checkerboard = transparency · 4× nearest preview · names / behavior / weakness", font=font(17), fill=MUTED)

    for index, asset in enumerate(assets):
        column, row = index % 3, index // 3
        x, y = 28 + column * 506, 104 + row * 255
        draw.rounded_rectangle((x, y, x + 480, y + 228), radius=5, fill=PANEL, outline=MUTED, width=1)
        image = Image.open(ROOT / asset["file"]).convert("RGBA")
        if asset["class"] == "background":
            preview = ImageOps.fit(image, (154, 154), Image.Resampling.NEAREST)
            preview_panel = Image.new("RGBA", (158, 158), PANEL)
        else:
            scale = max(1, min(4, 152 // max(image.width, image.height)))
            preview = image.resize((image.width * scale, image.height * scale), Image.Resampling.NEAREST)
            preview_panel = checkerboard((158, 158))
        preview_x = (158 - preview.width) // 2
        preview_y = (158 - preview.height) // 2
        preview_panel.alpha_composite(preview, (preview_x, preview_y))
        sheet.alpha_composite(preview_panel, (x + 16, y + 45))
        display_name = f"{asset['nameKo']} / {asset['nameEn']}"
        if len(display_name) > 41:
            display_name = asset["nameKo"]
        draw.text((x + 16, y + 12), display_name, font=font(16), fill=WHITE)
        draw.text((x + 190, y + 54), asset["id"], font=font(11), fill=ACCENT)
        draw.text((x + 190, y + 82), f"CLASS  {asset['class']}", font=font(13), fill=MUTED)
        draw.text((x + 190, y + 108), f"WEAK  {asset['weakness']}", font=font(13), fill=MUTED)
        draw.text((x + 190, y + 136), asset["behaviorKo"], font=font(13), fill=WHITE)
        draw.text((x + 190, y + 170), f"{asset['canvas'][0]}×{asset['canvas'][1]} · strict 16c", font=font(12), fill=MUTED)

    path = CONTACT_SHEET_DIR / f"issue-45-{region_id}-contact-sheet.png"
    path.parent.mkdir(parents=True, exist_ok=True)
    sheet.convert("RGB").save(path, optimize=False)
    return path


def verify_generation_log(fragment: dict[str, Any]) -> None:
    log_path = ROOT / fragment["generationLog"]["path"]
    if sha256(log_path) != fragment["generationLog"]["sha256"]:
        raise ValueError("generation log SHA-256 mismatch")
    log = json.loads(log_path.read_text(encoding="utf-8"))
    if log.get("mode") != "built-in-imagegen-distinct-call-per-asset":
        raise ValueError("generation log mode must require a distinct ImageGen call")
    entries = log.get("assets", [])
    ids = [entry["id"] for entry in entries]
    artifacts = [entry["artifactId"] for entry in entries]
    fragment_ids = [asset["id"] for asset in fragment["assets"]]
    if len(ids) != 18 or len(ids) != len(set(ids)) or set(ids) != set(fragment_ids):
        raise ValueError("generation log must map exactly one entry to each of 18 assets")
    if len(artifacts) != len(set(artifacts)):
        raise ValueError("ImageGen artifact IDs must be distinct across all 18 assets")
    expected_artifacts = {
        asset["imagegenCallArtifacts"][0].removesuffix(".png")
        for asset in fragment["assets"]
    }
    if set(artifacts) != expected_artifacts:
        raise ValueError("generation log and fragment ImageGen artifact IDs differ")
    for paths in log["sourceReferences"].values():
        for relative_path in paths:
            if not (ROOT / relative_path).is_file():
                raise FileNotFoundError(f"missing style reference: {relative_path}")


def verify_fragment(fragment: dict[str, Any], *, require_complete: bool) -> None:
    if fragment.get("issue") != 45:
        raise ValueError("fragment issue must be 45")
    if fragment["sourceContract"]["sha256"] != EXPECTED_SOURCE_SHA:
        raise ValueError("Issue #38 source contract SHA-256 changed")
    verify_generation_log(fragment)
    assets = fragment["assets"]
    ids = [asset["id"] for asset in assets]
    if len(assets) != 18 or len(ids) != len(set(ids)):
        raise ValueError("fragment must contain exactly 18 unique assets")
    for region in fragment["regions"]:
        region_id = region["id"]
        region_assets = [asset for asset in assets if asset["regionId"] == region_id]
        classes = [asset["class"] for asset in region_assets]
        expected = {"normal": 4, "elite": 2, "boss": 2, "background": 1}
        actual = {name: classes.count(name) for name in expected}
        if actual != expected:
            raise ValueError(f"{region_id}: expected {expected}, got {actual}")
        palette = load_palette(region["paletteFile"])
        palette_hex = {f"#{red:02X}{green:02X}{blue:02X}" for red, green, blue in palette}
        if not set(region["paletteAnchors"]) <= palette_hex:
            raise ValueError(f"{region_id}: world palette anchors missing")
        allocation = region["eliteStageAllocation"]
        local_stages = [item["localStage"] for item in allocation]
        if local_stages != [5, 15, 25, 35, 45, 55]:
            raise ValueError(f"{region_id}: elite stages must be ordered 5/15/25/35/45/55")
        first, second = EXPECTED_ELITES[region_id]
        if [item["entityId"] for item in allocation] != [first, second] * 3:
            raise ValueError(f"{region_id}: elite allocation must alternate exact #38 elites")
        global_start = 240 if region_id == "r05" else 300
        if [item["globalStage"] for item in allocation] != [global_start + stage for stage in local_stages]:
            raise ValueError(f"{region_id}: global elite stage mapping mismatch")
        elite_ids = {asset["entityId"] for asset in region_assets if asset["class"] == "elite"}
        if elite_ids != {first, second}:
            raise ValueError(f"{region_id}: elite assets differ from exact #38 contract")
    if require_complete:
        for asset in assets:
            if asset["status"] != "production_ready":
                raise ValueError(f"{asset['id']}: still {asset['status']}")
            output = ROOT / asset["file"]
            if not output.is_file() or sha256(output) != asset.get("sha256"):
                raise ValueError(f"{asset['id']}: output/hash mismatch")
            inspect_pixels(
                Image.open(output),
                set(load_palette(asset["paletteFile"])),
                transparent=asset["class"] != "background",
            )
            if asset["verified"]["greenFringePixels"] != 0:
                raise ValueError(f"{asset['id']}: fringe verification failed")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--asset", action="append", help="Build only this asset ID; repeatable")
    parser.add_argument("--all", action="store_true", help="Build every asset")
    parser.add_argument("--verify-contract", action="store_true")
    parser.add_argument("--verify-complete", action="store_true")
    parser.add_argument("--contact-sheets", action="store_true")
    args = parser.parse_args()

    fragment = load_fragment()
    verify_fragment(fragment, require_complete=False)
    if args.verify_contract:
        print("issue45 contract passed: 18 assets, 2 strict palettes, exact alternating elites")
    selected = set(args.asset or [])
    if args.all:
        selected = {asset["id"] for asset in fragment["assets"]}
    if selected:
        known = {asset["id"] for asset in fragment["assets"]}
        if unknown := selected - known:
            raise ValueError(f"unknown asset IDs: {sorted(unknown)}")
        for asset in fragment["assets"]:
            if asset["id"] in selected:
                build_asset(asset)
                print(f"built {asset['id']} -> {asset['file']}")
        FRAGMENT_PATH.write_text(
            json.dumps(fragment, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )
    if args.verify_complete:
        verify_fragment(fragment, require_complete=True)
        print("issue45 production verification passed: 18/18")
    if args.contact_sheets:
        for region_id in ("r05", "r06"):
            path = build_contact_sheet(fragment, region_id)
            print(f"contact sheet: {path.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
