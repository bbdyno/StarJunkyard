#!/usr/bin/env python3
"""Convert approved image-generation sources into strict shared pixel assets."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

from PIL import Image, ImageOps


ROOT = Path(__file__).resolve().parents[1]
PALETTE_PATH = ROOT / "art-source" / "palettes" / "common16.gpl"
OUTPUT_DIR = ROOT / "art-export" / "production" / "drawable-nodpi"


def load_palette() -> list[tuple[int, int, int]]:
    colors: list[tuple[int, int, int]] = []
    for line in PALETTE_PATH.read_text(encoding="utf-8").splitlines():
        values = line.split()
        if len(values) >= 3 and all(value.isdigit() for value in values[:3]):
            colors.append(tuple(int(value) for value in values[:3]))
    if len(colors) != 16:
        raise ValueError(f"expected 16 colors, found {len(colors)}")
    return colors


def nearest_color(
    red: int, green: int, blue: int, palette: list[tuple[int, int, int]]
) -> tuple[int, int, int]:
    return min(
        palette,
        key=lambda color: (red - color[0]) ** 2
        + (green - color[1]) ** 2
        + (blue - color[2]) ** 2,
    )


def quantize_strict(image: Image.Image, palette: list[tuple[int, int, int]]) -> Image.Image:
    source = image.convert("RGBA")
    output = Image.new("RGBA", source.size)
    output_pixels = output.load()
    for y in range(source.height):
        for x in range(source.width):
            red, green, blue, alpha = source.getpixel((x, y))
            if alpha < 128:
                output_pixels[x, y] = (0, 0, 0, 0)
            else:
                mapped = nearest_color(red, green, blue, palette)
                output_pixels[x, y] = (*mapped, 255)
    return output


def fit_sprite(
    source_path: Path,
    canvas: tuple[int, int],
    palette: list[tuple[int, int, int]],
) -> Image.Image:
    source = Image.open(source_path).convert("RGBA")
    alpha = source.getchannel("A")
    bounds = alpha.getbbox()
    if bounds is None:
        raise ValueError(f"{source_path} contains no opaque sprite")
    source = source.crop(bounds)
    max_width = canvas[0] - 2
    max_height = canvas[1] - 2
    ratio = min(max_width / source.width, max_height / source.height)
    target = (
        max(1, round(source.width * ratio)),
        max(1, round(source.height * ratio)),
    )
    source = source.resize(target, Image.Resampling.LANCZOS)
    source = quantize_strict(source, palette)
    output = Image.new("RGBA", canvas)
    x = (canvas[0] - source.width) // 2
    y = canvas[1] - source.height - 1
    output.alpha_composite(source, (x, y))
    return output


def fit_background(
    source_path: Path,
    size: tuple[int, int],
    palette: list[tuple[int, int, int]],
) -> Image.Image:
    source = Image.open(source_path).convert("RGB")
    fitted = ImageOps.fit(
        source,
        size,
        method=Image.Resampling.LANCZOS,
        centering=(0.5, 0.46),
    ).convert("RGBA")
    return quantize_strict(fitted, palette)


def recolor_spark_drone(image: Image.Image) -> Image.Image:
    replacements = {
        (30, 90, 90): (70, 103, 168),
        (56, 166, 165): (169, 75, 124),
        (118, 214, 201): (242, 193, 78),
    }
    output = image.copy()
    pixels = output.load()
    for y in range(output.height):
        for x in range(output.width):
            red, green, blue, alpha = pixels[x, y]
            pixels[x, y] = (*replacements.get((red, green, blue), (red, green, blue)), alpha)
    return output


def save_asset(identifier: str, image: Image.Image) -> dict[str, object]:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    path = OUTPUT_DIR / f"{identifier}.png"
    image.save(path, optimize=False)
    relative = path.relative_to(ROOT).as_posix()
    return {
        "file": relative,
        "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
    }


def build_preview(background: Image.Image, assets: dict[str, Image.Image]) -> None:
    preview = background.copy()

    def paste_scaled(identifier: str, x: int, y: int, scale: int) -> None:
        sprite = assets[identifier]
        sprite = sprite.resize(
            (sprite.width * scale, sprite.height * scale), Image.Resampling.NEAREST
        )
        preview.alpha_composite(sprite, (x, y))

    paste_scaled("actor_mo_base", 22, 382, 2)
    paste_scaled("drone_riv0_base", 104, 292, 1)
    paste_scaled("enemy_can_bug", 258, 420, 2)
    preview_path = ROOT / "docs" / "screenshots" / "r1-pixel-art-preview.png"
    preview_path.parent.mkdir(parents=True, exist_ok=True)
    preview.save(preview_path, optimize=False)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--mechanic", type=Path, required=True)
    parser.add_argument("--rivet", type=Path, required=True)
    parser.add_argument("--can-bug", type=Path, required=True)
    parser.add_argument("--umbrella-crab", type=Path, required=True)
    parser.add_argument("--fan-bat", type=Path, required=True)
    parser.add_argument("--vending-knight", type=Path, required=True)
    parser.add_argument("--cancrab-king", type=Path, required=True)
    parser.add_argument("--background", type=Path, required=True)
    args = parser.parse_args()

    palette = load_palette()
    sprites = {
        "actor_mo_base": fit_sprite(args.mechanic, (48, 64), palette),
        "drone_riv0_base": fit_sprite(args.rivet, (48, 40), palette),
        "enemy_can_bug": fit_sprite(args.can_bug, (32, 32), palette),
        "enemy_umbrella_crab": fit_sprite(args.umbrella_crab, (48, 48), palette),
        "enemy_fan_bat": fit_sprite(args.fan_bat, (48, 48), palette),
        "elite_vending_knight": fit_sprite(args.vending_knight, (64, 64), palette),
        "boss_cancrab_king": fit_sprite(args.cancrab_king, (128, 96), palette),
    }
    sprites["drone_spk2_base"] = recolor_spark_drone(sprites["drone_riv0_base"])
    background = fit_background(args.background, (360, 572), palette)

    manifest_entries = {
        identifier: save_asset(identifier, image)
        for identifier, image in sprites.items()
    }
    manifest_entries["background_r01_back_alley"] = save_asset(
        "background_r01_back_alley", background
    )
    build_preview(background, sprites)
    print(json.dumps(manifest_entries, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
