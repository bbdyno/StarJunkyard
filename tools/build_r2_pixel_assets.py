#!/usr/bin/env python3
"""Build approved R2 image-generation sources into strict 1x pixel PNGs."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path

from PIL import Image, ImageOps


ROOT = Path(__file__).resolve().parents[1]
SOURCE_DIR = ROOT / "art-source" / "generated" / "r02"
PALETTE_PATH = ROOT / "art-source" / "palettes" / "r02_mall12.gpl"
COMMON_PALETTE_PATH = ROOT / "art-source" / "palettes" / "common16.gpl"
OUTPUT_DIR = ROOT / "art-export" / "production" / "sprites"

SPRITES = {
    "enemy_cart_deer": ("enemy_cart_deer.png", (48, 48)),
    "enemy_mannequin_octopus": ("enemy_mannequin_octopus.png", (48, 48)),
    "enemy_kiosk_turtle": ("enemy_kiosk_turtle.png", (48, 48)),
    "enemy_vacuum_snail": ("enemy_vacuum_snail.png", (48, 48)),
    "elite_escalator_centipede": ("elite_escalator_centipede.png", (64, 48)),
    "elite_shutter_peacock": ("elite_shutter_peacock.png", (64, 64)),
    "boss_billboard_hydra": ("boss_billboard_hydra.png", (128, 112)),
    "boss_empty_throne": ("boss_empty_throne.png", (160, 144)),
}


def load_palette(path: Path = PALETTE_PATH, expected_count: int = 12) -> list[tuple[int, int, int]]:
    colors: list[tuple[int, int, int]] = []
    for line in path.read_text(encoding="utf-8").splitlines():
        values = line.split()
        if len(values) >= 3 and all(value.isdigit() for value in values[:3]):
            colors.append(tuple(int(value) for value in values[:3]))
    if len(colors) != expected_count:
        raise ValueError(f"expected {expected_count} colors in {path.name}, found {len(colors)}")
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


def strict_palette(image: Image.Image, palette: list[tuple[int, int, int]]) -> Image.Image:
    source = image.convert("RGBA")
    output = Image.new("RGBA", source.size)
    for y in range(source.height):
        for x in range(source.width):
            red, green, blue, alpha = source.getpixel((x, y))
            if alpha < 128:
                output.putpixel((x, y), (0, 0, 0, 0))
            else:
                output.putpixel((x, y), (*nearest_color(red, green, blue, palette), 255))
    return output


def fit_sprite(source_path: Path, canvas: tuple[int, int], palette: list[tuple[int, int, int]]) -> Image.Image:
    source = Image.open(source_path).convert("RGBA")
    bounds = source.getchannel("A").getbbox()
    if bounds is None:
        raise ValueError(f"{source_path} contains no visible subject")
    source = source.crop(bounds)
    target_ratio = min((canvas[0] - 2) / source.width, (canvas[1] - 2) / source.height)
    target_size = (
        max(1, round(source.width * target_ratio)),
        max(1, round(source.height * target_ratio)),
    )
    source = source.resize(target_size, Image.Resampling.LANCZOS)
    source = strict_palette(source, palette)
    output = Image.new("RGBA", canvas)
    output.alpha_composite(source, ((canvas[0] - source.width) // 2, canvas[1] - source.height - 1))
    return output


def fit_background(source_path: Path, palette: list[tuple[int, int, int]]) -> Image.Image:
    source = Image.open(source_path).convert("RGB")
    source = ImageOps.fit(source, (360, 572), Image.Resampling.LANCZOS, centering=(0.5, 0.52))
    background_palette = [color for color in palette if color not in {(166, 75, 60), (242, 193, 78)}]
    return strict_palette(source.convert("RGBA"), background_palette)


def save(identifier: str, image: Image.Image) -> dict[str, object]:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    path = OUTPUT_DIR / f"{identifier}.png"
    image.save(path, optimize=False)
    return {
        "file": path.relative_to(ROOT).as_posix(),
        "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
    }


def build() -> dict[str, dict[str, object]]:
    palette = load_palette()
    common_sprite_palette = load_palette(COMMON_PALETTE_PATH, expected_count=16)[:12]
    output = {
        identifier: save(identifier, fit_sprite(SOURCE_DIR / filename, canvas, palette))
        for identifier, (filename, canvas) in SPRITES.items()
    }
    output["background_r02_closed_megamall"] = save(
        "background_r02_closed_megamall",
        fit_background(SOURCE_DIR / "background_closed_megamall.png", palette),
    )
    output["boss_alley_devourer"] = save(
        "boss_alley_devourer",
        fit_sprite(
            ROOT / "art-source" / "generated" / "r01" / "boss_alley_devourer.png",
            (144, 96),
            common_sprite_palette,
        ),
    )
    output["elite_tire_matador"] = save(
        "elite_tire_matador",
        fit_sprite(
            ROOT / "art-source" / "generated" / "r01" / "elite_tire_matador.png",
            (64, 64),
            common_sprite_palette,
        ),
    )
    return output


def main() -> int:
    print(json.dumps(build(), ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
