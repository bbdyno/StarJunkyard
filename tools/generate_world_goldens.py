#!/usr/bin/env python3
"""Regenerate combat, R1 economy, and regional economy Golden fixtures."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path
from typing import Any

import economy_simulation
import reference_simulation
import world_economy


ROOT = Path(__file__).resolve().parents[1]
CONTENT_VERSION = "0.3.0"


def digest(value: Any) -> str:
    encoded = json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(encoded.encode("utf-8")).hexdigest()


def write(path: Path, value: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def update_existing() -> None:
    for path in sorted((ROOT / "golden" / "combat").glob("*.json")):
        fixture = json.loads(path.read_text(encoding="utf-8"))
        expected = reference_simulation.simulate(fixture["input"])
        fixture["contentVersion"] = CONTENT_VERSION
        fixture["expectedState"] = expected
        fixture["expectedDigest"] = digest(expected)
        write(path, fixture)
    for path in [ROOT / "golden" / "economy" / "first_30_minutes.json", ROOT / "golden" / "economy" / "first_day.json"]:
        fixture = json.loads(path.read_text(encoding="utf-8"))
        expected = economy_simulation.simulate(fixture["input"])
        fixture["contentVersion"] = CONTENT_VERSION
        fixture["expectedState"] = expected
        fixture["expectedDigest"] = digest(expected)
        write(path, fixture)


def write_regions() -> None:
    for number in range(1, 7):
        region_id = f"r{number:02d}"
        expected = world_economy.summarize(region_id)
        fixture = {
            "schemaVersion": 1,
            "fixtureId": f"economy_{region_id}_one_clear",
            "contentVersion": CONTENT_VERSION,
            "regionId": region_id,
            "expectedState": expected,
            "expectedDigest": digest(expected),
        }
        write(ROOT / "golden" / "economy" / "regions" / f"{region_id}.json", fixture)


def main() -> int:
    update_existing()
    write_regions()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
