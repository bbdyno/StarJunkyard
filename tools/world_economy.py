#!/usr/bin/env python3
"""Deterministic per-region economy summaries for R1-R6 Golden fixtures."""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
PPM = 1_000_000
CURRENCIES = ("credits", "parts", "circuits", "alloy", "starCores")


def load_content() -> dict[str, Any]:
    return json.loads((ROOT / "content" / "world_r1_r6.json").read_text(encoding="utf-8"))


def summarize(region_id: str, content: dict[str, Any] | None = None) -> dict[str, Any]:
    content = content or load_content()
    region = next(item for item in content["regions"] if item["id"] == region_id)
    stages = [stage for stage in content["stages"] if stage["regionId"] == region_id]
    enemies = {enemy["id"]: enemy for enemy in content["enemies"]}
    part_rewards = content["economy"]["enemyPartRewards"]
    wallet = {currency: 0 for currency in CURRENCIES}
    first_clear = {currency: 0 for currency in CURRENCIES}
    boss_limits: dict[str, int] = {}

    for stage in stages:
        credits_per_enemy = stage["baseReward"] * stage["rewardMultiplierPpm"] // PPM
        for enemy_id in stage["wave"]:
            enemy = enemies[enemy_id]
            wallet["credits"] += credits_per_enemy
            wallet["parts"] += part_rewards[enemy["class"]]
        for currency in CURRENCIES:
            first_clear[currency] += stage["firstClearReward"][currency]
        if "timeLimitMs" in stage:
            boss_limits[str(stage["number"])] = stage["timeLimitMs"]

    production_assets = sum(
        enemies[enemy_id]["assetStatus"] == "production_ready"
        for enemy_id in [*region["enemyIds"], *region["eliteIds"], region["midBossId"], region["regionBossId"]]
    )
    return {
        "regionId": region_id,
        "stageRange": [region["stageStart"], region["stageEnd"]],
        "oneClearBattleWallet": wallet,
        "firstClearWallet": first_clear,
        "expectedClearSeconds": sum(stage["expectedClearSeconds"] for stage in stages),
        "bossTimeLimitsMs": boss_limits,
        "uniqueEnemyCount": 8,
        "productionAssetCount": production_assets,
        "primaryDropId": region["primaryDropId"],
    }


if __name__ == "__main__":
    raise SystemExit("Import summarize() from Golden generation or tests.")
