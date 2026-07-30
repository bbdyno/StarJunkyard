# StarJunkyard iOS

iOS/iPadOS 전용 StarJunkyard 저장소다. 루트의 `Project.swift`가 Xcode 프로젝트를 생성하며, UIKit이 앱 생명주기와 접근성 셸을 담당하고 SpriteKit이 360×800 픽셀 전투를 그린다. Android 프로젝트나 Android 빌드 의존성은 포함하지 않는다.

- [한국어 마스터 게임 기획서](STARJUNKYARD_MASTER_GDD_KO.md)
- [픽셀 게임 비주얼 가드레일](docs/PIXEL_VISUAL_GUARDRAILS.md)
- [공통 콘텐츠 파이프라인](docs/CONTENT_PIPELINE.md)
- [iOS 도트 전투 버티컬 슬라이스](docs/IOS_VERTICAL_SLICE.md)
- [버티컬 슬라이스 검증 매트릭스](docs/VERIFICATION_MATRIX.md)
- [R1 프로덕션 픽셀 아트와 애니메이션](docs/PIXEL_ART_IMPLEMENTATION.md)
- [R1–R6 프로덕션 월드와 픽셀 팩](docs/R2_PRODUCTION_PACK.md)
- [멀티에이전트 worktree 및 검증 하네스](docs/AGENT_HARNESS.md)
- [현지화·설정·분석·피드백 제품 기반](docs/PRODUCT_FOUNDATION.md)
- [연구·제작·원정 작업 시스템](docs/IDLE_OPERATIONS.md)
- [픽셀 설정 콘솔과 접근성](docs/PIXEL_SETTINGS_ACCESSIBILITY.md)
- [StoreKit 2 거래·권한 구현](docs/STOREKIT_IMPLEMENTATION.md)
- [8주 시즌 라이브옵스](docs/SEASON_LIVEOPS.md)
- [App Store 출시 계약과 전체 회귀](docs/APP_STORE_RELEASE.md)

## 병렬 작업 상태와 공통 검증

이슈별 브랜치·worktree·담당 경로는 `agent-harness/tasks.json`에 선언한다. 브랜치 이름에는 `codex`를 사용할 수 없다. 현재 dirty 상태와 경로 소유권은 다음 명령으로 확인한다.

```bash
python3 tools/agent_harness.py status
python3 tools/agent_harness.py guard issue-21
```

커밋된 작업을 인계하기 전에는 Python 계약, Release 검사, Tuist 생성, iOS XCTest를 동일한 명령으로 실행한다.

```bash
python3 tools/agent_harness.py verify issue-21 --require-clean
```

App Store 제출 전 저장소 계약, 서명 없는 Release 빌드, iPhone/iPad XCTest를 한 번에 실행한다. 이 명령은 서명·업로드·심사 제출을 수행하지 않는다.

```bash
python3 tools/release_regression.py
```

Apple 계정·법무·지원/개인정보 URL·최종 스크린샷·IAP 승인·TestFlight·심사 제출처럼 외부 권한이 필요한 항목은 [출시 체크리스트](release/app-store/RELEASE_CHECKLIST.md)에 별도로 기록한다.

## 프로덕션 월드

런타임 콘텐츠는 R1 끝골목 폐기장부터 R6 버려진 달 도시와 기계 행성까지 S001–S360을 제공한다. 여섯 지역은 각각 고유 배경, 일반 적 4종, 엘리트 2종, 보스 2종과 지역별 기지·스토리 목표를 사용한다. 공통 매니페스트에는 프로덕션 에셋 58개가 등록되며 `contract_only`, null 스프라이트, 추상 폴백을 허용하지 않는다.

지역별 iPhone 17/iPad (A16) 전투 캡처는 `docs/screenshots/r3-*`부터 `r6-*`까지 보관한다. 개발 빌드에서 `-capture-r2` … `-capture-r6` 실행 인자로 각 지역 첫 스테이지를 재현할 수 있다.
