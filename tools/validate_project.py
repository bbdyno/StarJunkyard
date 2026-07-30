#!/usr/bin/env python3
"""Validate shared StarJunkyard contracts without third-party packages."""

from __future__ import annotations

import argparse
import hashlib
import json
import struct
import sys
import zlib
from datetime import datetime, timedelta, timezone
from decimal import Decimal, ROUND_HALF_UP, getcontext
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
COMMON_DIRS = ("content", "schemas", "golden", "art-source", "art-export", "tools")
RUNTIME_SUFFIXES = {".swift", ".kt", ".kts", ".java", ".m", ".mm", ".cpp", ".c"}
EXPECTED_REGIONS = {
    "r01": {
        "name": "끝골목 폐기장",
        "palette": ["#2B303B", "#70453A", "#C06C45", "#7D8F58"],
        "names": ["캔벌레", "우산게", "선풍기박쥐", "냉장고멧돼지", "자판기기사", "폐타이어 투우사", "압착왕 캔크랩", "골목 포식차"],
        "behaviors": ["구름", "우산 방패", "팬 밀침", "문 돌진", "상품 버튼 순서로 장갑 해제", "타이어 세 개를 차례로 굴림", "집게 방패 뒤 캔 투척", "돌진 뒤 폐품 흡입"],
    },
    "r02": {
        "name": "폐쇄된 메가몰",
        "palette": ["#301E3A", "#D14D87", "#57C7B6", "#E8D7A3"],
        "names": ["쇼핑카트사슴", "마네킹문어", "키오스크거북", "청소기달팽이", "에스컬레이터지네", "보안셔터공작", "광고탑 하이드라", "몰의 빈 왕좌"],
        "behaviors": ["바퀴가 네 단계로 가속", "소매가 다른 공격 팔 교체", "오류 화면 방패", "해체 파편 흡입", "몸 마디가 역순 파괴", "좌우 셔터 모터를 교대로 노출", "세 간판 눈부심과 문구 교체", "마네킹 소환과 회전문"],
    },
    "r03": {
        "name": "막차 없는 지하철",
        "palette": ["#111D33", "#E4572E", "#F3A712", "#7B8794"],
        "names": ["표딱지쥐", "형광등뱀", "좌석갑옷", "환풍기해파리", "개찰구견", "노선도거미", "막차 기관수", "개찰구 케르베로스"],
        "behaviors": ["세 마리 군집", "두 관이 교대 점멸", "좌석을 접어 장갑 전환", "환풍으로 부유", "세 머리 신호 속성 순환", "노선도 실로 공격 경로 전환", "선로 돌진과 신호 변경", "세 게이트 물기와 표 검사"],
    },
    "r04": {
        "name": "침몰선 묘지",
        "palette": ["#0D2B45", "#176B87", "#35A7A0", "#F07167"],
        "names": ["앵커게", "구명환복어", "전구아귀", "컨테이너소라", "크레인문어", "부표등대기사", "침몰 컨테이너 고래", "무명 함선의 심장"],
        "behaviors": ["체인 세 칸으로 지면 고정", "구명환 장갑 팽창", "전구 미끼로 암전", "상자 방패 전개", "네 암 중 공격 암 선택 절단", "회전등으로 표적 잠금", "물살과 상자 분출", "압력 맥박과 암전"],
    },
    "r05": {
        "name": "궤도 잔해권",
        "palette": ["#090B1A", "#4A4E9B", "#8C6ED9", "#D8F3FF"],
        "names": ["패널나비", "안테나사마귀", "캡슐거북", "로켓두더지", "도킹골렘", "접시안테나불가사리", "태양돛 가오리", "궤도 쓰레기 용"],
        "behaviors": ["태양 패널 반사", "안테나 집게 빔", "재진입 가열 돌진", "잔해 뒤 잠복", "좌우 도킹 암 동시 파괴", "다섯 접시로 빔 반사", "반사 날개와 태양광 빔", "패널 날개와 잔해 유성"],
    },
    "r06": {
        "name": "버려진 달 도시와 기계 행성",
        "palette": ["#17121F", "#6B5B3E", "#D9B44A", "#E45A9D"],
        "names": ["월면버스풍뎅이", "산소통양", "톱니꽃", "기록관거인", "시간압축기", "기억소각사서", "역행 시계탑", "최종 처리 규약"],
        "behaviors": ["저중력 점프", "압력 돌진", "톱니 꽃잎 재조립", "직전 공격 기록 복제", "공격 간격 1배와 2배 교대", "기록 한 줄씩 소각해 강화 제거", "5초 전 공격 복제와 시곗바늘 쓸기", "분류 삭제·시간 역전·백지화 3단계"],
    },
}
STRICT_WORLD_ASSET_IDS = {
    "boss_alley_devourer",
    "elite_tire_matador",
    "enemy_cart_deer",
    "enemy_mannequin_octopus",
    "enemy_kiosk_turtle",
    "enemy_vacuum_snail",
    "elite_escalator_centipede",
    "elite_shutter_peacock",
    "boss_billboard_hydra",
    "boss_empty_throne",
}


