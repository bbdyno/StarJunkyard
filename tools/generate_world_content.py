#!/usr/bin/env python3
"""Generate the six-region, 360-stage 1.0 content contract deterministically."""

from __future__ import annotations

import json
from decimal import Decimal, ROUND_HALF_UP, getcontext
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
SOURCE_PATH = ROOT / "content" / "r1_vertical_slice.json"
OUTPUT_PATH = ROOT / "content" / "world_r1_r6.json"
PPM = 1_000_000
CONTENT_VERSION = "0.3.0"


def enemy(
    identifier: str,
    name: str,
    enemy_class: str,
    weakness: str,
    hp: int,
    behavior_id: str,
    behavior: str,
    break_sequence: str,
    sprite_id: str | None = None,
    secondary: tuple[str, ...] = (),
    boss_role: str | None = None,
    time_limit_ms: int | None = None,
) -> dict[str, Any]:
    value: dict[str, Any] = {
        "id": identifier,
        "nameKo": name,
        "class": enemy_class,
        "hpMultiplierPpm": hp,
        "weakness": weakness,
        "secondaryWeaknesses": list(secondary),
        "behaviorId": behavior_id,
        "behaviorKo": behavior,
        "breakSequenceKo": break_sequence,
        "spriteId": sprite_id,
        "assetStatus": "production_ready" if sprite_id else "contract_only",
    }
    if boss_role:
        value["bossRole"] = boss_role
    if time_limit_ms:
        value["timeLimitMs"] = time_limit_ms
    return value


