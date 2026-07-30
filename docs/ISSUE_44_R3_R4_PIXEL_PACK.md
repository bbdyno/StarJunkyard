# Issue #44 R3/R4 생산용 픽셀 팩

이 브랜치는 #38 통합용으로 R3 `막차 없는 지하철`과 R4 `침몰선 묘지`의 픽셀 원본, strict export, 검증 가능한 manifest fragment만 제공한다. 공용 `content/`, `art-export/asset-manifest.json`, Swift 런타임과 공용 `common16.gpl`은 수정하지 않는다.

## 콘텐츠 출처와 수량

- 원본 계약: #38 worktree의 `content/world_r1_r6.json`
- 읽은 파일 SHA-256: `f8922a8ce4d98d01f19477a38b7bb3291c52b20914576a4231067e635818338a`
- 지역마다 일반 4, 엘리트 2, 보스 2, 배경 1의 총 9개다.
- #38 데이터의 일반 4, 엘리트 2, 보스 2의 ID·한글 이름·행동·약점·파괴 순서를 변경하지 않는다.

| 지역 | 구분 | entity ID | 이름 | 행동 | 약점 |
|---|---|---|---|---|---|
| R3 | 일반 | `ticket_mouse` | 표딱지쥐 / Ticket-Stub Mouse | 세 마리 군집 | impact |
| R3 | 일반 | `fluorescent_snake` | 형광등뱀 / Fluorescent-Tube Snake | 두 관이 교대 점멸 | impact |
| R3 | 일반 | `seat_armor` | 좌석갑옷 / Subway-Seat Armor | 좌석을 접어 장갑 전환 | cut |
| R3 | 일반 | `vent_jellyfish` | 환풍기해파리 / Vent-Fan Jellyfish | 환풍으로 부유 | electric |
| R3 | 엘리트 | `turnstile_hound` | 개찰구견 / Turnstile Hound | 세 머리 신호 속성 순환 | electric |
| R3 | 엘리트 | `route_map_spider` | 노선도거미 / Route-Map Spider | 노선도 실로 공격 경로 전환 | cut |
| R3 | 중간 보스 | `last_train_engineer` | 막차 기관수 / Last-Train Engineer | 선로 돌진과 신호 변경 | cooling, impact |
| R3 | 지역 보스 | `turnstile_cerberus` | 개찰구 케르베로스 / Turnstile Cerberus | 세 게이트 물기와 표 검사 | electric |
| R4 | 일반 | `anchor_crab` | 앵커게 / Anchor Crab | 체인 세 칸으로 지면 고정 | impact |
| R4 | 일반 | `lifebuoy_puffer` | 구명환복어 / Lifebuoy Puffer | 구명환 장갑 팽창 | cut |
| R4 | 일반 | `bulb_angler` | 전구아귀 / Bulb Angler | 전구 미끼로 암전 | electric |
| R4 | 일반 | `container_hermit` | 컨테이너소라 / Container Hermit | 상자 방패 전개 | heat |
| R4 | 엘리트 | `crane_octopus` | 크레인문어 / Crane Octopus | 네 암 중 공격 암 선택 절단 | cut |
| R4 | 엘리트 | `buoy_lighthouse_knight` | 부표등대기사 / Buoy-Lighthouse Knight | 회전등으로 표적 잠금 | electric |
| R4 | 중간 보스 | `sunken_container_whale` | 침몰 컨테이너 고래 / Sunken Container Whale | 물살과 상자 분출 | heat, cut |
| R4 | 지역 보스 | `nameless_ship_heart` | 무명 함선의 심장 / Heart of the Nameless Ship | 압력 맥박과 암전 | electric, cooling |

R3 엘리트 스테이지는 local S5/25/45에 `turnstile_hound`, S15/35/55에 `route_map_spider`를 배치한다. R4는 local S5/25/45에 `crane_octopus`, S15/35/55에 `buoy_lighthouse_knight`를 배치한다. 같은 엘리트를 연속 사용하지 않으며 각 3회다.

## 실루엣 계약

