# StoreKit 2 거래·권한 구현

## 구현 범위

`content/ios-iap-catalog.json`의 5개 상품은 `StoreProductID`와 `PremiumEntitlement`로 타입 안전하게 매핑된다. 앱 시작 시 다음 순서로 결제 상태를 복구한다.

1. `Transaction.updates` 관찰을 먼저 시작한다.
2. `Product.products(for:)`로 카탈로그의 상품 메타데이터를 불러온다.
3. `Transaction.all`의 검증된 이력으로 앱이 꺼져 있을 때 발생한 환불·만료를 반영한다.
4. `Transaction.currentEntitlements`의 검증된 활성 거래를 원장과 대조한다.
5. 원장 저장이 성공한 거래만 `finish()` 한다.
6. 원장에서 현재 시각에 활성인 entitlement를 계산해 게임에 전달한다.

검증 실패 거래는 지급하지도, `finish()` 하지도 않는다. 동일 transaction ID가 구매 결과, 앱 시작 복원, `Transaction.updates`에서 반복 전달되어도 원장에는 한 번만 저장된다. 이미 저장된 거래를 다시 받은 경우에도 원장을 확인한 뒤 `finish()`하여 미완료 거래가 계속 재전달되지 않게 한다.

## 거래 원장

원장은 Application Support의 `StarJunkyard/purchase-ledger.json`에 기록한다. 저장은 원자 교체와 iOS 파일 보호를 사용하며 이전 정상 파일을 별도 백업한다. 각 항목에는 transaction ID, original transaction ID, 상품 ID, 구매일, 만료일, 환불일을 저장한다.

- 비소모성 환불: revocation date가 기록되면 해당 권한을 즉시 제외한다.
- 구독 해지: 현재 결제 기간의 expiration date까지 권한을 유지하고 이후 제외한다.
- 재구독·갱신: 새 transaction ID를 별도 감사 기록으로 남긴다.
- 클라우드: `exportCloudData()`와 `mergeCloudData(_:)`가 같은 Codable 스냅샷을 사용한다. 병합은 transaction ID 단위이며 환불 정보는 제거되지 않는다.

Game Center에 결제 증빙 자체를 대신 저장하는 구조가 아니다. App Store 검증이 권위 원본이며, 클라우드 직렬화는 여러 로컬 저장에서 이미 처리한 transaction ID의 중복 지급을 막기 위한 보조 수단이다.

## 사용자 상태

결제 계층은 로딩, 구매 중, 보호자 승인 대기(Ask to Buy), 사용자 취소, 복원 중, 복원 완료, 검증 실패, 오프라인 재시도 상태를 구분한다. 네트워크나 StoreKit 호출이 실패하면 마지막 작업을 보관하고 `retryLastOperation()`으로 상품 로딩·복원을 다시 시도한다.

아직 실제 작업대 큐, 외형 장착, 멤버십 제작 시스템이 없으므로 유료 구매 버튼은 노출하지 않는다. 시설·직원 화면에는 다음 entitlement를 읽은 명확한 `활성/잠김` 상태만 표시한다.

- 세 번째 작업대 슬롯
- 오프라인 16시간 적립
- 보라 창업복·녹슨 정비복
- 월간 정비 멤버십

`offline_cap_16h`만 현재 게임 효과와 연결되어 있다. 활성 시 `YardEconomy`의 오프라인 적립 상한이 8시간에서 16시간으로 바뀐다.

## 로컬 StoreKit 테스트

공유 `StarJunkyard` 스킴은 `StarJunkyard/StarJunkyard.storekit`을 사용한다. 이 구성에는 카탈로그와 동일한 비소모성 4개와 자동 갱신 구독 1개가 있다. Xcode의 StoreKit Transaction Manager에서 구매, 환불, 구독 만료를 로컬로 재현할 수 있다.

## App Store Connect 이후 필수 검증

현재 구현은 실제 App Store Connect 상품이나 Sandbox 계정에 접근하지 않았다. 구매 UI를 출시 빌드에 열기 전 다음 항목을 완료해야 한다.

- App Store Connect에 동일 ID·유형·구독 그룹으로 5개 상품 생성
- 유료 앱 계약, 세금·은행 정보와 한국어 가격 표시 검토
- Sandbox 구매, 앱 재설치 후 복원, 기기 간 복원
- Ask to Buy 승인·거절·장시간 pending
- 구매 직후 네트워크 단절과 원장 쓰기 실패 후 재전달
- 비소모성 환불과 구독 해지·만료·갱신·청구 재시도
- StoreKit Configuration이 아닌 Sandbox 영수증에서 `Transaction.updates` 재수신
- 실제 작업대·외형·제작 시스템 구현 후 각 권한 연결