class ContractError(ValueError):
    pass


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ContractError(message)


def load_json(relative_path: str | Path) -> dict[str, Any]:
    path = ROOT / relative_path
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise ContractError(f"cannot load JSON {relative_path}: {error}") from error
    require(isinstance(value, dict), f"{relative_path} must contain a JSON object")
    return value


def canonical_digest(value: Any) -> str:
    payload = json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()


def load_palette(relative_path: str | Path, expected_count: int = 16) -> set[tuple[int, int, int]]:
    colors: set[tuple[int, int, int]] = set()
    for line in (ROOT / relative_path).read_text(encoding="utf-8").splitlines():
        fields = line.strip().split()
        if len(fields) >= 3 and all(field.isdigit() for field in fields[:3]):
            color = tuple(int(field) for field in fields[:3])
            require(all(0 <= channel <= 255 for channel in color), f"invalid palette color: {line}")
            colors.add(color)
    require(len(colors) == expected_count, f"{relative_path} must have exactly {expected_count} colors, found {len(colors)}")
    return colors


def _paeth(left: int, up: int, upper_left: int) -> int:
    prediction = left + up - upper_left
    distances = (abs(prediction - left), abs(prediction - up), abs(prediction - upper_left))
    return (left, up, upper_left)[distances.index(min(distances))]


