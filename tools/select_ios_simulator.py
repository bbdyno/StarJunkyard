#!/usr/bin/env python3
"""Select a deterministic available iPhone UDID from `simctl ... --json`."""

from __future__ import annotations

import json
import sys
from typing import Any


PREFERRED_MODELS = (
    "iPhone 17 Pro",
    "iPhone 17",
    "iPhone 16 Pro",
    "iPhone 16",
    "iPhone 15 Pro",
    "iPhone 15",
)


def select_simulator(payload: dict[str, Any]) -> str:
    candidates: list[tuple[int, str, str, str]] = []
    for runtime, devices in payload.get("devices", {}).items():
        for device in devices:
            name = str(device.get("name", ""))
            udid = str(device.get("udid", ""))
            available = device.get("isAvailable", device.get("availability") == "(available)")
            if not available or not name.startswith("iPhone") or not udid:
                continue
            try:
                preference = PREFERRED_MODELS.index(name)
            except ValueError:
                preference = len(PREFERRED_MODELS)
            candidates.append((preference, name, runtime, udid))

    if not candidates:
        raise ValueError("no available iPhone simulator was reported by simctl")
    candidates.sort(key=lambda item: (item[0], item[1], item[2]), reverse=False)
    return candidates[0][3]


def main() -> int:
    try:
        print(select_simulator(json.load(sys.stdin)))
    except (json.JSONDecodeError, ValueError) as error:
        print(f"simulator selection failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
