#!/usr/bin/env python3
"""Deterministically extend the checked-in R1 content contract to stage 60."""

from __future__ import annotations

import json
from decimal import Decimal, ROUND_HALF_UP, getcontext
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
CONTENT_PATH = ROOT / "content" / "r1_vertical_slice.json"
PPM = 1_000_000
REGION_END = 60
NORMAL_ENEMIES = ("can_bug", "umbrella_crab", "fan_bat", "fridge_boar")


def encounter_class(stage: int) -> str:
    if stage == REGION_END:
        return "regionBoss"
    if stage % 10 == 0:
        return "boss"
    if stage % 5 == 0:
        return "elite"
    return "normal"


def wave_for(stage: int) -> list[str]:
    kind = encounter_class(stage)
    if kind in {"boss", "regionBoss"}:
        return ["cancrab_king"]
    count = 6 if kind == "elite" else 8
    wave = [NORMAL_ENEMIES[(stage + offset * 3) % len(NORMAL_ENEMIES)] for offset in range(count)]
    if kind == "elite":
        wave.append("vending_knight")
    return wave


def first_clear_reward(stage: int) -> dict[str, int]:
    kind = encounter_class(stage)
    if kind == "regionBoss":
        return {"credits": 0, "parts": 0, "circuits": 20, "alloy": 12, "starCores": 1}
    if kind == "boss":
        return {"credits": 0, "parts": 0, "circuits": 8, "alloy": 4, "starCores": 0}
    if kind == "elite":
        return {"credits": 0, "parts": 0, "circuits": 3, "alloy": 1, "starCores": 0}
    circuits = 1 if stage % 3 == 0 else 0
    return {"credits": 0, "parts": 0, "circuits": circuits, "alloy": 0, "starCores": 0}


def reward_multiplier(stage: int) -> int:
    kind = encounter_class(stage)
    if kind == "regionBoss":
        return 75 * PPM
    if kind == "boss":
        return (35 + stage // 10 * 5) * PPM
    if kind == "elite":
        return 1_300_000 + stage * 20_000
    return 1_000_000 + stage * 15_000


def expected_clear_seconds(stage: int) -> int:
    return {"normal": 40, "elite": 55, "boss": 45, "regionBoss": 60}[encounter_class(stage)]


def wallet(credits: int, parts: int, circuits: int = 0, alloy: int = 0, star_cores: int = 0) -> dict[str, int]:
    return {
        "credits": credits,
        "parts": parts,
        "circuits": circuits,
        "alloy": alloy,
        "starCores": star_cores,
    }


def economy_contract() -> dict[str, Any]:
    return {
        "currencies": [
            {"id": "credits", "nameKo": "크레딧", "primarySource": "전투·오프라인 파밍", "primarySink": "공구·시설 강화"},
            {"id": "parts", "nameKo": "부품", "primarySource": "괴수 해체", "primarySink": "드론·시설 강화"},
            {"id": "circuits", "nameKo": "회로", "primarySource": "첫 클리어·엘리트", "primarySink": "자동화·드론 해금"},
            {"id": "alloy", "nameKo": "합금", "primarySource": "엘리트·보스 첫 클리어", "primarySink": "상위 설비·출항선"},
            {"id": "starCores", "nameKo": "항성 코어", "primarySource": "S60 지역 보스", "primarySink": "다음 지역 출항"},
        ],
        "enemyPartRewards": {"normal": 3, "elite": 6, "boss": 15},
        "offline": {"efficiencyPpm": 700_000, "cycleSeconds": 75, "freeCapSeconds": 28_800},
        "launch": {"requiredStage": 60, "cost": wallet(40_000_000, 2_400, 40, 20, 1)},
        "upgradeSinks": [
            {"id": "cutter_2", "nameKo": "절단기 Mk.2", "cost": wallet(200, 40)},
            {"id": "rivet_2", "nameKo": "리벳 출력 강화", "cost": wallet(800, 100, 3)},
            {"id": "sorter_repair", "nameKo": "자동 선별기 복구", "cost": wallet(2_500, 250, 5, 1)},
            {"id": "cutter_3", "nameKo": "절단기 Mk.3", "cost": wallet(8_000, 600, 8, 2)},
            {"id": "spark_drone", "nameKo": "스파크 드론 조립", "cost": wallet(20_000, 1_000, 12, 3)},
            {"id": "warehouse", "nameKo": "궤도 창고 증축", "cost": wallet(60_000, 1_200, 10, 4)},
        ],
    }


def build() -> dict[str, Any]:
    source = json.loads(CONTENT_PATH.read_text(encoding="utf-8"))
    getcontext().prec = 50
    preserved = {stage["number"]: stage for stage in source["stages"] if stage["number"] <= 20}
    stages: list[dict[str, Any]] = []

    for number in range(1, REGION_END + 1):
        base_hp = int((Decimal(50) * Decimal("1.105") ** (number - 1)).quantize(Decimal(1), rounding=ROUND_HALF_UP))
        base_reward = int((Decimal(10) * Decimal("1.095") ** (number - 1)).quantize(Decimal(1), rounding=ROUND_HALF_UP))
        if number in preserved:
            stage = dict(preserved[number])
        else:
            stage = {
                "number": number,
                "baseHp": base_hp,
                "baseReward": base_reward,
                "wave": wave_for(number),
                "rewardMultiplierPpm": reward_multiplier(number),
            }
            if number % 10 == 0:
                stage["bossTier"] = number // 10
                stage["timeLimitMs"] = 60_000 if number == REGION_END else 45_000
        stage["encounterClass"] = encounter_class(number)
        stage["expectedClearSeconds"] = expected_clear_seconds(number)
        stage["firstClearReward"] = first_clear_reward(number)
        stages.append(stage)

    source["contentVersion"] = "0.2.0"
    source["slice"]["stageEnd"] = REGION_END
    source["stages"] = stages
    source["economy"] = economy_contract()
    return source


def main() -> None:
    CONTENT_PATH.write_text(json.dumps(build(), ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
