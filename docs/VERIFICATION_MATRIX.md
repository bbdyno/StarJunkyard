# 버티컬 슬라이스 검증 매트릭스

| 영역 | 로컬/CI 명령 | 승인 조건 | 현재 증빙 |
|---|---|---|---|
| 공통 콘텐츠 | `python3 tools/validate_project.py` | schema, 20 stages, 16색 팔레트, 3 golden fixture 통과 | GitHub `validate` |
| 비앱형 Android 셸 | `python3 tools/validate_android_pixel_shell.py` | Compose Card/Button/List 없음, AndroidView 1개, SurfaceView/정수 Canvas | Python 계약 테스트 |
| iOS | `tuist generate`; `xcodebuild ... test` | Debug build, XCTest 4개, SKView 단일 루트, UIButton/SKShapeNode 없음 | GitHub `iOS debug and XCTest`, 실제 캡처 |
| Android | `./gradlew ... :app:assembleDebug :app:lintDebug` | PCG/content/combat tests, Debug APK, Lint 0 issues | GitHub `Android debug, tests, lint`, 실제 캡처 |
| Release | `python3 tools/validate_project.py --release` | production-ready atlas만 허용 | 현재 planned 에셋 때문에 의도적 실패 |
| 시각 | iPhone 17 Pro / Pixel 7 캡처 | 화면 전체가 픽셀 게임 장면, 앱형 카드/리스트 부재, 360×800 안전 구도 | `docs/screenshots/` |

## CI 재현성

- Tuist는 루트 `.mise.toml`의 4.202.6으로 고정한다.
- Android는 저장소의 Gradle 8.13 wrapper와 AGP 8.13.2를 사용한다.
- iOS runner의 기종명 변화에 대비해 `simctl` JSON에서 사용 가능한 iPhone UDID를 결정론적으로 선택한다.
- Release 실패는 CI 결함이 아니다. `art-export/asset-manifest.json`의 모든 항목이 승인된 production PNG로 바뀌기 전까지의 의도된 출하 차단이다.

CI 도구 선택은 [Tuist CI 가이드](https://docs.tuist.dev/en/guides/automate/continuous-integration), [mise GitHub Actions 가이드](https://mise.jdx.dev/continuous-integration.html), [Gradle GitHub Actions 가이드](https://docs.gradle.org/current/userguide/github-actions.html)를 따른다.