REGIONS: list[dict[str, Any]] = [
    {
        "id": "r01", "number": 1, "nameKo": "끝골목 폐기장", "stages": (1, 60),
        "themeKo": "비 골목, 벽돌·녹·청록", "musicKo": "망치와 로파이",
        "palette": ["#2B303B", "#70453A", "#C06C45", "#7D8F58"],
        "backgroundSpriteId": "background_r01_back_alley", "primaryDropId": "parts",
        "baseFormKo": "손수레 천막에서 컨테이너 작업장으로",
        "arrivalStoryKo": "피난처 7호의 불을 되살리고 끝골목의 폐품을 분류한다.",
        "completionStoryKo": "골목 포식차의 노선표로 출항로를 찾아 폐쇄된 메가몰로 향한다.",
        "nextRegionId": "r02",
        "normals": [
            enemy("can_bug", "캔벌레", "normal", "impact", 1_000_000, "roll_cloud", "구름", "라벨→턱→회전 뚜껑", "enemy_can_bug"),
            enemy("umbrella_crab", "우산게", "normal", "cut", 1_150_000, "umbrella_guard", "우산 방패", "우산살 3개 순차 분리", "enemy_umbrella_crab"),
            enemy("fan_bat", "선풍기박쥐", "normal", "electric", 1_250_000, "fan_knockback", "팬 밀침", "날개→팬축→플러그", "enemy_fan_bat"),
            enemy("fridge_boar", "냉장고멧돼지", "normal", "electric", 1_350_000, "door_charge", "문 돌진", "문→선반→압축기", "enemy_fridge_boar"),
        ],
        "elites": [
            enemy("vending_knight", "자판기기사", "elite", "electric", 6_000_000, "button_armor", "상품 버튼 순서로 장갑 해제", "버튼 3개→전면 장갑→동전 코어", "elite_vending_knight"),
            enemy("tire_matador", "폐타이어 투우사", "elite", "cut", 6_300_000, "rolling_tire_feint", "타이어 세 개를 차례로 굴림", "굴림 타이어 3개→타이어 방패→허브 볼트", "elite_tire_matador"),
        ],
        "midBoss": enemy("cancrab_king", "압착왕 캔크랩", "boss", "impact", 30_000_000, "claw_shield", "집게 방패 뒤 캔 투척", "빛난 집게 볼트 2개→자석 쓸기", "boss_cancrab_king", boss_role="mid", time_limit_ms=45_000),
        "regionBoss": enemy("alley_devourer", "골목 포식차", "boss", "cut", 40_000_000, "charge_inhale", "돌진 뒤 폐품 흡입", "타이어 고정→점선 절단→압축기 인양", "boss_alley_devourer", boss_role="region", time_limit_ms=60_000),
    },
    {
        "id": "r02", "number": 2, "nameKo": "폐쇄된 메가몰", "stages": (61, 120),
        "themeKo": "네온 암전, 자홍·민트·베이지", "musicKo": "뮤작에서 신스로",
        "palette": ["#301E3A", "#D14D87", "#57C7B6", "#E8D7A3"],
        "backgroundSpriteId": "background_r02_closed_megamall", "primaryDropId": "circuits",
        "baseFormKo": "컨테이너 작업장에서 골목 재활용 공장으로",
        "arrivalStoryKo": "출항선이 멈춘 메가몰에 닿고, 버려진 소비 기억에서 회로를 회수한다.",
        "completionStoryKo": "빈 왕좌의 영업을 끝내고 보라와 누리가 골목 재활용 공장을 세운다.",
        "nextRegionId": "r03",
        "normals": [
            enemy("cart_deer", "쇼핑카트사슴", "normal", "impact", 1_450_000, "accelerate", "바퀴가 네 단계로 가속", "앞바퀴→바구니→손잡이 뿔", "enemy_cart_deer"),
            enemy("mannequin_octopus", "마네킹문어", "normal", "cut", 1_550_000, "arm_swap", "소매가 다른 공격 팔 교체", "옷걸이 팔 2개씩→상반신", "enemy_mannequin_octopus"),
            enemy("kiosk_turtle", "키오스크거북", "normal", "electric", 1_650_000, "error_shield", "오류 화면 방패", "화면 균열→영수증→받침", "enemy_kiosk_turtle"),
            enemy("vacuum_snail", "청소기달팽이", "normal", "heat", 1_750_000, "fragment_vacuum", "해체 파편 흡입", "흡입구→호스 목→원반 몸", "enemy_vacuum_snail"),
        ],
        "elites": [
            enemy("escalator_centipede", "에스컬레이터지네", "elite", "electric", 7_000_000, "reverse_segments", "몸 마디가 역순 파괴", "6번 마디부터 1번 마디", "elite_escalator_centipede"),
            enemy("shutter_peacock", "보안셔터공작", "elite", "electric", 7_200_000, "alternating_shutter_motors", "좌우 셔터 모터를 교대로 노출", "자홍 모터→민트 모터→셔터 깃", "elite_shutter_peacock"),
        ],
        "midBoss": enemy("billboard_hydra", "광고탑 하이드라", "boss", "electric", 32_000_000, "three_sign_glare", "세 간판 눈부심과 문구 교체", "전원선 3개를 표시 순서로 절단", "boss_billboard_hydra", boss_role="mid", time_limit_ms=45_000),
        "regionBoss": enemy("empty_mall_throne", "몰의 빈 왕좌", "boss", "heat", 40_000_000, "mannequin_revolving_door", "마네킹 소환과 회전문", "가격표 회로 4개 중 실제 회로 선택", "boss_empty_throne", secondary=("electric",), boss_role="region", time_limit_ms=60_000),
    },
    {
        "id": "r03", "number": 3, "nameKo": "막차 없는 지하철", "stages": (121, 180),
        "themeKo": "터널·신호등, 남색·주황", "musicKo": "레일 퍼커션",
        "palette": ["#111D33", "#E4572E", "#F3A712", "#7B8794"],
        "backgroundSpriteId": None, "primaryDropId": "alloy_recipe",
        "baseFormKo": "재활용 공장이 이동 레일을 얻는다",
        "arrivalStoryKo": "막차가 끊긴 터널에서 돌아오지 못한 물건의 주인을 기록한다.",
        "completionStoryKo": "개찰구의 돌아오는 표가 바다 아래 침몰선 좌표를 가리킨다.",
        "nextRegionId": "r04",
        "normals": [
            enemy("ticket_mouse", "표딱지쥐", "normal", "impact", 1_850_000, "ticket_swarm", "세 마리 군집", "표 귀 펀칭→몸통 분리"),
            enemy("fluorescent_snake", "형광등뱀", "normal", "impact", 1_950_000, "two_step_flicker", "두 관이 교대 점멸", "형광관 1개→안정기 머리"),
            enemy("seat_armor", "좌석갑옷", "normal", "cut", 2_050_000, "seat_fold", "좌석을 접어 장갑 전환", "등받이→방석→프레임"),
            enemy("vent_jellyfish", "환풍기해파리", "normal", "electric", 2_150_000, "vent_float", "환풍으로 부유", "덕트 촉수→팬 코어"),
        ],
        "elites": [
            enemy("turnstile_hound", "개찰구견", "elite", "electric", 7_500_000, "three_signal_heads", "세 머리 신호 속성 순환", "녹색→황색→적색 머리"),
            enemy("route_map_spider", "노선도거미", "elite", "cut", 7_800_000, "reroute_web", "노선도 실로 공격 경로 전환", "환승점 3개→노선 실→중앙 역명판"),
        ],
        "midBoss": enemy("last_train_engineer", "막차 기관수", "boss", "cooling", 33_000_000, "rail_signal_charge", "선로 돌진과 신호 변경", "녹→황→적 타이밍 뒤 차륜 인양", secondary=("impact",), boss_role="mid", time_limit_ms=45_000),
        "regionBoss": enemy("turnstile_cerberus", "개찰구 케르베로스", "boss", "electric", 40_000_000, "three_gate_bite", "세 게이트 물기와 표 검사", "올바른 표를 세 게이트에 순서 배치", boss_role="region", time_limit_ms=60_000),
    },
    {
        "id": "r04", "number": 4, "nameKo": "침몰선 묘지", "stages": (181, 240),
        "themeKo": "수면 단면·녹슨 선체, 군청·산호", "musicKo": "수중 베이스",
        "palette": ["#0D2B45", "#176B87", "#35A7A0", "#F07167"],
        "backgroundSpriteId": None, "primaryDropId": "salvage_relic",
        "baseFormKo": "이동식 대형 분해선 완성",
        "arrivalStoryKo": "이름 없는 선원의 기록을 모으며 침몰한 컨테이너 길을 인양한다.",
        "completionStoryKo": "함선 심장의 박동이 수면 위 분해선을 깨워 궤도 승강로를 연다.",
        "nextRegionId": "r05",
        "normals": [
            enemy("anchor_crab", "앵커게", "normal", "impact", 2_250_000, "chain_anchor", "체인 세 칸으로 지면 고정", "닻 팔→체인→부표 코어"),
            enemy("lifebuoy_puffer", "구명환복어", "normal", "cut", 2_350_000, "lifebuoy_inflate", "구명환 장갑 팽창", "외부 환→밸브→몸통"),
            enemy("bulb_angler", "전구아귀", "normal", "electric", 2_450_000, "blackout_lure", "전구 미끼로 암전", "전구→케이블→배터리"),
            enemy("container_hermit", "컨테이너소라", "normal", "heat", 2_550_000, "container_guard", "상자 방패 전개", "문짝→상자→소라 코어"),
        ],
        "elites": [
            enemy("crane_octopus", "크레인문어", "elite", "cut", 8_000_000, "choose_attack_arm", "네 암 중 공격 암 선택 절단", "표시 암→균형추→회전축"),
            enemy("buoy_lighthouse_knight", "부표등대기사", "elite", "electric", 8_300_000, "rotating_beacon_lock", "회전등으로 표적 잠금", "부표 장갑→회전등→계류 체인"),
        ],
        "midBoss": enemy("sunken_container_whale", "침몰 컨테이너 고래", "boss", "heat", 35_000_000, "current_container_burst", "물살과 상자 분출", "부력 밸브 2개→상자 자석 회수", secondary=("cut",), boss_role="mid", time_limit_ms=45_000),
        "regionBoss": enemy("nameless_ship_heart", "무명 함선의 심장", "boss", "electric", 40_000_000, "pressure_pulse_blackout", "압력 맥박과 암전", "박자 4회 입력 뒤 기억 전구 회수", secondary=("cooling",), boss_role="region", time_limit_ms=60_000),
    },
    {
        "id": "r05", "number": 5, "nameKo": "궤도 잔해권", "stages": (241, 300),
        "themeKo": "지구 호·별·위성, 흑청·백색·보라", "musicKo": "무중력 아르페지오",
        "palette": ["#090B1A", "#4A4E9B", "#8C6ED9", "#D8F3FF"],
        "backgroundSpriteId": None, "primaryDropId": "alien_relic",
        "baseFormKo": "궤도 재활용 정거장 결합",
        "arrivalStoryKo": "지상에서 보낸 마지막 메시지를 따라 분해선이 궤도 잔해권에 결합한다.",
        "completionStoryKo": "미전송 별지도를 복구해 버려진 달 도시의 좌표를 확정한다.",
        "nextRegionId": "r06",
        "normals": [
            enemy("panel_butterfly", "패널나비", "normal", "cooling", 2_650_000, "solar_reflect", "태양 패널 반사", "왼날개→오른날개→광전 코어"),
            enemy("antenna_mantis", "안테나사마귀", "normal", "cut", 2_750_000, "antenna_beam", "안테나 집게 빔", "안테나→집게→송신기"),
            enemy("capsule_turtle", "캡슐거북", "normal", "cooling", 2_850_000, "capsule_reentry", "재진입 가열 돌진", "열차폐판→캡슐 문→코어"),
            enemy("rocket_mole", "로켓두더지", "normal", "electric", 2_950_000, "zero_g_burrow", "잔해 뒤 잠복", "노즐→드릴 코→연료전지"),
        ],
        "elites": [
            enemy("docking_golem", "도킹골렘", "elite", "cut", 8_500_000, "paired_docking_arms", "좌우 도킹 암 동시 파괴", "두 암을 3초 안에→중앙 포트"),
            enemy("dish_starfish", "접시안테나불가사리", "elite", "cooling", 8_800_000, "five_dish_reflection", "다섯 접시로 빔 반사", "접시 5개 각도 정렬→수신 코어"),
        ],
        "midBoss": enemy("solar_sail_ray", "태양돛 가오리", "boss", "cooling", 36_000_000, "reflective_solar_beam", "반사 날개와 태양광 빔", "반사각 날개 선택→패널 접기", secondary=("electric",), boss_role="mid", time_limit_ms=45_000),
        "regionBoss": enemy("orbital_trash_dragon", "궤도 쓰레기 용", "boss", "cut", 40_000_000, "debris_meteor_wings", "패널 날개와 잔해 유성", "날개 패널 3개 순서 절단→중력 갈퀴", boss_role="region", time_limit_ms=60_000),
    },
    {
        "id": "r06", "number": 6, "nameKo": "버려진 달 도시와 기계 행성", "stages": (301, 360),
        "themeKo": "달 골목→행성 내부→백지 처리장, 회색·금·자홍", "musicKo": "전 지역 주제 변주",
        "palette": ["#17121F", "#6B5B3E", "#D9B44A", "#E45A9D"],
        "backgroundSpriteId": None, "primaryDropId": "memory_fragment",
        "baseFormKo": "항성 기지 에필로그",
        "arrivalStoryKo": "달 도시의 폐기 기록을 따라 기계 행성 내부의 백지 처리장으로 내려간다.",
        "completionStoryKo": "폐기 대신 보존을 선택하고 별 모양 나사로 항성 기지의 새 규약을 고정한다.",
        "nextRegionId": None,
        "normals": [
            enemy("lunar_bus_beetle", "월면버스풍뎅이", "normal", "impact", 3_050_000, "low_gravity_jump", "저중력 점프", "버스 지붕→차륜 날개→월면 코어"),
            enemy("oxygen_tank_sheep", "산소통양", "normal", "cut", 3_150_000, "pressure_charge", "압력 돌진", "압력계→산소통 뿔→밸브"),
            enemy("gear_flower", "톱니꽃", "normal", "heat", 3_250_000, "gear_reassemble", "톱니 꽃잎 재조립", "꽃잎 4개 동시 열→중앙 축"),
            enemy("archivist_giant", "기록관거인", "normal", "electric", 3_350_000, "recorded_attack_echo", "직전 공격 기록 복제", "기록판→도장 팔→메모리 코어"),
        ],
        "elites": [
            enemy("time_compressor", "시간압축기", "elite", "impact", 9_000_000, "alternating_time_scale", "공격 간격 1배와 2배 교대", "느린 톱니→빠른 톱니→진자"),
            enemy("memory_incinerator_librarian", "기억소각사서", "elite", "cooling", 9_300_000, "erase_recorded_buff", "기록 한 줄씩 소각해 강화 제거", "소각 서랍 3개→기록 집게→냉각 코어"),
        ],
        "midBoss": enemy("reverse_clock_tower", "역행 시계탑", "boss", "impact", 38_000_000, "five_second_echo", "5초 전 공격 복제와 시곗바늘 쓸기", "정방향 톱니 3개 고정→과거 파편", boss_role="mid", time_limit_ms=60_000),
        "regionBoss": enemy("final_disposal_protocol", "최종 처리 규약", "boss", "electric", 40_000_000, "protocol_three_phase", "분류 삭제·시간 역전·백지화 3단계", "기억 잔해 중 보존 선택→별 나사 장착", secondary=("cut", "impact", "heat", "cooling"), boss_role="region", time_limit_ms=75_000),
    },
]


