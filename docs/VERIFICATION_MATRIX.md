# iOS 버티컬 슬라이스 검증 매트릭스

| 영역 | 로컬/CI 명령 | 승인 조건 | 현재 증빙 |
|---|---|---|---|
| 콘텐츠 | `python3 tools/validate_project.py` | schema, S1~60, 5단위 엘리트·10단위 보스·S60 지역 보스, 16색 팔레트, 전투 Golden 3개·경제 Golden 2개 통과 | GitHub `validate` |
| iOS | `tuist generate`; `xcodebuild ... test` | Debug build, XCTest 49개, 저장 v1·v2→v8 이관, 8/16시간 오프라인 상한, 유료 작업대·제작 속도·일일권, StoreKit 원장, iPhone Safe Area, iPad 정보 레일, 다중 적, 운영 메뉴, SKView 단일 루트 통과 | 로컬 iOS Simulator XCTest, 실제 캡처 |
| Release | `python3 tools/validate_project.py --release` | 11개 production-ready PNG의 캔버스·16색·알파·SHA-256, iOS IAP 6종·StoreKit Configuration·속도 상한 일치 | release 검증 통과 |
| 결제 | `xcodebuild ... test`; Xcode StoreKit Transaction Manager | 현지 상품명·가격이 있을 때만 구매 진입, persist-before-finish, transaction ID 멱등, 복원·환불·만료·Ask to Buy 상태, 시즌 패스 entitlement 통과 | StoreKit Configuration 6종, XCTest 원장·권한 테스트 |
| 시각 | iPhone 17·iPad 캡처와 전투 영상 | Dynamic Island·홈 영역 회피, 중앙 전투 레인, 모·보라·드론·적 3체 식별, 직접 해체, 장비·직원·시설·기록, 공격·부유·피격·회수 움직임 | `docs/screenshots/ios-yard-combat-iphone.png`, `docs/screenshots/ios-yard-facilities-iphone.png`, `docs/screenshots/ios-yard-facilities-ipad.png` |

## CI 재현성

- Tuist는 루트 `.mise.toml`의 4.202.6으로 고정한다.
- iOS runner의 기종명 변화에 대비해 `simctl` JSON에서 사용 가능한 iPhone UDID를 결정론적으로 선택한다.
- `art-export/asset-manifest.json`은 11개 프로덕션 PNG와 정수 스텝 애니메이션 프로필을 고정한다. 파일이 바뀌면 SHA-256도 갱신해야 Release가 통과한다.

CI 도구 선택은 [Tuist CI 가이드](https://docs.tuist.dev/en/guides/automate/continuous-integration)와 [mise GitHub Actions 가이드](https://mise.jdx.dev/continuous-integration.html)를 따른다.
