# iOS 콘텐츠 파이프라인

iOS 런타임은 이 저장소의 JSON, JSON Schema, Golden fixture, 팔레트와 에셋 manifest를 단일 진실로 사용한다. 다른 플랫폼 저장소에 대한 상대 경로나 빌드 의존성은 두지 않는다.

## 로컬 검증

```sh
python3 tools/validate_project.py
python3 -m unittest discover -s tests -p "test_*.py"
```

`--release`는 모든 픽셀 에셋이 `production_ready`이고 실제 PNG·SHA-256·팔레트 검증을 통과할 때만 성공한다. R1은 정비사·드론 2종·적 5종·뒷골목 배경까지 9개 공통 PNG가 이 검증을 통과한다.

## 데이터 책임

- `content/`: 버전 manifest와 스테이지·전투 콘텐츠
- `schemas/`: Swift 모델 생성과 리뷰 기준이 되는 계약
- `golden/`: Swift exact-match 결과 fixture
- `art-source/`: Aseprite 작업에 쓰는 승인 팔레트와 원본 영역
- `art-export/`: 1배율 PNG와 정수 피벗 manifest 영역
- `tools/`: 개발 시점 검증 도구이며 앱에 포함하지 않음

R1 슬라이스는 지수 공식을 런타임 부동소수점으로 다시 계산하지 않는다. `baseHp`와 `baseReward`를 1~20단계 데이터에 미리 계산해 넣고 Swift 런타임이 동일한 정수 값을 읽는다.
