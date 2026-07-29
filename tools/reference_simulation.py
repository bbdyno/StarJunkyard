#!/usr/bin/env python3
"""Development-only integer combat reference used to author Golden fixtures."""

from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
PPM = 1_000_000
TICK_MS = 50
MASK_64 = (1 << 64) - 1
MASK_32 = (1 << 32) - 1


@dataclass
class PCG32:
    state: int
    stream: int

    @classmethod
    def seeded(cls, seed: int, stream: int) -> "PCG32":
        generator = cls(state=0, stream=stream & MASK_64)
        generator.next_u32()
        generator.state = (generator.state + seed) & MASK_64
        generator.next_u32()
        return generator

    def next_u32(self) -> int:
        old_state = self.state
        increment = ((self.stream << 1) | 1) & MASK_64
        self.state = (old_state * 6_364_136_223_846_793_005 + increment) & MASK_64
        xor_shifted = (((old_state >> 18) ^ old_state) >> 27) & MASK_32
        rotation = (old_state >> 59) & 31
        return ((xor_shifted >> rotation) | (xor_shifted << ((-rotation) & 31))) & MASK_32

    def bounded(self, bound: int) -> int:
        threshold = ((1 << 32) - bound) % bound
        while True:
            value = self.next_u32()
            if value >= threshold:
                return value % bound


def _load_content() -> dict[str, Any]:
    return json.loads((ROOT / "content" / "r1_vertical_slice.json").read_text(encoding="utf-8"))


def simulate(fixture_input: dict[str, Any], content: dict[str, Any] | None = None) -> dict[str, Any]:
    content = content or _load_content()
    stage = next(item for item in content["stages"] if item["number"] == fixture_input["stage"])
    enemy_by_id = {enemy["id"]: enemy for enemy in content["enemies"]}
    wave = stage["wave"]
    loadout = fixture_input["loadout"]
    generator = PCG32.seeded(int(fixture_input["seed"]), int(fixture_input["stream"]))
    actions_by_tick = {action["tick"]: action for action in fixture_input["actions"]}

    enemy_index = 0
    enemy_id = wave[enemy_index]
    enemy = enemy_by_id[enemy_id]
    enemy_hp = stage["baseHp"] * enemy["hpMultiplierPpm"] // PPM
    credits = 0
    parts = 0
    next_player_tick = 1
    next_drone_tick = 1
    overclock_until = 0
    overclock_speed_ppm = PPM
    last_tick = 0

    def attack(damage: int) -> int:
        if generator.bounded(PPM) < loadout["criticalChancePpm"]:
            return damage * loadout["criticalDamagePpm"] // PPM
        return damage

    def collect_reward(defeated: dict[str, Any]) -> None:
        nonlocal credits, parts
        credits += stage["baseReward"] * stage["rewardMultiplierPpm"] // PPM
        parts += {"normal": 3, "elite": 6, "boss": 15}[defeated["class"]]

    for tick in range(1, fixture_input["ticks"] + 1):
        last_tick = tick
        action = actions_by_tick.get(tick)
        if action and action["type"] == "overclock":
            overclock_until = tick + action["durationTicks"]
            overclock_speed_ppm = action["attackSpeedPpm"]

        if tick >= next_player_tick:
            enemy_hp -= attack(loadout["playerDamage"])
            active_speed = overclock_speed_ppm if tick < overclock_until else PPM
            interval_ms = loadout["playerAttackIntervalMs"] * PPM // active_speed
            next_player_tick = tick + max(1, interval_ms // TICK_MS)

        if enemy_hp > 0 and loadout["droneDamage"] > 0 and tick >= next_drone_tick:
            enemy_hp -= attack(loadout["droneDamage"])
            next_drone_tick = tick + max(1, loadout["droneAttackIntervalMs"] // TICK_MS)

        if enemy_hp <= 0:
            collect_reward(enemy)
            enemy_index += 1
            if enemy_index == len(wave):
                break
            enemy_id = wave[enemy_index]
            enemy = enemy_by_id[enemy_id]
            enemy_hp = stage["baseHp"] * enemy["hpMultiplierPpm"] // PPM

    return {
        "stage": fixture_input["stage"],
        "ticksElapsed": last_tick,
        "enemyIndex": enemy_index,
        "enemyHp": max(0, enemy_hp),
        "credits": credits,
        "parts": parts,
        "cleared": enemy_index == len(wave),
        "rngState": str(generator.state),
        "rngStream": str(generator.stream),
    }


if __name__ == "__main__":
    raise SystemExit("Import simulate() from tests or a fixture-authoring script.")