def encounter_class(region_number: int, local_stage: int) -> str:
    if local_stage == 60:
        return "regionBoss"
    if region_number == 2 and local_stage == 50:
        return "elite"
    if local_stage % 10 == 0:
        return "boss"
    elite_offsets = {5, 15, 25, 35, 45, 55}
    if region_number == 2:
        elite_offsets = {5, 15, 25, 35, 50, 55}
    return "elite" if local_stage in elite_offsets else "normal"


def wave_for(region: dict[str, Any], local_stage: int) -> list[str]:
    encounter = encounter_class(region["number"], local_stage)
    if encounter == "regionBoss":
        return [region["regionBoss"]["id"]]
    if encounter == "boss":
        return [region["midBoss"]["id"]]
    normals = [item["id"] for item in region["normals"]]
    count = 6 if encounter == "elite" else 8
    wave = [normals[(local_stage + offset * 3) % len(normals)] for offset in range(count)]
    if encounter == "elite":
        if region["number"] == 2:
            elite_index = 0 if local_stage in {5, 25, 50} else 1
        else:
            elite_index = 0 if local_stage in {5, 25, 45} else 1
        wave.append(region["elites"][elite_index]["id"])
    return wave


def first_clear_reward(region_number: int, local_stage: int, encounter: str) -> dict[str, int]:
    reward = {"credits": 0, "parts": 0, "circuits": 0, "alloy": 0, "starCores": 0}
    if encounter == "regionBoss":
        reward.update(circuits=20 * region_number, alloy=12 * region_number, starCores=region_number)
    elif encounter == "boss":
        reward.update(circuits=8 * region_number, alloy=4 * region_number)
    elif encounter == "elite":
        reward.update(circuits=3 * region_number, alloy=region_number)
    elif local_stage % 3 == 0:
        reward["circuits"] = region_number
    return reward


