#!/usr/bin/env python3
"""Static architecture guard for the Android game-first pixel combat shell."""

from __future__ import annotations

import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class AndroidPixelShellError(RuntimeError):
    pass


def read(relative_path: str) -> str:
    path = ROOT / relative_path
    if not path.is_file():
        raise AndroidPixelShellError(f"missing Android contract file: {relative_path}")
    return path.read_text(encoding="utf-8")


def require(source: str, token: str, context: str) -> None:
    if token not in source:
        raise AndroidPixelShellError(f"{context}: required token is missing: {token}")


def validate_android_pixel_shell() -> str:
    activity = read("android/app/src/main/kotlin/com/bbdyno/starjunkyard/MainActivity.kt")
    route = read(
        "android/feature/combat/src/main/kotlin/com/bbdyno/starjunkyard/combat/PixelCombatRoute.kt"
    )
    surface = read(
        "android/feature/combat/src/main/kotlin/com/bbdyno/starjunkyard/combat/PixelCombatSurfaceView.kt"
    )
    painter = read(
        "android/feature/combat/src/main/kotlin/com/bbdyno/starjunkyard/combat/DebugPixelPainter.kt"
    )
    app_build = read("android/app/build.gradle.kts")
    manifest = read("android/app/src/main/AndroidManifest.xml")

    forbidden_shell_patterns = {
        r"\bCard\s*\(": "Compose Card",
        r"\bButton\s*\(": "Compose Button",
        r"\bLazy(?:Column|Row)\s*\(": "Compose lazy list",
        r"\bScaffold\s*\(": "Compose Scaffold",
        r"androidx\.compose\.material": "Compose Material",
    }
    shell_source = activity + "\n" + route
    for pattern, label in forbidden_shell_patterns.items():
        if re.search(pattern, shell_source):
            raise AndroidPixelShellError(f"app-like combat shell component is forbidden: {label}")

    if route.count("AndroidView(") != 1:
        raise AndroidPixelShellError("PixelCombatRoute must host exactly one AndroidView")
    require(route, "PixelCombatSurfaceView(context)", "PixelCombatRoute")
    require(surface, ": SurfaceView", "PixelCombatSurfaceView")
    require(surface, "holder.lockCanvas()", "PixelCombatSurfaceView")
    require(surface, "setZOrderOnTop(true)", "PixelCombatSurfaceView")
    require(surface, "SIMULATION_STEP_NS = 50_000_000L", "PixelCombatSurfaceView")
    require(painter, "isAntiAlias = false", "DebugPixelPainter")
    require(painter, "isFilterBitmap = false", "DebugPixelPainter")
    require(painter, "canvas.scale(scale.toFloat(), scale.toFloat())", "DebugPixelPainter")
    require(painter, "const val LOGICAL_WIDTH = 360", "DebugPixelPainter")
    require(painter, "const val LOGICAL_HEIGHT = 800", "DebugPixelPainter")
    require(app_build, 'compileSdk = 36', "Android app build")
    require(app_build, 'minSdk = 28', "Android app build")
    require(app_build, 'targetSdk = 36', "Android app build")
    require(app_build, 'assets.srcDir("../../content")', "Android app build")
    require(app_build, 'it.name == "packageRelease"', "Android release gate")
    require(manifest, 'android:screenOrientation="portrait"', "Android manifest")

    return "Android pixel shell passed: Compose host -> one SurfaceView -> 360x800 integer Canvas"


if __name__ == "__main__":
    try:
        print(validate_android_pixel_shell())
    except AndroidPixelShellError as error:
        raise SystemExit(f"validation failed: {error}") from error
