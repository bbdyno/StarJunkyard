# iOS 제품 기반 계약

이 문서는 현지화, 기기 설정, 분석 이벤트, 오디오·햅틱의 공통 계약을 정의한다. 모든 기능은 네트워크나 외부 분석 SDK 없이 동작하며, 분석 동의가 없거나 저장이 손상돼도 전투·저장·결제 흐름을 막지 않는다.

## 현지화와 포맷

- 한국어와 영어의 원본은 `StarJunkyard/Resources/{ko,en}.lproj/Localizable.strings`에 둔다.
- 키는 `영역.의미` 형태의 영문 식별자다. 화면에 노출되는 한국어를 키로 쓰지 않는다.
- 코드에서는 `GameTextKey`와 `GameText.localized`만 사용한다. 새 키는 두 언어와 `GameTextKey.allCases`에 같은 커밋으로 추가한다.
- 수치가 들어가는 문장은 문자열 조각을 이어 붙이지 않고 `%1$lld` 같은 위치 지정자를 사용한다. `GameText.format`이 현재 언어의 숫자 표기를 적용한다.
- 게임 콘텐츠 고유명은 콘텐츠 데이터의 언어 필드로 관리하고, 메뉴·설정·접근성 문구는 문자열 리소스로 관리한다.
- 복수형이 필요한 영문 문장은 다음 확장 때 `.stringsdict` 또는 String Catalog의 plural variation으로 옮긴다.

## 기기 설정

`GameSettingsStore`는 저장 슬롯과 별도인 `UserDefaults` JSON 한 건을 사용한다. 기본값은 음악·효과음·햅틱 켬, 모션 감소·흔들림 감소·한 번 탭 대체 끔이다. 누락 필드는 안전한 기본값으로 이관되므로 필드를 추가해도 이전 설치가 깨지지 않는다.

| 설정 | 즉시 적용 계약 |
|---|---|
| 음악 | 배경 트랙 시작·정지 |
| 효과음 | 짧은 피드백 톤 허용 여부 |
| 햅틱 | 탭·해체·복구 햅틱 허용 여부 |
| 모션 감소 | 화면 전환을 0초 페이드로 대체 |
| 흔들림 감소 | 향후 전투 카메라 흔들림을 정적 플래시로 대체 |
| 한 번 탭 대체 | 향후 길게 누르기·연타 입력에 동등한 단일 탭 경로 제공 |

## 분석과 개인정보

- 이벤트 이름과 속성은 `GameAnalyticsEventName`, `GameAnalyticsParameterKey`의 고정 계약만 사용한다.
- 이메일, 닉네임, Game Center ID, 광고 ID, 기기 ID, 자유 입력 문자열은 기록하지 않는다.
- 문자열 속성은 적·상품·스토리 같은 빌드에 포함된 안정적인 콘텐츠 ID에만 쓴다.
- `AnalyticsConsent`의 기본값은 `unknown`이며 `granted`가 아니면 `ConsentGatedGameAnalytics`는 즉시 반환한다.
- `NoOpGameAnalytics`는 출시 및 테스트 대체재다. `LocalGameAnalyticsRecorder`는 최대 200건의 메모리 버퍼만 제공하며 디스크나 네트워크로 전송하지 않는다.
- 분석 호출은 반환값이나 오류가 없고 게임 기능의 성공 조건에 포함되지 않는다.

## 오디오와 햅틱

`IOSGameFeedbackService`는 설정을 매번 읽고 허용된 피드백만 실행한다. 효과음은 다른 앱의 오디오와 섞이는 `.ambient` 세션의 짧은 합성 톤이라 에셋 누락이 없다. 오디오 세션이나 엔진 시작에 실패하면 조용히 건너뛴다. 직접 해체, 적 해체 완료, 피난처 복구 마일스톤이 현재 연결된 최소 실제 효과다.

## 남은 UI 연결

- 도트 스타일 설정 패널에서 여섯 설정과 분석 동의를 수정하는 화면
- `SaveSelectionScene`과 `CombatScene`의 기존 하드코딩 문구를 카탈로그로 순차 이관
- 실제 BGM 에셋과 앱 생명주기 pause/resume 연결
- 전투 카메라 흔들림 구현 시 `reduceScreenShake` 분기
- 길게 누르기·연타 기능 도입 시 `singleTapActions`의 동등 입력 경로
