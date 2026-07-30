#!/usr/bin/env python3
"""Build and verify the isolated Issue #44 R3/R4 strict pixel pack.

Sprite inputs must already have been passed through the installed ImageGen
`remove_chroma_key.py` helper with soft matte, despill, and edge-contract 1.
Backgrounds remain opaque. This script never touches the shared production
manifest, shared palette, game content, or Swift sources.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Any

from PIL import Image, ImageDraw, ImageFont, ImageOps


ROOT = Path(__file__).resolve().parents[1]
FRAGMENT_PATH = ROOT / "art-export/issue-44-r3-r4/manifest-fragment.json"
CONTACT_SHEET_DIR = ROOT / "docs/screenshots"
BACKGROUND = (18, 20, 28, 255)
PANEL = (28, 35, 51, 255)
WHITE = (242, 240, 233, 255)
MUTED = (184, 195, 209, 255)
ACCENT = (242, 193, 78, 255)


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


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
        key=lambda color: (red - color[0]) ** 2
        + (green - color[1]) ** 2
        + (blue - color[2]) ** 2,
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
    max_width = canvas[0] - 2
    max_height = canvas[1] - 2
    ratio = min(max_width / cropped.width, max_height / cropped.height)
    target = (
        max(1, int(cropped.width * ratio)),
        max(1, int(cropped.height * ratio)),
    )
    # The production contract is intentionally nearest-neighbor only.
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
    alphas = set(rgba.getchannel("A").getdata())
    if not alphas <= {0, 255}:
        raise ValueError(f"partial alpha values remain: {sorted(alphas - {0, 255})[:8]}")
    colors = {
        (red, green, blue)
        for red, green, blue, alpha in rgba.getdata()
        if alpha == 255
    }
    outside = colors - palette
    if outside:
        raise ValueError(f"colors outside strict palette: {sorted(outside)}")
    corners = [
        rgba.getpixel((0, 0))[3],
        rgba.getpixel((rgba.width - 1, 0))[3],
        rgba.getpixel((0, rgba.height - 1))[3],
        rgba.getpixel((rgba.width - 1, rgba.height - 1))[3],
    ]
    transparent_corners = all(alpha == 0 for alpha in corners)
    if transparent and not transparent_corners:
        raise ValueError("sprite corners must remain transparent")
    if not transparent and alphas != {255}:
        raise ValueError("background must be fully opaque")
    # Exact chroma green and highly dominant residual greens are forbidden.
    green_fringe = sum(
        1
        for red, green, blue, alpha in rgba.getdata()
        if alpha == 255 and green > 220 and green > red * 1.65 and green > blue * 1.65
    )
    if green_fringe:
        raise ValueError(f"detected {green_fringe} possible chroma fringe pixels")
    opaque = sum(1 for alpha in rgba.getchannel("A").getdata() if alpha == 255)
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
    if is_background:
        intermediate_path = source_path
        built = build_background(Image.open(source_path), canvas, palette)
    else:
        intermediate_path = ROOT / asset["transparentFile"]
        if not intermediate_path.is_file():
            raise FileNotFoundError(
                f"{intermediate_path} missing; run the official chroma helper first"
            )
        built = build_sprite(Image.open(intermediate_path), canvas, palette)

    output_path = ROOT / asset["file"]
    output_path.parent.mkdir(parents=True, exist_ok=True)
    built.save(output_path, optimize=False)
    verified = inspect_pixels(
        built,
        set(palette),
        transparent=not is_background,
    )
    asset.update(
        {
            "status": "production_ready",
            "sourceSha256": sha256(source_path),
            "sha256": sha256(output_path),
            "verified": verified,
        }
    )
    if not is_background:
        asset["transparentSha256"] = sha256(intermediate_path)


def font(size: int) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    paths = [
        Path("/System/Library/Fonts/AppleSDGothicNeo.ttc"),
        Path("/System/Library/Fonts/Supplemental/Arial.ttf"),
    ]
    for path in paths:
        if path.is_file():
            return ImageFont.truetype(str(path), size=size)
    return ImageFont.load_default()


def build_contact_sheet(fragment: dict[str, Any], region_id: str) -> Path:
    assets = [asset for asset in fragment["assets"] if asset["regionId"] == region_id]
    if len(assets) != 9 or any(asset["status"] != "production_ready" for asset in assets):
        raise ValueError(f"{region_id}: contact sheet requires all nine verified assets")
    region = next(item for item in fragment["regions"] if item["id"] == region_id)
    sheet = Image.new("RGBA", (1280, 900), BACKGROUND)
    draw = ImageDraw.Draw(sheet)
    draw.text((32, 22), f"{region_id.upper()} · {region['nameKo']} · ISSUE #44 STRICT PIXEL QA", font=font(28), fill=WHITE)
    draw.text((32, 60), "100% production pixels · 4× nearest-neighbor preview · names/behavior/weakness", font=font(17), fill=MUTED)

    for index, asset in enumerate(assets):
        column = index % 3
        row = index // 3
        x = 28 + column * 414
        y = 104 + row * 255
        draw.rounded_rectangle((x, y, x + 388, y + 228), radius=5, fill=PANEL, outline=MUTED, width=1)
        image = Image.open(ROOT / asset["file"]).convert("RGBA")
        if asset["class"] == "background":
            preview = ImageOps.fit(image, (154, 154), Image.Resampling.NEAREST)
        else:
            scale = min(4, max(2, 152 // max(image.width, image.height)))
            preview = image.resize((image.width * scale, image.height * scale), Image.Resampling.NEAREST)
        preview_x = x + 16 + (158 - preview.width) // 2
        preview_y = y + 45 + (158 - preview.height) // 2
        sheet.alpha_composite(preview, (preview_x, preview_y))
        draw.text((x + 16, y + 12), f"{asset['nameKo']} / {asset['nameEn']}", font=font(16), fill=WHITE)
        draw.text((x + 184, y + 56), asset["id"], font=font(13), fill=ACCENT)
        draw.text((x + 184, y + 86), f"CLASS  {asset['class']}", font=font(13), fill=MUTED)
        draw.text((x + 184, y + 112), f"WEAK  {asset['weakness']}", font=font(13), fill=MUTED)
        draw.text((x + 184, y + 140), asset["behaviorKo"], font=font(13), fill=WHITE)
        draw.text((x + 184, y + 172), f"{asset['canvas'][0]}×{asset['canvas'][1]} · binary alpha", font=font(12), fill=MUTED)

    path = CONTACT_SHEET_DIR / f"issue-44-{region_id}-contact-sheet.png"
    path.parent.mkdir(parents=True, exist_ok=True)
    sheet.convert("RGB").save(path, optimize=False)
    return path


def verify_fragment(fragment: dict[str, Any], *, require_complete: bool) -> None:
    assets = fragment["assets"]
    ids = [asset["id"] for asset in assets]
    if len(assets) != 18 or len(ids) != len(set(ids)):
        raise ValueError("fragment must contain exactly 18 unique assets")
    for region in fragment["regions"]:
        region_assets = [asset for asset in assets if asset["regionId"] == region["id"]]
        classes = [asset["class"] for asset in region_assets]
        expected = {"normal": 4, "elite": 2, "boss": 2, "background": 1}
        actual = {name: classes.count(name) for name in expected}
        if actual != expected:
            raise ValueError(f"{region['id']}: expected {expected}, got {actual}")
        palette = load_palette(region["paletteFile"])
        palette_hex = {f"#{red:02X}{green:02X}{blue:02X}" for red, green, blue in palette}
        if not set(region["paletteAnchors"]) <= palette_hex:
            raise ValueError(f"{region['id']}: world palette anchors missing")
        allocation = region["eliteStageAllocation"]
        if sorted(item["localStage"] for item in allocation) != [5, 15, 25, 35, 45, 55]:
            raise ValueError(f"{region['id']}: invalid elite stage allocation")
        elite_ids = {asset["entityId"] for asset in region_assets if asset["class"] == "elite"}
        if {item["entityId"] for item in allocation} != elite_ids:
            raise ValueError(f"{region['id']}: allocation must use both elite entities")
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
        print("issue44 contract passed: 18 assets, 2 strict palettes, 2 elites per region")
    selected = set(args.asset or [])
    if args.all:
        selected = {asset["id"] for asset in fragment["assets"]}
    if selected:
        known = {asset["id"] for asset in fragment["assets"]}
        unknown = selected - known
        if unknown:
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
        print("issue44 production verification passed: 18/18")
    if args.contact_sheets:
        for region_id in ("r03", "r04"):
            print(f"contact sheet: {build_contact_sheet(fragment, region_id).relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