def read_png_pixels(path: Path) -> tuple[int, int, set[tuple[int, int, int]], bool]:
    """Decode non-interlaced 8-bit RGB/RGBA/indexed PNGs for palette validation."""

    data = path.read_bytes()
    require(data.startswith(b"\x89PNG\r\n\x1a\n"), f"{path} is not a PNG")
    offset = 8
    width = height = bit_depth = color_type = interlace = -1
    palette: list[tuple[int, int, int]] = []
    transparency = b""
    compressed = bytearray()

    while offset < len(data):
        require(offset + 12 <= len(data), f"truncated PNG chunk in {path}")
        length = struct.unpack(">I", data[offset : offset + 4])[0]
        chunk_type = data[offset + 4 : offset + 8]
        chunk_data = data[offset + 8 : offset + 8 + length]
        require(offset + 12 + length <= len(data), f"truncated PNG payload in {path}")
        if chunk_type == b"IHDR":
            width, height, bit_depth, color_type, _, _, interlace = struct.unpack(">IIBBBBB", chunk_data)
        elif chunk_type == b"PLTE":
            require(len(chunk_data) % 3 == 0, f"invalid PLTE in {path}")
            palette = [tuple(chunk_data[index : index + 3]) for index in range(0, len(chunk_data), 3)]
        elif chunk_type == b"tRNS":
            transparency = bytes(chunk_data)
        elif chunk_type == b"IDAT":
            compressed.extend(chunk_data)
        elif chunk_type == b"IEND":
            break
        offset += length + 12

    require(width > 0 and height > 0, f"missing IHDR in {path}")
    require(bit_depth == 8, f"{path} must use 8-bit channels")
    require(interlace == 0, f"{path} must be non-interlaced")
    require(color_type in (2, 3, 6), f"{path} must be RGB, indexed, or RGBA")
    channels = {2: 3, 3: 1, 6: 4}[color_type]
    row_size = width * channels
    raw = zlib.decompress(bytes(compressed))
    require(len(raw) == height * (row_size + 1), f"unexpected decompressed size in {path}")

    previous = bytearray(row_size)
    rows: list[bytearray] = []
    cursor = 0
    for _ in range(height):
        filter_type = raw[cursor]
        cursor += 1
        encoded = raw[cursor : cursor + row_size]
        cursor += row_size
        require(filter_type <= 4, f"unsupported PNG filter {filter_type} in {path}")
        decoded = bytearray(row_size)
        for index, value in enumerate(encoded):
            left = decoded[index - channels] if index >= channels else 0
            up = previous[index]
            upper_left = previous[index - channels] if index >= channels else 0
            predictor = (0, left, up, (left + up) // 2, _paeth(left, up, upper_left))[filter_type]
            decoded[index] = (value + predictor) & 0xFF
        rows.append(decoded)
        previous = decoded

    colors: set[tuple[int, int, int]] = set()
    has_partial_alpha = False
    for row in rows:
        for index in range(0, len(row), channels):
            if color_type == 2:
                red, green, blue = row[index : index + 3]
                alpha = 255
            elif color_type == 6:
                red, green, blue, alpha = row[index : index + 4]
            else:
                palette_index = row[index]
                require(palette_index < len(palette), f"palette index out of range in {path}")
                red, green, blue = palette[palette_index]
                alpha = transparency[palette_index] if palette_index < len(transparency) else 255
            has_partial_alpha |= alpha not in (0, 255)
            if alpha != 0:
                colors.add((red, green, blue))
    return width, height, colors, has_partial_alpha


def validate_schema_documents() -> None:
    identifiers: set[str] = set()
    for path in sorted((ROOT / "schemas").glob("*.schema.json")):
        schema = load_json(path.relative_to(ROOT))
        require(schema.get("$schema") == "https://json-schema.org/draft/2020-12/schema", f"{path.name}: unsupported draft")
        identifier = schema.get("$id")
        require(isinstance(identifier, str) and identifier, f"{path.name}: missing $id")
        require(identifier not in identifiers, f"duplicate schema $id: {identifier}")
        identifiers.add(identifier)
    require(len(identifiers) >= 3, "content, asset, and golden schemas are required")


def validate_content(content: dict[str, Any], manifest: dict[str, Any]) -> set[str]:
    require(content.get("schemaVersion") == manifest.get("schemaVersion") == 2, "schema version mismatch")
    require(content.get("contentVersion") == manifest.get("contentVersion"), "content version mismatch")
    slice_data = content["slice"]
    stages = content["stages"]
    expected_numbers = list(range(slice_data["stageStart"], slice_data["stageEnd"] + 1))
    actual_numbers = [stage["number"] for stage in stages]
    require(actual_numbers == expected_numbers, "stages must be unique, ordered, and contiguous")
    require(expected_numbers == list(range(1, 361)), "world content must contain exactly S1 through S360")
    require(slice_data.get("productionStageEnd") == 120, "this delivery must close production only through R2 S120")

    enemy_ids = [enemy["id"] for enemy in content["enemies"]]
    require(len(enemy_ids) == len(set(enemy_ids)), "enemy ids must be unique")
    enemy_by_id = {enemy["id"]: enemy for enemy in content["enemies"]}
    class_counts = {
        enemy_class: sum(enemy["class"] == enemy_class for enemy in content["enemies"])
        for enemy_class in ("normal", "elite", "boss")
    }
    require(class_counts == {"normal": 24, "elite": 12, "boss": 12}, f"invalid enemy roster counts: {class_counts}")
    drone_ids = [drone["id"] for drone in content["drones"]]
    require(len(drone_ids) == len(set(drone_ids)), "drone ids must be unique")

    regions = content.get("regions", [])
    require([region["id"] for region in regions] == list(EXPECTED_REGIONS), "regions must be ordered R1 through R6")
    referenced_enemy_ids: set[str] = set()
    for index, region in enumerate(regions, start=1):
        expected = EXPECTED_REGIONS[region["id"]]
        require(region["number"] == index, f"{region['id']}: invalid region number")
        require(region["stageStart"] == (index - 1) * 60 + 1 and region["stageEnd"] == index * 60, f"{region['id']}: invalid stage range")
        require(region["nameKo"] == expected["name"], f"{region['id']}: GDD region name drift")
        require(region["palette"] == expected["palette"], f"{region['id']}: GDD palette drift")
        roster_ids = [*region["enemyIds"], *region["eliteIds"], region["midBossId"], region["regionBossId"]]
        require(len(roster_ids) == len(set(roster_ids)) == 8, f"{region['id']}: needs four normal, two elites, and two bosses")
        roster = [enemy_by_id[enemy_id] for enemy_id in roster_ids]
        require([enemy["nameKo"] for enemy in roster] == expected["names"], f"{region['id']}: GDD enemy name drift")
        require([enemy["behaviorKo"] for enemy in roster] == expected["behaviors"], f"{region['id']}: GDD behavior drift")
        require([enemy["class"] for enemy in roster] == ["normal"] * 4 + ["elite", "elite", "boss", "boss"], f"{region['id']}: roster classes are invalid")
        require(all(enemy["regionId"] == region["id"] for enemy in roster), f"{region['id']}: cross-region enemy")
        require(roster[-2].get("bossRole") == "mid" and roster[-1].get("bossRole") == "region", f"{region['id']}: boss roles are invalid")
        require(all(enemy.get("behaviorId") and enemy.get("breakSequenceKo") for enemy in roster), f"{region['id']}: behavior or break sequence missing")
        require(all(enemy.get("weakness") in {"cut", "impact", "heat", "electric", "cooling"} for enemy in roster), f"{region['id']}: weakness missing")
        if region["stageEnd"] <= slice_data["productionStageEnd"]:
            require(region.get("backgroundSpriteId"), f"{region['id']}: production region background missing")
            require(all(enemy["assetStatus"] == "production_ready" and enemy.get("spriteId") for enemy in roster), f"{region['id']}: production roster is incomplete")
        else:
            require(all(enemy["assetStatus"] == "contract_only" and enemy.get("spriteId") is None for enemy in roster), f"{region['id']}: unfinished art must remain contract_only")
        referenced_enemy_ids.update(roster_ids)
    require(referenced_enemy_ids == set(enemy_ids), "region rosters and enemy catalog differ")

    getcontext().prec = 50
    wave_references: set[str] = set()
    normal_signatures: list[tuple[str, ...] | None] = []
    for stage in stages:
        number = stage["number"]
        region_number = (number - 1) // 60 + 1
        region_id = f"r{region_number:02d}"
        local_stage = (number - 1) % 60 + 1
        require(stage["regionId"] == region_id and stage["localStage"] == local_stage, f"stage {number}: region mapping mismatch")
        expected_hp = int((Decimal(50) * Decimal("1.105") ** (number - 1)).quantize(Decimal(1), rounding=ROUND_HALF_UP))
        expected_reward = int((Decimal(10) * Decimal("1.095") ** (number - 1)).quantize(Decimal(1), rounding=ROUND_HALF_UP))
        require(stage["baseHp"] == expected_hp, f"stage {number}: baseHp must be precomputed as {expected_hp}")
        require(stage["baseReward"] == expected_reward, f"stage {number}: baseReward must be precomputed as {expected_reward}")
        require(all(enemy_id in enemy_by_id for enemy_id in stage["wave"]), f"stage {number}: unknown enemy id")
        wave_references.update(stage["wave"])
        elite_offsets = {5, 15, 25, 35, 50, 55} if region_number == 2 else {5, 15, 25, 35, 45, 55}
        expected_encounter = "regionBoss" if local_stage == 60 else "boss" if local_stage % 10 == 0 and not (region_number == 2 and local_stage == 50) else "elite" if local_stage in elite_offsets else "normal"
        require(stage.get("encounterClass") == expected_encounter, f"stage {number}: expected {expected_encounter}")
        first_clear = stage.get("firstClearReward", {})
        require(
            set(first_clear) == {"credits", "parts", "circuits", "alloy", "starCores"}
            and all(isinstance(value, int) and value >= 0 for value in first_clear.values()),
            f"stage {number}: invalid first-clear wallet",
        )
        require(first_clear["credits"] == first_clear["parts"] == 0, f"stage {number}: repeat currencies cannot be first-clear rewards")
        expected_cores = region_number if expected_encounter == "regionBoss" else 0
        require(first_clear["starCores"] == expected_cores, f"stage {number}: star core source must be the region boss")
        require(10 <= stage.get("expectedClearSeconds", 0) <= 300, f"stage {number}: invalid clear-time budget")
        if expected_encounter in {"boss", "regionBoss"}:
            require(len(stage["wave"]) == 1, f"stage {number}: boss stage must contain one enemy")
            require(enemy_by_id[stage["wave"][0]]["class"] == "boss", f"stage {number}: wave is not a boss")
            boss_enemy = enemy_by_id[stage["wave"][0]]
            expected_limit = boss_enemy["timeLimitMs"]
            require(stage.get("timeLimitMs") == expected_limit, f"stage {number}: boss limit must be {expected_limit}ms")
            require(
                stage["expectedClearSeconds"] * 1000 <= expected_limit,
                f"stage {number}: expected clear time exceeds its combat limit",
            )
            require(stage.get("bossTier") == number // 10, f"stage {number}: invalid boss tier")
        else:
            require("bossTier" not in stage and "timeLimitMs" not in stage, f"stage {number}: non-boss has boss fields")
            expected_count = 7 if expected_encounter == "elite" else 8
            require(len(stage["wave"]) == expected_count, f"stage {number}: expected {expected_count} enemies")
            enemy_classes = [enemy_by_id[enemy_id]["class"] for enemy_id in stage["wave"]]
            if expected_encounter == "elite":
                require(enemy_classes.count("elite") == 1, f"stage {number}: elite stage needs exactly one elite")
            else:
                require(all(enemy_class == "normal" for enemy_class in enemy_classes), f"stage {number}: normal stage has special enemy")
        signature = tuple(stage["wave"]) if expected_encounter == "normal" else None
        normal_signatures.append(signature)
        if len(normal_signatures) >= 3 and signature is not None:
            require(not (normal_signatures[-2] == signature == normal_signatures[-3]), f"stage {number}: same normal wave repeated three times")

    require(wave_references == set(enemy_ids), "every catalog enemy must appear in at least one stage")
    for region in regions:
        for elite_id in region["eliteIds"]:
            elite_appearances = sum(elite_id in stage["wave"] for stage in stages if stage["regionId"] == region["id"])
            require(elite_appearances == 3, f"{region['id']}: each elite must appear exactly three times")

    validate_economy(content["economy"], [stage for stage in stages if stage["number"] <= 60], 60)

    sprite_ids = {content["player"]["spriteId"]}
    sprite_ids.update(drone["spriteId"] for drone in content["drones"])
    sprite_ids.update(enemy["spriteId"] for enemy in content["enemies"] if enemy.get("spriteId"))
    sprite_ids.update(region["backgroundSpriteId"] for region in regions if region.get("backgroundSpriteId"))
    return sprite_ids


def validate_economy(economy: dict[str, Any], stages: list[dict[str, Any]], region_end: int) -> None:
    currency_ids = [currency["id"] for currency in economy.get("currencies", [])]
    expected_currencies = {"credits", "parts", "circuits", "alloy", "starCores"}
    require(len(currency_ids) == 5 and set(currency_ids) == expected_currencies, "economy must define five unique currencies")
    require(
        all(currency.get("primarySource") and currency.get("primarySink") for currency in economy["currencies"]),
        "every currency needs a documented source and sink",
    )
    parts = economy.get("enemyPartRewards", {})
    require(set(parts) == {"normal", "elite", "boss"}, "enemy part reward classes are incomplete")
    require(0 < parts["normal"] < parts["elite"] < parts["boss"], "part rewards must grow normal < elite < boss")

    offline = economy.get("offline", {})
    require(offline.get("efficiencyPpm") == 700_000, "offline farming must be exactly 70% efficient")
    require(offline.get("cycleSeconds", 0) > 0, "offline cycle must be positive")
    require(offline.get("freeCapSeconds") == 8 * 60 * 60, "free offline cap must be eight hours")

    launch = economy.get("launch", {})
    require(launch.get("requiredStage") == region_end, "launch must require the R1 region boss")
    launch_cost = launch.get("cost", {})
    require(set(launch_cost) == expected_currencies, "launch cost must use the complete wallet contract")
    require(all(launch_cost[currency] > 0 for currency in expected_currencies), "launch must sink all five currencies")

    sinks = economy.get("upgradeSinks", [])
    sink_ids = [sink["id"] for sink in sinks]
    require(sinks and len(sink_ids) == len(set(sink_ids)), "upgrade sink ids must be non-empty and unique")
    require(
        all(set(sink.get("cost", {})) == expected_currencies for sink in sinks),
        "every upgrade sink must use the complete wallet contract",
    )
    for currency in ("circuits", "alloy", "starCores"):
        total_source = sum(stage["firstClearReward"][currency] for stage in stages)
        total_sink = launch_cost[currency] + sum(sink["cost"][currency] for sink in sinks)
        require(total_source >= total_sink, f"R1 first clears cannot fund all {currency} progression sinks")


def validate_assets(
    asset_manifest: dict[str, Any],
    required_ids: set[str],
    palettes: dict[str, set[tuple[int, int, int]]],
    release: bool,
) -> None:
    require(asset_manifest.get("logicalViewport") == [360, 800], "asset viewport must be 360x800 portrait")
    assets = asset_manifest.get("assets", [])
    asset_ids = [asset["id"] for asset in assets]
    require(len(asset_ids) == len(set(asset_ids)), "asset ids must be unique")
    require(required_ids <= set(asset_ids), f"missing asset ids: {sorted(required_ids - set(asset_ids))}")
    require("background_r01_back_alley" in asset_ids, "R1 combat background is missing")
    require("crew_bora_base" in asset_ids, "Bora crew sprite is missing")
    profiles = asset_manifest.get("animationProfiles", {})
    require(profiles.get("actor_mo_base", {}).get("attackFrames") == 4, "Mo needs four attack steps")
    require(profiles.get("drone_riv0_base", {}).get("hoverFrames") == 4, "Rivet needs four hover steps")
    require(profiles.get("crew_bora_base", {}).get("attackFrames") == 4, "Bora needs four attack steps")
    require(profiles.get("enemy_normal", {}).get("hitFrames") == 3, "normal enemies need three hit steps")
    allowed_canvas: dict[str, set[tuple[int, int]]] = {
        "actor": {(48, 64)},
        "drone": {(32, 32), (48, 40)},
        "enemy_small": {(32, 32)},
        "enemy_medium": {(48, 48)},
        "enemy_large": {(64, 64)},
        "enemy_wide": {(64, 48)},
    }

    for asset in assets:
        identifier = asset["id"]
        canvas = tuple(asset["canvas"])
        pivot = tuple(asset["pivot"])
        require(asset["scalePolicy"] == "integer_nearest", f"{identifier}: nearest integer scaling required")
        require(all(isinstance(value, int) for value in (*canvas, *pivot)), f"{identifier}: canvas and pivot must be integer")
        require(0 <= pivot[0] <= canvas[0] and 0 <= pivot[1] <= canvas[1], f"{identifier}: pivot outside canvas")
        if asset["kind"] in allowed_canvas:
            require(canvas in allowed_canvas[asset["kind"]], f"{identifier}: invalid canvas {canvas}")
        if asset["kind"] == "boss":
            require(80 <= canvas[0] <= 288 and 80 <= canvas[1] <= 224, f"{identifier}: boss canvas outside budget")

        status = asset["status"]
        if release:
            require(status == "production_ready", f"{identifier}: {status} asset cannot enter a release build")
        if status == "production_ready":
            require("file" in asset and "sha256" in asset, f"{identifier}: production asset needs file and sha256")
            relative_file = Path(asset["file"])
            require(not relative_file.is_absolute() and ".." not in relative_file.parts, f"{identifier}: unsafe asset path")
            path = ROOT / relative_file
            require(path.is_file(), f"{identifier}: missing {relative_file}")
            require(hashlib.sha256(path.read_bytes()).hexdigest() == asset["sha256"], f"{identifier}: sha256 mismatch")
            width, height, colors, has_partial_alpha = read_png_pixels(path)
            require((width, height) == canvas, f"{identifier}: PNG canvas does not match manifest")
            require(not has_partial_alpha, f"{identifier}: anti-aliased partial alpha is forbidden")
            palette_id = asset.get("paletteId", asset_manifest["paletteId"])
            require(palette_id in palettes, f"{identifier}: unknown palette {palette_id}")
            palette = palettes[palette_id]
            require(colors <= palette, f"{identifier}: colors outside {palette_id}: {sorted(colors - palette)}")
            if identifier in STRICT_WORLD_ASSET_IDS:
                color_budget = 18 if asset["kind"] == "boss" else 12
                require(len(colors) <= color_budget, f"{identifier}: uses {len(colors)} colors, limit is {color_budget}")
            require((0, 255, 0) not in colors, f"{identifier}: chroma fringe reached production output")


def validate_golden(manifest: dict[str, Any], content: dict[str, Any]) -> None:
    valid_stages = {stage["number"] for stage in content["stages"]}
    for relative_path in manifest["goldenFiles"]:
        fixture = load_json(relative_path)
        require(fixture.get("schemaVersion") == 1, f"{relative_path}: schema version mismatch")
        require(fixture.get("contentVersion") == manifest["contentVersion"], f"{relative_path}: content version mismatch")
        require(fixture["input"]["stage"] in valid_stages, f"{relative_path}: stage outside content")
        digest = canonical_digest(fixture["expectedState"])
        require(fixture.get("expectedDigest") == digest, f"{relative_path}: expected digest is {digest}")


def validate_economy_golden(manifest: dict[str, Any]) -> None:
    paths = manifest.get("economyGoldenFiles", [])
    require(len(paths) == 2, "30-minute and first-day economy fixtures are required")
    fixture_ids: set[str] = set()
    for relative_path in paths:
        fixture = load_json(relative_path)
        require(fixture.get("schemaVersion") == 1, f"{relative_path}: schema version mismatch")
        require(fixture.get("contentVersion") == manifest["contentVersion"], f"{relative_path}: content version mismatch")
        fixture_id = fixture.get("fixtureId")
        require(isinstance(fixture_id, str) and fixture_id not in fixture_ids, f"{relative_path}: duplicate fixture id")
        fixture_ids.add(fixture_id)
        digest = canonical_digest(fixture["expectedState"])
        require(fixture.get("expectedDigest") == digest, f"{relative_path}: expected digest is {digest}")


def validate_region_economy_golden(manifest: dict[str, Any], content: dict[str, Any]) -> None:
    paths = manifest.get("regionEconomyGoldenFiles", [])
    require(len(paths) == 6, "one regional economy Golden fixture is required for each of R1-R6")
    expected_region_ids = [f"r{number:02d}" for number in range(1, 7)]
    actual_region_ids: list[str] = []
    for relative_path in paths:
        fixture = load_json(relative_path)
        require(fixture.get("schemaVersion") == 1, f"{relative_path}: schema version mismatch")
        require(fixture.get("contentVersion") == manifest["contentVersion"], f"{relative_path}: content version mismatch")
        region_id = fixture.get("regionId")
        actual_region_ids.append(region_id)
        state = fixture.get("expectedState", {})
        require(state.get("regionId") == region_id, f"{relative_path}: region state mismatch")
        require(state.get("uniqueEnemyCount") == 8, f"{relative_path}: regional roster must include eight enemies")
        expected_production_assets = 8 if region_id in {"r01", "r02"} else 0
        require(state.get("productionAssetCount") == expected_production_assets, f"{relative_path}: production asset count mismatch")
        digest = canonical_digest(state)
        require(fixture.get("expectedDigest") == digest, f"{relative_path}: expected digest is {digest}")
    require(actual_region_ids == expected_region_ids, "regional economy Goldens must be ordered R1-R6")


def validate_ios_iap_catalog() -> int:
    catalog = load_json("content/ios-iap-catalog.json")
    require(catalog.get("schemaVersion") == 1, "iOS IAP catalog schema mismatch")
    require(catalog.get("platform") == "ios", "IAP catalog must be iOS-only")
    target = Decimal(str(catalog["speedMultiplierTarget"]))
    hard_cap = Decimal(str(catalog["speedMultiplierHardCap"]))
    require(Decimal("1") <= target <= hard_cap < Decimal("2"), "paid speed limits must stay below 2x")
    products = catalog.get("products", [])
    identifiers = [product["id"] for product in products]
    require(len(identifiers) == len(set(identifiers)), "IAP product ids must be unique")
    require(all(identifier.startswith("com.bbdyno.starjunkyard.") for identifier in identifiers), "invalid IAP product prefix")
    allowed_types = {"non_consumable", "auto_renewable_subscription"}
    require(all(product["type"] in allowed_types for product in products), "unsupported launch IAP type")

    storekit = load_json("StarJunkyard/StarJunkyard.storekit")
    configured_products = storekit.get("products", [])
    configured_subscriptions = [
        subscription
        for group in storekit.get("subscriptionGroups", [])
        for subscription in group.get("subscriptions", [])
    ]
    configured_ids = {
        product["productID"] for product in configured_products + configured_subscriptions
    }
    require(configured_ids == set(identifiers), "StoreKit Configuration product ids must match the iOS IAP catalog")
    expected_non_consumables = {
        product["id"] for product in products if product["type"] == "non_consumable"
    }
    actual_non_consumables = {
        product["productID"] for product in configured_products if product.get("type") == "NonConsumable"
    }
    require(actual_non_consumables == expected_non_consumables, "StoreKit non-consumable types do not match the catalog")
    expected_subscriptions = {
        product["id"] for product in products if product["type"] == "auto_renewable_subscription"
    }
    actual_subscriptions = {
        product["productID"] for product in configured_subscriptions if product.get("type") == "RecurringSubscription"
    }
    require(actual_subscriptions == expected_subscriptions, "StoreKit subscription types do not match the catalog")
    return len(products)


def _utc_date(value: Any, label: str) -> datetime:
    require(isinstance(value, str) and value.endswith("Z"), f"{label} must be an explicit UTC timestamp")
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError as error:
        raise ContractError(f"{label} is not an ISO-8601 timestamp") from error
    require(parsed.tzinfo == timezone.utc, f"{label} must use UTC")
    return parsed


def validate_season_definition(season: dict[str, Any], label: str) -> tuple[datetime, datetime]:
    require(season.get("schemaVersion") == 1, f"{label}: schema version mismatch")
    content_version = season.get("contentVersion")
    require(isinstance(content_version, str) and len(content_version.split(".")) == 3 and
            all(part.isdigit() for part in content_version.split(".")),
            f"{label}: semantic content version is required")
    season_id = season.get("seasonID")
    require(isinstance(season_id, str) and season_id.startswith("season_"), f"{label}: invalid season id")
    starts_at = _utc_date(season.get("startsAt"), f"{label}.startsAt")
    ends_at = _utc_date(season.get("endsAt"), f"{label}.endsAt")
    require(ends_at - starts_at == timedelta(weeks=8), f"{label}: season must last exactly eight weeks")
    require(season.get("weeklyXPCap") == 2500, f"{label}: weekly play XP cap must be 2500")
    require(isinstance(season.get("selectionSeed"), int) and season["selectionSeed"] > 0,
            f"{label}: selection seed must be positive")
    require(isinstance(season.get("codexEntryID"), str) and season["codexEntryID"],
            f"{label}: post-season codex entry is required")

    allowed_metrics = {
        "dismantle_enemy", "salvage_part", "manual_salvage", "crew_attack",
        "clear_stage", "facility_job", "defeat_boss", "expedition_complete",
    }
    forbidden_terms = ("purchase", "payment", "store", "iap", "advert", "watch_ad", "ad_watch")
    daily = season.get("dailyMissionPool", [])
    weekly = season.get("weeklyMissions", [])
    require(isinstance(daily, list) and len(daily) == 6, f"{label}: daily pool must contain six missions")
    require(isinstance(weekly, list) and len(weekly) == 4, f"{label}: four weekly missions are required")
    missions = daily + weekly
    mission_ids = [mission.get("id") for mission in missions]
    require(len(mission_ids) == len(set(mission_ids)), f"{label}: mission ids must be unique")
    for mission in missions:
        identifier = mission.get("id", "")
        metric = mission.get("metric", "")
        require(metric in allowed_metrics, f"{label}/{identifier}: non-gameplay mission metric {metric!r}")
        searchable = f"{identifier} {metric}".casefold()
        require(not any(term in searchable for term in forbidden_terms),
                f"{label}/{identifier}: payment and advertising missions are forbidden")
        require(isinstance(mission.get("target"), int) and mission["target"] > 0,
                f"{label}/{identifier}: target must be positive")
        require(isinstance(mission.get("xp"), int) and 0 < mission["xp"] <= 500,
                f"{label}/{identifier}: invalid mission XP")
    require(all(mission.get("cadence") == "daily" for mission in daily),
            f"{label}: daily pool cadence mismatch")
    require(all(mission.get("cadence") == "weekly" for mission in weekly),
            f"{label}: weekly cadence mismatch")

    tiers = season.get("rewardTiers", [])
    require(isinstance(tiers, list) and len(tiers) == 40, f"{label}: reward track must have 40 tiers")
    require([tier.get("level") for tier in tiers] == list(range(1, 41)),
            f"{label}: reward tiers must be ordered 1 through 40")
    require([tier.get("xpRequired") for tier in tiers] == [level * 500 for level in range(1, 41)],
            f"{label}: reward tier XP must reach 20000 in 500 XP steps")
    free_kinds = {"currency", "material", "story"}
    premium_kinds = {"cosmetic", "convenience"}
    for tier in tiers:
        level = tier["level"]
        free = tier.get("free", {})
        premium = tier.get("premium", {})
        require(free.get("kind") in free_kinds, f"{label}/tier {level}: invalid free reward")
        require(premium.get("kind") in premium_kinds,
                f"{label}/tier {level}: premium track must remain cosmetic or convenience-only")
        for track, reward in (("free", free), ("premium", premium)):
            require(isinstance(reward.get("itemID"), str) and reward["itemID"],
                    f"{label}/tier {level}: {track} item id is required")
            require(isinstance(reward.get("amount"), int) and reward["amount"] > 0,
                    f"{label}/tier {level}: {track} amount must be positive")
    return starts_at, ends_at


def validate_season_catalog(manifest: dict[str, Any]) -> int:
    files = manifest.get("seasonFiles")
    require(isinstance(files, dict) and set(files) == {"current", "next"},
            "manifest must declare current and next season files")
    current = load_json(files["current"])
    next_season = load_json(files["next"])
    current_start, current_end = validate_season_definition(current, "current season")
    next_start, _ = validate_season_definition(next_season, "next season")
    require(current_end == next_start, "current and next season UTC windows must be contiguous")
    require(current_start < next_start, "next season must start after current season")
    require(current["seasonID"] != next_season["seasonID"], "season ids must be unique")
    require(current["codexEntryID"] != next_season["codexEntryID"], "season codex entries must be unique")
    return 2


def validate_no_shared_runtime() -> None:
    violations: list[str] = []
    for directory in COMMON_DIRS:
        for path in (ROOT / directory).rglob("*"):
            if path.is_file() and path.suffix in RUNTIME_SUFFIXES:
                violations.append(str(path.relative_to(ROOT)))
    require(not violations, f"shared runtime code is forbidden: {violations}")


def validate_project(release: bool = False) -> list[str]:
    manifest = load_json("content/manifest.json")
    require(manifest.get("logicalViewport") == {"width": 360, "height": 800, "orientation": "portrait"}, "manifest viewport mismatch")
    require(len(manifest.get("contentFiles", [])) == 1, "vertical slice must have one content entrypoint")
    content = load_json(manifest["contentFiles"][0])
    asset_manifest = load_json(manifest["assetManifest"])
    palette_files = asset_manifest.get("paletteFiles", {})
    require(palette_files.get("common16") == manifest["palette"], "common palette path mismatch")
    palettes = {
        "common16": load_palette(palette_files["common16"], expected_count=16),
        "r02_mall12": load_palette(palette_files["r02_mall12"], expected_count=12),
    }

    validate_schema_documents()
    required_ids = validate_content(content, manifest)
    validate_assets(asset_manifest, required_ids, palettes, release)
    validate_golden(manifest, content)
    validate_economy_golden(manifest)
    validate_region_economy_golden(manifest, content)
    iap_count = validate_ios_iap_catalog()
    season_count = validate_season_catalog(manifest)
    validate_no_shared_runtime()
    return [
        f"content {manifest['contentVersion']}",
        f"{len(content['regions'])} regions / {len(content['stages'])} stages",
        f"{len(asset_manifest['assets'])} pixel assets ({'release' if release else 'development'} mode)",
        f"{len(manifest['goldenFiles'])} golden fixtures",
        f"{len(manifest['economyGoldenFiles'])} economy golden fixtures",
        f"{len(manifest['regionEconomyGoldenFiles'])} region economy golden fixtures",
        f"{iap_count} ethical iOS IAP products",
        f"{season_count} validated eight-week seasons",
    ]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--release", action="store_true", help="reject planned and placeholder assets")
    args = parser.parse_args()
    try:
        summary = validate_project(release=args.release)
    except (ContractError, KeyError, TypeError) as error:
        print(f"validation failed: {error}", file=sys.stderr)
        return 1
    print("validation passed: " + ", ".join(summary))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
