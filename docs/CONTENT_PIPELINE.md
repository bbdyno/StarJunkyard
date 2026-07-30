# iOS 콘텐츠 파이프라인

iOS 런타임은 이 저장소의 JSON, JSON Schema, Golden fixture, 팔레트와 에셋 manifest를 단일 진실로 사용한다. 다른 플랫폼 저장소에 대한 상대 경로나 빌드 의존성은 두지 않는다.

## 로컬 검증

```sh
python3 tools/validate_project.py
python3 -m unittest discover -s tests -p "test_*.py"
```

`--release`는 모든 픽셀 에셋이 `production_ready`이고 실제 PNG·SHA-256·팔레트 검증을 통과할 때만 성공한다. R1의 11개 공통 PNG가 이 검증을 통과한다.

## 데이터 책임

- `content/`: 버전 manifest와 스테이지·전투 콘텐츠
- `schemas/`: Swift 모델 생성과 리뷰 기준이 되는 계약
- `golden/`: Swift exact-match 결과 fixture
- `art-source/`: Aseprite 작업에 쓰는 승인 팔레트와 원본 영역
- `art-export/`: 1배율 PNG와 정수 피벗 manifest 영역
- `tools/`: 개발 시점 검증 도구이며 앱에 포함하지 않음

R1은 지수 공식을 런타임 부동소수점으로 다시 계산하지 않는다. `baseHp`와 `baseReward`를 S1~60 데이터에 미리 계산해 넣고 Swift 런타임이 동일한 정수 값을 읽는다. 데이터 재생성은 `python3 tools/generate_r1_content.py`로 수행한다.

## R1 진행·경제 계약

- S5 단위는 엘리트, S10 단위는 보스이며 S60은 R1 지역 보스다.
- 크레딧·부품은 반복 전투와 마지막 클리어 지점의 오프라인 파밍에서 나온다.
- 회로·합금은 첫 클리어 보상이며 항성 코어는 S60 지역 보스 첫 클리어에서만 나온다.
- 오프라인 전투 파밍은 마지막 클리어 스테이지 보상의 70%, 75초 단위, 무료 8시간 상한이다. 시설의 별도 초당 생산 계약과 혼합하지 않는다.
- 다음 지역 출항은 S60 클리어와 다섯 재화의 명시된 비용을 모두 요구한다.
- `golden/economy`의 30분·첫날 fixture는 `tools/economy_simulation.py` 결과와 exact-match한다.

30분 fixture는 1,800초 연속 진행과 초반 강화 3종을, 첫날 fixture는 3,600초 진행 후 24시간 부재(무료 상한 8시간 적용), 강화 6종 구매와 출항 비용 지불을 재현한다. 첫날 결과는 출항 후에도 음수 재화가 없도록 고정한다.
