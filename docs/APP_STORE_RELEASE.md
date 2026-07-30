# App Store 출시 계약

StarJunkyard iOS의 저장소 준비 상태는 `release/app-store/` 아래 구조화된 자료로 관리한다.

- `metadata.json`: ko-KR/en-US 제품 페이지 문안과 아직 외부 입력이 필요한 필드
- `privacy-labels.json`: 현재 소스 기준 추적·수집·필수 사유 API 선언
- `storekit-release-contract.json`: 상품 개수를 고정하지 않는 IAP/StoreKit 일치 규칙
- `visual-assets.json`: 앱 아이콘과 런치 엠블럼의 생성 근거·크기·불투명도·해시
- `screenshots.json`: 최종 빌드에서 캡처할 iPhone/iPad 규격과 장면
- `submission-blockers.json`: 계정 소유자만 해제할 수 있는 제출 차단 조건
- `ExportOptions.template.plist`: 팀 ID와 인증서를 넣지 않은 App Store Connect export 템플릿

## 검증

빠른 저장소 계약 검사는 다음 명령을 사용한다.

```bash
python3 tools/validate_app_store_release.py
```

출시 전체 회귀는 다음 명령을 사용한다.

```bash
python3 tools/release_regression.py
```

전체 회귀는 Python 계약 테스트, Release 콘텐츠/픽셀 검사, App Store 계약, Tuist 생성, 서명 없는 generic iOS Release 빌드, 사용 가능한 iPhone과 iPad 각각의 XCTest를 실행한다. 결과물은 `Derived/ReleaseReadiness`에 생성되며 서명이나 업로드는 하지 않는다.

CI가 없는 환경에서 실행 순서만 점검하려면 `--dry-run`, Xcode가 없는 환경에서 저장소 계약만 점검하려면 `--skip-ios`를 사용한다. 상품이나 기능 브랜치가 통합되면 최종 통합 커밋에서 전체 회귀를 다시 실행해야 한다.

## StoreKit 통합 원칙

상품 ID 목록과 개수의 단일 원본은 `content/ios-iap-catalog.json`이다. 검증기는 StoreKit 런타임 사용 표식이 없을 때에는 카탈로그 계약만 검사하고, `import StoreKit` 또는 `Product.products(`가 소스에 나타나는 순간 `StarJunkyard/StarJunkyard.storekit`과 Scheme 연결을 요구한다. 구성 파일이 있으면 그 안의 일반 상품과 구독을 모두 수집해 현재 카탈로그와 ID·유형을 정확히 비교한다.

따라서 다른 이슈가 상품을 추가하거나 제거해도 #29의 숫자를 고칠 필요가 없다. 고객에게 보이는 가격은 StoreKit 현지화 가격만 사용하며 JSON의 기준 가격은 경제 기획용이다.

## Apple 기준 자료

- [Xcode 앱 아이콘 구성](https://developer.apple.com/documentation/xcode/configuring-your-app-icon)
- [App Store 플랫폼 버전 메타데이터](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information/)
- [iPhone/iPad 스크린샷 규격](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/)
- [앱 개인정보 관리](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy/)
- [필수 사유 API 선언](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype)
- [인앱 구입 메타데이터](https://developer.apple.com/help/app-store-connect/reference/in-app-purchases-and-subscriptions/in-app-purchase-information/)
