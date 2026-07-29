# R1 프로덕션 픽셀 아트 구현 기록

## 최종 에셋

iOS 원본은 `art-export/production/sprites/`에 둔다. SpriteKit이 텍스처 필터링 없이 정수 배율로 표시한다.

| ID | 화면에서 읽혀야 하는 것 | 캔버스 |
|---|---|---|
| `actor_mo_base` | 얼굴, 올린 용접 바이저, 작업복, 양손 절단기 | 48×64 |
| `drone_riv0_base` | 카메라 눈, 2개 로터, 자석 집게 | 48×40 |
| `drone_spk2_base` | 리벳과 다른 청색·마젠타 전기형 도장 | 48×40 |
| `enemy_can_bug` | 찌그러진 캔 몸통, 풀탭, 6개 다리 | 32×32 |
| `enemy_umbrella_crab` | 찢어진 우산 갑각, 갈고리 집게, 게 다리 | 48×48 |
| `enemy_fan_bat` | 선풍기 날개 눈, 철망 박쥐 날개, 전선 꼬리 | 48×48 |
| `elite_vending_knight` | 자판기 몸통, 투구, 캔 발사기, 표지판 방패 | 64×64 |
| `boss_cancrab_king` | 압착기 몸통, 캔 왕관, 비대칭 유압 집게 | 128×96 |
| `background_r01_back_alley` | 압착기, 별·렌치 간판, 폐차, 작업등, 컨베이어 | 360×572 |

## 최종 생성 프롬프트 세트

내장 ImageGen으로 각각 독립 생성한 원화의 핵심 프롬프트는 다음과 같다.

1. `Mo`: “full-body scrapyard mechanic, side view facing right, raised orange welding visor, teal work overalls, oversized industrial plasma cutter, authentic hand-authored 16-bit pixel art.”
2. `Rivet`: “compact salvage drone, amber cyclops camera, twin rotors, magnetic claw, worn teal-and-iron plates, side-view 16-bit pixel sprite.”
3. `Can Bug`: “crushed soda can transformed into a beetle, pull-tab shell, six sharp metal legs, amber eye, side-view 16-bit pixel enemy.”
4. `Umbrella Crab`: “broken blue umbrella transformed into a crab, torn canopy shell, bent-handle pincers, exposed ribs, side-view pixel enemy.”
5. `Fan Bat`: “broken desk fan transformed into a bat, fan-cage torso, teal blades, mesh wings, power-cord tail, side-view pixel enemy.”
6. `Vending Knight`: “rusted vending machine walking knight, product window, can launcher, sign shield, hydraulic legs, three-quarter pixel enemy.”
7. `Cancrab King`: “colossal scrap crab built from a car compactor and crushed cans, can crown, asymmetric crushing claws, piston legs, furnace mouth.”
8. `Back Alley`: “portrait nighttime scrapyard workshop, corrugated wall, star-and-wrench sign, car compactor, crushed cars, appliances, clear central combat lane, conveyor foreground.”

모든 스프라이트 프롬프트에는 단색 크로마 배경, 한 개 피사체, 공통 16색 재료군, 단일 픽셀 그리드, 단단한 외곽선, 안티앨리어싱·그라데이션·워터마크·추가 오브젝트 금지를 공통 조건으로 사용했다. 결과는 크로마 제거 후 목표 캔버스로 리샘플하고 `common16.gpl`의 정확한 색으로 재양자화했다. 부분 알파는 제거했고 매니페스트 SHA-256을 고정했다.

## 애니메이션 프로필

- 정비사: 4단계 호흡 대기, 4단계 전진·절단기 반동, 10fps
- 리벳: 4단계 부유, 2단계 로터 잔상, 공격 반동
- 일반 적: 4단계 보행/비행, 3단계 피격 흔들림·플래시
- 보스: 4단계 중량 대기와 집게 예고
- 해체: 10개 파편 폭발 후 리벳 자석으로 8 tick 회수

SpriteKit은 보간 이동 대신 1–7 논리 픽셀 단위의 순간 이동과 50–180ms 유지 프레임을 사용한다. 따라서 애니메이션은 보이지만 픽셀 경계는 흐려지지 않는다.