def expected_clear_seconds(local_stage: int, encounter: str, limit: int | None = None) -> int:
    if encounter in {"boss", "regionBoss"}:
        return (limit or 45_000) // 1_000
    target = 25 if local_stage <= 20 else 28 if local_stage <= 50 else 32
    return target + (8 if encounter == "elite" else 0)


def stage_contract(region: dict[str, Any], number: int) -> dict[str, Any]:
    local_stage = number - region["stages"][0] + 1
    encounter = encounter_class(region["number"], local_stage)
    getcontext().prec = 50
    base_hp = int((Decimal(50) * Decimal("1.105") ** (number - 1)).quantize(Decimal(1), rounding=ROUND_HALF_UP))
    base_reward = int((Decimal(10) * Decimal("1.095") ** (number - 1)).quantize(Decimal(1), rounding=ROUND_HALF_UP))
    multiplier = {
        "normal": 1_000_000 + number * 15_000,
        "elite": 1_300_000 + number * 20_000,
        "boss": 45_000_000 + region["number"] * 5_000_000,
        "regionBoss": 75_000_000 + region["number"] * 10_000_000,
    }[encounter]
    stage: dict[str, Any] = {
        "number": number,
        "regionId": region["id"],
        "localStage": local_stage,
        "landmarkId": f"{region['id']}_landmark_{(local_stage - 1) // 10 + 1}",
        "baseHp": base_hp,
        "baseReward": base_reward,
        "wave": wave_for(region, local_stage),
        "rewardMultiplierPpm": multiplier,
        "encounterClass": encounter,
        "expectedClearSeconds": expected_clear_seconds(local_stage, encounter),
        "firstClearReward": first_clear_reward(region["number"], local_stage, encounter),
    }
    if local_stage == 1:
        stage["storyBeatId"] = f"{region['id']}_arrival"
    elif local_stage == 30:
        stage["storyBeatId"] = f"{region['id']}_midpoint"
    elif local_stage == 60:
        stage["storyBeatId"] = f"{region['id']}_departure"
    if encounter in {"boss", "regionBoss"}:
        boss = region["regionBoss"] if encounter == "regionBoss" else region["midBoss"]
        stage["bossTier"] = number // 10
        stage["timeLimitMs"] = boss["timeLimitMs"]
        stage["expectedClearSeconds"] = expected_clear_seconds(local_stage, encounter, boss["timeLimitMs"])
    return stage


