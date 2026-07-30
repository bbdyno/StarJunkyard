# R2 production pack and R3–R6 handoff contract

## Intermediate status

This commit is the R2 production checkpoint for issue #38. It defines the complete R1–R6 world contract, but deliberately exposes only S001–S120 to the game runtime until the remaining art packs are integrated.

| Region | Stages | Enemy roster | Runtime art |
| --- | ---: | ---: | --- |
| R1 끝골목 폐기장 | 1–60 | 4 normal + 2 elite + 2 boss | production ready |
| R2 폐쇄된 메가몰 | 61–120 | 4 normal + 2 elite + 2 boss | production ready |
| R3 막차 없는 지하철 | 121–180 | 4 normal + 2 elite + 2 boss | contract only (#44) |
| R4 침몰선 묘지 | 181–240 | 4 normal + 2 elite + 2 boss | contract only (#44) |
| R5 궤도 잔해권 | 241–300 | 4 normal + 2 elite + 2 boss | contract only (#45) |
| R6 버려진 달 도시와 기계 행성 | 301–360 | 4 normal + 2 elite + 2 boss | contract only (#45) |

The generated contract contains exactly 6 regions, 360 stages, 24 normal enemies, 12 elites, and 12 bosses. `slice.productionStageEnd` remains `120` at this checkpoint. `ContentLoader` rejects unfinished art and filters the runtime to the production range instead of displaying placeholders.

After #44 and #45 have been integrated, issue #38 must not close until all of these are true:

- `slice.productionStageEnd` is `360` and `ContentLoader` loads all 360 stages.
- No enemy has `assetStatus: contract_only` or a null `spriteId`.
- Every region has a production background.
- The release validator reports 360 production stages.

## Generated source and runtime data

- `tools/generate_world_content.py` is the canonical generator.
- `content/world_r1_r6.json` is the generated runtime contract.
- `schemas/content.schema.json` is its JSON Schema.
- `tools/generate_world_goldens.py` and `tools/world_economy.py` generate the six regional economy fixtures.
- `StarJunkyard/Sources/RegionProgression.swift` resolves region membership and the S060→S061 story transition.
- `StarJunkyard/Sources/ContentModels.swift` exposes only production-ready stages and assets.

Do not hand-edit only the generated JSON. Update the generator and regenerate so both files remain identical.

## R2 production art

Every R2 sprite uses `art-source/palettes/r02_mall12.gpl`, nearest-neighbor scaling, fully opaque or transparent pixels, and no chroma fringe. Normal and elite sprites use at most 12 approved colors; bosses use at most 18.

| Asset ID | SHA-256 |
| --- | --- |
| `enemy_cart_deer` | `2ae7b245ba46aacebb057452e6be34dcc0e3a7fd9824da0393330d00ea43dad5` |
| `enemy_mannequin_octopus` | `cb50482fc921ed969ac58ba8cf7e77d72a382b73e59b365bbf5d5f30a3662922` |
| `enemy_kiosk_turtle` | `e75931f99b55112f620061d1f1c93a18513010faf7d994a1171cfbd3d325e4f3` |
| `enemy_vacuum_snail` | `0a7bd1b7d9bb4b0614599362754306078f616649f561919a82a4023c66061b81` |
| `elite_escalator_centipede` | `6fe25c7f26b9a2e473b5dba3265eb70aa88340001e21eccca8a185801ba5e0ef` |
| `elite_shutter_peacock` | `4cc8cd5f09cb633f92343297fd25bbb6399d40dd30dc3843b241d5d2cfad2237` |
| `boss_billboard_hydra` | `72425d717a9cceeb90185981a2dc29a8765f0dcfa86ff70a0b6b2e0c78e56858` |
| `boss_empty_throne` | `df7392162896eb987acd3ff33f58584c867c9040ca2858fcb482a4a3c5d10bc8` |
| `background_r02_closed_megamall` | `87facf6ab9b0281a2c7e905a74a59aed4e06b8193bed9adf4170ca533b28a794` |

Two missing R1 production slots were completed with the same pipeline:

| Asset ID | SHA-256 |
| --- | --- |
| `elite_tire_matador` | `f22f2e14f61d511894202e63b47f008c5c285f8b8b683dcfe3e817a9a3fded3e` |
| `boss_alley_devourer` | `3f0a5c0e48a5e1ebe272ae00d9fe54b277596e931d9e7ae658c9b70621033d4e` |

The original generated alpha sources live under `art-source/generated/r01` and `art-source/generated/r02`. Final runtime files live under `art-export/production/sprites` and are registered in `art-export/asset-manifest.json`.

## Image generation and strict pixel pipeline

Each asset was generated in a separate built-in ImageGen call. The shared prompt contract was:

> Stylized-concept game sprite with a hand-authored pixel-art look; unmistakable named-object silhouette; generous padding; perfectly flat #00ff00 background for sprites; no shadow, gradient, text, logo, or watermark. Backgrounds are full-frame scenes without chroma.

Named silhouettes covered the garbage-truck Alley Devourer, Scrap-tire Matador, cart deer, mannequin octopus, kiosk turtle, vacuum snail, escalator centipede, shutter peacock, billboard hydra, empty mall throne, and closed megamall.

Sprite sources were matted with the official `remove_chroma_key.py` helper using border auto-key, soft matte, despill, and one-pixel edge contraction. `tools/build_r2_pixel_assets.py` then quantizes to the approved region palette, enforces binary alpha, removes fringe pixels, writes final canvas/pivot sizes, and refreshes the manifest hashes.

## Exact fragment contract for #44 and #45

Each production pack must return an asset-manifest fragment and the corresponding world-enemy fragment. The integrator compares every field against the canonical generator; renamed IDs or paraphrased Korean behavior text fail validation.

World enemy entries must have this exact shape:

```json
{
  "regionId": "r03",
  "id": "route_map_spider",
  "nameKo": "노선도거미",
  "class": "elite",
  "hpMultiplierPpm": 7800000,
  "weakness": "cut",
  "secondaryWeaknesses": [],
  "behaviorId": "reroute_web",
  "behaviorKo": "노선도 실로 공격 경로 전환",
  "breakSequenceKo": "환승점 3개→노선 실→중앙 역명판",
  "spriteId": "elite_route_map_spider",
  "assetStatus": "production_ready"
}
```

The remaining locked second-elite contracts are:

| Region | ID / Korean name | Weakness | Behavior ID / text | Break sequence |
| --- | --- | --- | --- | --- |
| R3 | `route_map_spider` / 노선도거미 | `cut` | `reroute_web` / 노선도 실로 공격 경로 전환 | 환승점 3개→노선 실→중앙 역명판 |
| R4 | `buoy_lighthouse_knight` / 부표등대기사 | `electric` | `rotating_beacon_lock` / 회전등으로 표적 잠금 | 부표 장갑→회전등→계류 체인 |
| R5 | `dish_starfish` / 접시안테나불가사리 | `cooling` | `five_dish_reflection` / 다섯 접시로 빔 반사 | 접시 5개 각도 정렬→수신 코어 |
| R6 | `memory_incinerator_librarian` / 기억소각사서 | `cooling` | `erase_recorded_buff` / 기록 한 줄씩 소각해 강화 제거 | 소각 서랍 3개→기록 집게→냉각 코어 |

Do not independently recreate numeric values. Read `hpMultiplierPpm`, all weaknesses, `behaviorId`, and `breakSequenceKo` from the matching generator entry and change only `spriteId` and `assetStatus` when promoting the asset.

Every sprite manifest fragment must contain exactly these fields:

```json
{
  "id": "elite_route_map_spider",
  "kind": "enemy_wide",
  "canvas": [64, 48],
  "pivot": [32, 46],
  "scalePolicy": "integer_nearest",
  "status": "production_ready",
  "paletteId": "r03_<approved-palette-id>",
  "file": "art-export/production/sprites/elite_route_map_spider.png",
  "sha256": "<lowercase 64-character SHA-256>"
}
```

Every region background uses the same manifest fields with `kind: background`, canvas `[360, 572]`, and pivot `[0, 572]`. Update its region `backgroundSpriteId` from null to the exact manifest ID.

## Integration and harness gates

Issues #38, #44, and #45 are registered in `agent-harness/tasks.json` with disjoint common-integration and pack-production ownership. The `pixel-pack` profile runs these gates in order:

1. Detect issue #44 or #45 from the branch, run its region asset builder, and exact-match the emitted fragment.
2. Check the immutable R3–R6 world contract without writing.
3. Run the pixel-pack integration fixture tests.
4. Run `python3 tools/validate_project.py --release` against the current common production set.

After both packs merge, the final #38 integration also regenerates regional economy goldens, runs the full Python and iOS suites, and captures one phone plus one iPad frame for the new regions.

Current visual references are `docs/screenshots/r2-iphone17.png` and `docs/screenshots/r2-ipad-a16.png`.

`python3 tools/integrate_world_pixel_packs.py --check-contracts` is always read-only and works before the pack fragments exist. When both fragments are complete, validate them without writing first:

```shell
python3 tools/integrate_world_pixel_packs.py \
  --fragment art-export/issue-44-r3-r4/manifest-fragment.json \
  --fragment art-export/issue-45-r5-r6/manifest-fragment.json
```

Only after that succeeds should the integrator be run again with `--apply`. The apply path revalidates both packs together, copies their production PNGs into the common runtime directory, adds their palettes and assets to the common manifest, records a deterministic `content/world-pixel-pack-promotions.json` overlay, promotes every R3–R6 entity/background, and changes `productionStageEnd` to 360. A single pack cannot promote the world.
