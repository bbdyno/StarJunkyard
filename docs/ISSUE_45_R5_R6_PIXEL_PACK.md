# Issue #45 — R5/R6 production pixel pack

## Scope and contract

This isolated pack supplies nine assets per region: four normal monsters, two elites, two bosses, and one portrait battle background. It does not modify the common production manifest, gameplay content, or Swift sources.

- Source contract: `issue-38/content/world_r1_r6.json`
- Locked source SHA-256: `f8922a8ce4d98d01f19477a38b7bb3291c52b20914576a4231067e635818338a`
- Fragment: `art-export/issue-45-r5-r6/manifest-fragment.json`
- Reconstructable ImageGen evidence: `art-source/issue-45-r5-r6/generation-log.json`
- R5 palette: 16 colors including `#090B1A`, `#4A4E9B`, `#8C6ED9`, `#D8F3FF`
- R6 palette: 16 colors including `#17121F`, `#6B5B3E`, `#D9B44A`, `#E45A9D`

Every asset has one distinct built-in ImageGen artifact ID. The generation log records the shared production prompt, style-only references, per-asset prompt delta, and artifact mapping.

## Readable silhouette roster

| Region | Class | Entity | Primary silhouette cue | Canvas |
|---|---|---|---|---:|
| R5 | Normal | 패널나비 | two separately angled solar-panel wings | 48×40 |
| R5 | Normal | 안테나사마귀 | forked mast and two dish-scythe arms | 48×48 |
| R5 | Normal | 캡슐거북 | reentry shell, hatch, and heat shield | 48×48 |
| R5 | Normal | 로켓두더지 | drill nose, shovel claws, and rocket nozzle | 48×48 |
| R5 | Elite | 도킹골렘 | paired clamp arms around a docking port | 64×64 |
| R5 | Elite | 접시안테나불가사리 | exactly five dish-bearing mechanical arms | 64×64 |
| R5 | Boss | 태양돛 가오리 | very wide segmented reflective sails | 192×112 |
| R5 | Boss | 궤도 쓰레기 용 | three solar-panel wing targets and rake tail | 208×160 |
| R5 | Background | 궤도 잔해권 전장 | Earth limb, edge debris, open central lane | 360×572 |
| R6 | Normal | 월면버스풍뎅이 | bus cabin, window row, and six wheel-legs | 64×48 |
| R6 | Normal | 산소통양 | twin tank horns and central pressure gauge | 48×48 |
| R6 | Normal | 톱니꽃 | four gear petals around a hot axle | 48×48 |
| R6 | Normal | 기록관거인 | tablet chest and oversized stamp arm | 64×64 |
| R6 | Elite | 시간압축기 | unequal slow/fast gears and caged pendulum | 64×64 |
| R6 | Elite | 기억소각사서 | three furnace drawers, record clamp, cooling core | 64×64 |
| R6 | Boss | 역행 시계탑 | reverse clock, three gear targets, walking tower | 192×192 |
| R6 | Boss | 최종 처리 규약 | three-tier disposal machine and star-screw socket | 280×220 |
| R6 | Background | 달 도시 백지 처리장 | lunar machine city, distant press, open lane | 360×572 |

## Elite stage allocation

The two exact Issue #38 elites alternate instead of repeating one elite at every checkpoint.

| Region | Local stage | Global stage | Elite |
|---|---:|---:|---|
| R5 | 5 / 25 / 45 | 245 / 265 / 285 | 도킹골렘 (`docking_golem`) |
| R5 | 15 / 35 / 55 | 255 / 275 / 295 | 접시안테나불가사리 (`dish_starfish`) |
| R6 | 5 / 25 / 45 | 305 / 325 / 345 | 시간압축기 (`time_compressor`) |
| R6 | 15 / 35 / 55 | 315 / 335 / 355 | 기억소각사서 (`memory_incinerator_librarian`) |

The build harness rejects a changed entity, order, local stage, or global-stage mapping.

## Export pipeline

Sprite originals use a flat chroma source. Each of the 16 sprite originals was processed with the installed official helper before strict export:

```sh
python /Users/bbdyno/.codex/skills/.system/imagegen/scripts/remove_chroma_key.py \
  --input INPUT.png --out OUTPUT.png --auto-key border --soft-matte \
  --transparent-threshold 12 --opaque-threshold 220 --despill --edge-contract 1
```

The Issue #45 builder then performs only nearest-neighbor fitting, nearest-color mapping to the region's strict 16-color palette, and binary alpha conversion. Backgrounds remain fully opaque and are center-cropped to 360×572 with nearest-neighbor sampling.

Run the complete contract, export, hash, and QA workflow with a Python environment containing Pillow:

```sh
python tools/issue45_build_r5_r6_pixel_pack.py \
  --verify-contract --all --verify-complete --contact-sheets
```

## Verification result

- 18/18 source files and 18/18 distinct ImageGen artifacts mapped.
- Exactly 4 normal + 2 elite + 2 boss + 1 background per region.
- All 16 sprites have fully transparent corners after the official helper.
- Transparent intermediates have no detected dominant chroma-green edge pixels.
- Strict sprite exports use only alpha 0/255 and their region's 16 colors.
- Both backgrounds are fully opaque, palette-locked, and leave the center battle lane readable.
- Human review of the named checkerboard sheets confirms recognizable silhouettes, separated break targets, and no visible green fringe.

QA sheets:

- `docs/screenshots/issue-45-r05-contact-sheet.png`
- `docs/screenshots/issue-45-r06-contact-sheet.png`