def serializable_region(region: dict[str, Any]) -> dict[str, Any]:
    return {
        key: value
        for key, value in region.items()
        if key not in {"normals", "elites", "midBoss", "regionBoss", "stages"}
    } | {
        "stageStart": region["stages"][0],
        "stageEnd": region["stages"][1],
        "enemyIds": [item["id"] for item in region["normals"]],
        "eliteIds": [item["id"] for item in region["elites"]],
        "midBossId": region["midBoss"]["id"],
        "regionBossId": region["regionBoss"]["id"],
    }


def build() -> dict[str, Any]:
    source = json.loads(SOURCE_PATH.read_text(encoding="utf-8"))
    enemies: list[dict[str, Any]] = []
    stages: list[dict[str, Any]] = []
    for region in REGIONS:
        for item in [*region["normals"], *region["elites"], region["midBoss"], region["regionBoss"]]:
            enemies.append({"regionId": region["id"], **item})
        stages.extend(stage_contract(region, number) for number in range(region["stages"][0], region["stages"][1] + 1))

    economy = source["economy"]
    economy["launch"]["cost"]["starCores"] = 1
    return {
        "schemaVersion": 2,
        "contentVersion": CONTENT_VERSION,
        "slice": {
            "id": "world_r1_r6_1_0",
            "regionId": "world",
            "stageStart": 1,
            "stageEnd": 360,
            "productionStageEnd": 120,
        },
        "player": source["player"],
        "drones": source["drones"],
        "regions": [serializable_region(region) for region in REGIONS],
        "enemies": enemies,
        "stages": stages,
        "economy": economy,
    }


def main() -> int:
    OUTPUT_PATH.write_text(json.dumps(build(), ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