- 표딱지쥐: 개찰표 직사각 몸, 펀치 구멍 눈, 찢긴 표 귀와 얇은 철사 꼬리. 캔 벌레와 같은 둥근 갑각을 쓰지 않는다.
- 형광등뱀: 두 개의 긴 관이 평행한 S자 몸을 만들고 안정기 머리가 앞에 있다.
- 좌석갑옷: 지하철 등받이 방패와 접힌 방석 가슴판, 좌석 프레임 다리의 직립형이다.
- 환풍기해파리: 원형 팬 코어가 위에 있고 네 개의 덕트 촉수가 아래로 늘어진 부유형이다.
- 개찰구견: 가로 회전봉 다리와 녹·황·적 세 신호 머리의 낮고 넓은 사족형이다.
- 노선도거미: 노선도 판 중앙 몸, 세 개의 원형 환승점, 색 노선 실과 여덟 가는 철사 다리의 넓고 낮은 거미형이다. 개찰구견의 사족·세 머리·회전봉과 겹치지 않는다.
- 막차 기관수: 기관차 보일러 몸과 기관수 모자, 큰 차륜, 신호 레버를 가진 단일 전면 보스다.
- 개찰구 케르베로스: 세 개의 개찰 게이트 입과 표 투입구, 회전봉 발이 각각 읽히는 초대형 사족형이다.
- 앵커게: 닻 팔 두 개와 세 칸 체인 다리, 중앙 부표 코어의 낮은 갑각형이다.
- 구명환복어: 굵은 구명환 외곽, 밸브 가시와 작은 금속 몸의 원형 팽창형이다.
- 전구아귀: 케이블 낚싯대 끝 전구와 큰 배터리 턱이 분리되어 보이는 전진형이다.
- 컨테이너소라: 열린 컨테이너 문 방패와 뒤로 드러난 나선 코어의 넓은 지상형이다.
- 크레인문어: 회전 운전실 머리와 서로 다른 네 크레인 암, 뒤쪽 균형추가 있는 방사형이다.
- 부표등대기사: 세로 원통 부표 갑옷, 머리 위 회전등, 한 손 닻 창과 한 손 표적 잠금 방패, 아래 계류 체인의 높은 기사형이다. 크레인문어의 방사형 네 팔과 겹치지 않는다.
- 침몰 컨테이너 고래: 컨테이너 적재 등, 두 부력 밸브, 큰 고래 턱의 장축형이다.
- 무명 함선의 심장: 선체 프레임 안 거대한 4실 심장과 네 기억 전구, 압력 링의 대칭형이다.

## 팔레트와 생성 계약

R3는 세계 계약 앵커 `#111D33`, `#E4572E`, `#F3A712`, `#7B8794`를 포함한 `r03_subway16.gpl`만 사용한다. R4는 `#0D2B45`, `#176B87`, `#35A7A0`, `#F07167`을 포함한 `r04_shipgrave16.gpl`만 사용한다. 두 팔레트 모두 외곽선용 `#12141C`를 포함한다.

각 distinct asset은 내장 ImageGen을 별도 호출한다. 스프라이트 원본은 완전 균일한 `#00FF00` 배경, 단일 피사체, 그림자·바닥·반사·텍스트·워터마크 없음, 하나의 픽셀 격자, 단단한 1px/2px 외곽, 안티앨리어싱·그라데이션·벡터형 도형 없음으로 생성한다. 배경은 크로마 없이 360×572 세로 전투 구도와 빈 중앙 전투 레인을 요구한다.

스프라이트마다 설치된 공식 helper를 다음 계약으로 실행한다.

```sh
python "${CODEX_HOME:-$HOME/.codex}/skills/.system/imagegen/scripts/remove_chroma_key.py" \
  --input art-source/issue-44-r3-r4/originals/<asset>.png \
  --out art-source/issue-44-r3-r4/transparent/<asset>.png \
  --auto-key border \
  --soft-matte \
  --transparent-threshold 12 \
  --opaque-threshold 220 \
  --despill \
  --edge-contract 1
```

그 다음 issue 전용 빌더가 nearest-neighbor만 사용해 목표 캔버스에 맞추고 가장 가까운 지역 16색으로 양자화하며 알파를 0/255로 고정한다.

```sh
python3 tools/issue44_build_r3_r4_pixel_pack.py --verify-contract
python3 tools/issue44_build_r3_r4_pixel_pack.py --all --verify-complete --contact-sheets
```

`production_ready`는 strict PNG의 크기, binary alpha, 투명 모서리, 지역 팔레트 부분집합, 초록 fringe 0개, 원본/투명 중간물/strict PNG SHA-256 검사를 모두 통과한 뒤 빌더만 기록한다. `imagegenCallArtifacts`는 distinct asset마다 실제 별도 내장 ImageGen 호출의 고유 `exec-*.png` 증거를 남기며, 수정 호출도 순서대로 보존한다. 접촉 시트에는 각 적의 한·영 이름, ID, 등급, 행동, 약점과 4배 nearest-neighbor 미리보기를 함께 둔다.

## 최종 QA 결과

| 지역 | 별도 원본 | strict export | 알파 | 팔레트 | 초록 fringe | 접촉 시트 |
|---|---:|---:|---|---|---:|---|
| R3 | 9 | 9 | 0/255 only | R3 16색 부분집합 | 0 | `docs/screenshots/issue-44-r03-contact-sheet.png` |
| R4 | 9 | 9 | 0/255 only | R4 16색 부분집합 | 0 | `docs/screenshots/issue-44-r04-contact-sheet.png` |

내장 ImageGen은 distinct asset 18개에 각각 호출했다. R3 막차 기관수는 원본 압력계에 생긴 금지 영문을 제거하기 위한 targeted edit 1회를 추가해 총 호출 증거는 19개다. 원본 18개, 투명 중간물 16개, 불투명 배경 원본 2개, strict PNG 18개의 SHA-256을 fragment에 고정했다. R3/R4 접촉 시트의 100% production pixel과 확대 미리보기를 직접 확인해 의미 불명 도형, 복제 실루엣, 잘린 부위, 안티앨리어싱, 초록 테두리가 없음을 승인했다.
