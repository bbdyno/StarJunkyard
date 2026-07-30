# iOS App Store 출시 체크리스트

이 문서는 저장소에서 재현 가능한 준비 상태와 App Store Connect 권한이 있어야 완료할 수 있는 출시 행위를 분리한다. `python3 tools/release_regression.py`가 통과해도 아래 외부 항목이 끝나기 전에는 제출할 수 없다.

## 저장소 자동 게이트

- [x] iPhone/iPad 대상, 번들 ID, 버전/빌드 번호, 게임 카테고리와 암호화 사용 선언을 프로젝트에 고정했다.
- [x] 모·리벳·별 코어가 읽히는 1024×1024 불투명 픽셀 앱 아이콘과 런치 화면 색상·엠블럼을 Asset Catalog에 연결했다.
- [x] `PrivacyInfo.xcprivacy`에 추적 없음, 개발자 수집 데이터 없음, 앱 전용 `UserDefaults`의 `CA92.1` 사유를 선언했다.
- [x] 한국어·영어 이름, 부제, 홍보 문구, 설명, 키워드와 첫 출시 문안을 `metadata.json`에 작성했다.
- [x] 현재 IAP 카탈로그를 동적으로 읽는 StoreKit 출시 계약을 추가했다. StoreKit 런타임이 합쳐지는 순간 `.storekit` 상품 ID·유형과 프로젝트 Scheme 연결이 필수로 전환된다.
- [x] Release 콘텐츠/픽셀 검사, 메타데이터/개인정보/StoreKit 검사, Tuist 생성, 서명 없는 Release 기기 빌드, iPhone/iPad XCTest를 한 명령으로 묶었다.
- [x] CI와 멀티에이전트 하네스에 #29 전용 출시 게이트를 등록했다.

## 최종 기능 통합 뒤 다시 확인

- [ ] `python3 tools/release_regression.py`를 최종 통합 커밋에서 다시 실행한다.
- [ ] `privacy-labels.json`을 최종 바이너리의 SDK privacy report와 대조한다. 네트워크 분석·광고·충돌 수집 SDK가 추가되면 빈 수집 목록을 유지하면 안 된다.
- [ ] `content/ios-iap-catalog.json`과 StoreKit 런타임/구성의 상품 ID·유형이 일치하는지 자동 검사 결과를 보관한다. 특정 상품 개수를 체크리스트에 복사하지 않는다.
- [ ] 모든 고객 노출 가격이 StoreKit의 현지화된 `displayPrice`에서 나오고 계획용 `referencePriceUSD`가 화면에 노출되지 않는지 확인한다.
- [ ] 저장 게임 선택, Game Center 비로그인/로그인/충돌 복구와 기기 간 저장 복원을 실제 기기에서 확인한다.
- [ ] iPhone과 iPad의 세이프 에어리어, Dynamic Type, VoiceOver, Reduce Motion, 백그라운드/복귀를 확인한다.
- [ ] 구매 성공·취소·보류·중복·복원·환불·구독 만료·네트워크 단절을 Sandbox/TestFlight에서 확인한다.
- [ ] 최종 빌드 화면으로 `screenshots.json`의 iPhone 6.9형과 iPad 13형 세트를 캡처한다. 알파 채널을 넣지 않는다.

## 외부 권한이 필요한 차단 항목

- [ ] `ASC-ACCOUNT`: App Store Connect 앱 레코드, SKU, App Review 연락처, Developer Team, 인증서와 프로비저닝을 확정한다.
- [ ] `ASC-LEGAL`: 저작권자, 콘텐츠 권리, 유료 앱 계약, 세금·은행·지역 사업자 정보를 승인한다.
- [ ] `ASC-URLS`: 실제 연락처가 있는 HTTPS 지원 페이지와 개인정보 처리방침을 게시하고 최종 URL을 입력한다.
- [ ] `ASC-AGE`: 최종 게임/결제 내용에 맞춰 현재 연령 등급 설문을 사람이 확인하고 제출한다.
- [ ] `ASC-SCREENSHOTS`: 최종 스크린샷을 검수하고 각 로케일에 업로드한다.
- [ ] `ASC-IAP`: 카탈로그의 현재 모든 상품과 구독 그룹을 App Store Connect에 생성하고 현지화·가격·심사 자료를 승인한다.
- [ ] `ASC-TESTFLIGHT`: 서명된 archive를 업로드하고 실제 기기·TestFlight·Sandbox 증적을 남긴다.
- [ ] `ASC-SUBMISSION`: 최종 개인정보 라벨, 수출 규정, 지역/가격, 출시 방식을 확정한 뒤 명시적으로 App Review에 제출한다.

외부 항목의 세부 책임과 해제 조건은 `submission-blockers.json`이 단일 원본이다. 이 브랜치는 서명, 업로드, 상품 생성 또는 심사 제출을 수행하지 않는다.
