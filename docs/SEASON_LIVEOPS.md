# 8주 시즌 라이브옵스

시즌은 본편 진행을 막지 않는 서버리스 선택 콘텐츠다. 현재 시즌과 다음 시즌을 앱 번들에 함께 넣고 UTC 경계에서만 전환한다.

## 콘텐츠 계약

- `content/season-current.json`, `content/season-next.json`: schema/content version을 가진, 각각 정확히 56일인 현재·다음 시즌
- `schemas/season.schema.json`: 임무, 40단계 보상, UTC 기간 계약
- 일일 임무는 6개 풀에서 UTC 날짜와 시즌 seed로 3개를 결정론적으로 선택한다.
- 주간 임무는 매주 4개가 열리고 완료하지 않은 이전 주차 임무도 시즌 종료까지 유지된다.
- 플레이 및 임무 XP 합계는 주차별 2,500을 넘지 않는다. 40단계는 500 XP 간격이라 8주 상한 20,000 XP와 일치한다.
- 결제·광고 지표는 임무 enum에 없으며 Python 검증기도 이를 거부한다.
- 무료 트랙은 재화·재료·도감 이야기, 유료 트랙은 능력치가 없는 외형·프리셋 편의만 제공한다.

## 런타임 API

`SeasonEngine`은 전투 화면이나 StoreKit에 의존하지 않는 값 타입이다.

1. `snapshot(progress:at:clockSuspect:)`로 오늘의 일일 3개, 누적 주간 임무, 해금 단계를 얻는다.
2. 전투·시설·원정은 고유 event ID를 가진 `SeasonGameplayEvent`를 `apply`에 전달한다.
3. 중복 event ID는 무시되며 임무 진척은 목표치에서 멈추고 XP는 주간 상한에서 잘린다.
4. `clockSuspect` 상태에서는 마지막 신뢰 날짜의 임무를 유지하고 XP를 계속 저장하되 시즌 전환만 보류한다.
5. 신뢰 시간이 회복되면 종료 시즌의 제목·도감 ID·획득 XP·최고 단계를 `SeasonCodexRecord`로 보존한 뒤 다음 시즌을 시작한다.
6. `claimReward`는 무료 보상을 결제 없이 지급하고 premium entitlement가 없는 유료 트랙 청구를 거부한다.

## 검증

```bash
python3 tools/validate_project.py --release
python3 -m unittest discover -s tests -p "test_*.py"
tuist generate --no-open
xcodebuild -project StarJunkyard.xcodeproj -scheme StarJunkyard -sdk iphonesimulator CODE_SIGNING_ALLOWED=NO test
```

## 후속 연결

이번 구현은 모델 API와 번들 계약까지다. 통합 단계에서 `SeasonProgress`를 최신 저장/클라우드 payload에 포함하고, 전투·시설·원정의 실제 이벤트를 전달하며, `SeasonSnapshot`을 표시하는 도트 시즌 패널을 메뉴에 연결해야 한다. StoreKit 작업은 entitlement 값만 `premiumUnlocked`에 전달해야 하며 시즌 엔진 안에서 결제를 시작하지 않는다.
