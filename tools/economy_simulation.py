#!/usr/bin/env python3
"""Deterministic R1 progression/economy simulation used by Golden tests."""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
PPM = 1_000_000
CURRENCIES = ("credits", "parts", "circuits", "alloy", "starCores")


def _content() -> dict[str, Any]:
    return json.loads((ROOT / "content" / "r1_vertical_slice.json").read_text(encoding="utf-8"))


def empty_wallet() -> dict[str, int]:
    return {currency: 0 for currency in CURRENCIES}


def add(wallet: dict[str, int], reward: dict[str, int], multiplier: int = 1) -> None:
    for currency in CURRENCIES:
        wallet[currency] += reward.get(currency, 0) * multiplier


def subtract(wallet: dict[str, int], cost: dict[str, int]) -> bool:
    if any(wallet[currency] < cost[currency] for currency in CURRENCIES):
        return False
    for currency in CURRENCIES:
        wallet[currency] -= cost[currency]
    return True


def battle_reward(stage: dict[str, Any], content: dict[str, Any]) -> dict[str, int]:
    enemy_by_id = {enemy["id"]: enemy for enemy in content["enemies"]}
    part_rewards = content["economy"]["enemyPartRewards"]
    credits_per_enemy = stage["baseReward"] * stage["rewardMultiplierPpm"] // PPM
    reward = empty_wallet()
    for enemy_id in stage["wave"]:
        reward["credits"] += credits_per_enemy
        reward["parts"] += part_rewards[enemy_by_id[enemy_id]["class"]]
    return reward


def launch_status(stage: int, wallet: dict[str, int], content: dict[str, Any]) -> tuple[bool, dict[str, int]]:
    launch = content["economy"]["launch"]
    missing = {
        currency: max(0, launch["cost"][currency] - wallet[currency])
        for currency in CURRENCIES
    }
    return stage >= launch["requiredStage"] and not any(missing.values()), missing


def simulate(fixture_input: dict[str, Any], content: dict[str, Any] | None = None) -> dict[str, Any]:
    content = content or _content()
    stages = content["stages"]
    stage_by_number = {stage["number"]: stage for stage in stages}
    region_end = content["slice"]["stageEnd"]
    wallet = empty_wallet()
    active_seconds = fixture_input["activeSeconds"]
    elapsed = 0
    clears = 0
    highest_cleared = 0

    while True:
        stage_number = min(highest_cleared + 1, region_end)
        stage = stage_by_number[stage_number]
        duration = stage["expectedClearSeconds"]
        if elapsed + duration > active_seconds:
            break
        elapsed += duration
        clears += 1
        first_clear = stage_number > highest_cleared
        highest_cleared = max(highest_cleared, stage_number)
        add(wallet, battle_reward(stage, content))
        if first_clear:
            add(wallet, stage["firstClearReward"])

    offline = content["economy"]["offline"]
    offline_seconds = min(max(0, fixture_input.get("offlineSeconds", 0)), offline["freeCapSeconds"])
    offline_cycles = 0
    offline_reward = empty_wallet()
    if highest_cleared > 0:
        offline_cycles = offline_seconds // offline["cycleSeconds"]
        full_reward = battle_reward(stage_by_number[highest_cleared], content)
        for currency in CURRENCIES:
            offline_reward[currency] = full_reward[currency] * offline_cycles * offline["efficiencyPpm"] // PPM
        add(wallet, offline_reward)

    purchased: list[str] = []
    sink_by_id = {sink["id"]: sink for sink in content["economy"]["upgradeSinks"]}
    for sink_id in fixture_input.get("purchases", []):
        sink = sink_by_id[sink_id]
        if subtract(wallet, sink["cost"]):
            purchased.append(sink_id)

    eligible, missing = launch_status(highest_cleared, wallet, content)
    wallet_after_launch = dict(wallet)
    if eligible:
        subtract(wallet_after_launch, content["economy"]["launch"]["cost"])

    return {
        "activeSecondsApplied": elapsed,
        "highestClearedStage": highest_cleared,
        "totalActiveClears": clears,
        "purchasedSinkIds": purchased,
        "offlineSecondsApplied": offline_seconds,
        "offlineCycles": offline_cycles,
        "offlineReward": offline_reward,
        "wallet": wallet,
        "launchEligible": eligible,
        "launchMissing": missing,
        "walletAfterLaunch": wallet_after_launch,
    }


if __name__ == "__main__":
    raise SystemExit("Import simulate() from tests or fixture-authoring tools.")
