# 공통 콘텐츠 파이프라인

Swift와 Kotlin은 런타임 코드를 공유하지 않는다. 두 앱이 공유하는 것은 이 저장소의 JSON, JSON Schema, Golden fixture, 팔레트와 에셋 manifest뿐이다.

## 로컬 검증

```sh
python3 tools/validate_project.py
python3 -m unittest discover -s tests -p "test_*.py"
```

`--release`는 모든 픽셀 에셋이 `production_ready`이고 실제 PNG·SHA-256·팔레트 검증을 통과할 때만 성공한다. 현재 R1 에셋은 아트 제작 전 `planned` 상태이므로 개발 검증은 통과하지만 릴리스 검증은 의도적으로 실패한다.

## 데이터 책임

- `content/`: 버전 manifest와 스테이지·전투 콘텐츠
- `schemas/`: 플랫폼 모델 생성과 리뷰 기준이 되는 계약
- `golden/`: Swift/Kotlin exact-match 결과 fixture
- `art-source/`: Aseprite 작업에 쓰는 승인 팔레트와 원본 영역
- `art-export/`: 1배율 PNG와 정수 피벗 manifest 영역
- `tools/`: 개발 시점 검증 도구이며 앱에 포함하지 않음

R1 슬라이스는 지수 공식을 런타임 부동소수점으로 다시 계산하지 않는다. `baseHp`와 `baseReward`를 1~20단계 데이터에 미리 계산해 넣고 두 플랫폼이 동일한 정수 값을 읽는다.
