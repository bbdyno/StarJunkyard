# StarJunkyard iOS

iOS/iPadOS 전용 StarJunkyard 저장소다. 루트의 `Project.swift`가 Xcode 프로젝트를 생성하며, UIKit이 앱 생명주기와 접근성 셸을 담당하고 SpriteKit이 360×800 픽셀 전투를 그린다. Android 프로젝트나 Android 빌드 의존성은 포함하지 않는다.

- [한국어 마스터 게임 기획서](STARJUNKYARD_MASTER_GDD_KO.md)
- [픽셀 게임 비주얼 가드레일](docs/PIXEL_VISUAL_GUARDRAILS.md)
- [공통 콘텐츠 파이프라인](docs/CONTENT_PIPELINE.md)
- [iOS 도트 전투 버티컬 슬라이스](docs/IOS_VERTICAL_SLICE.md)
- [버티컬 슬라이스 검증 매트릭스](docs/VERIFICATION_MATRIX.md)
- [R1 프로덕션 픽셀 아트와 애니메이션](docs/PIXEL_ART_IMPLEMENTATION.md)
- [멀티에이전트 worktree 및 검증 하네스](docs/AGENT_HARNESS.md)

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
