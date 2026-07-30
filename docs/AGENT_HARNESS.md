# 멀티에이전트 작업 하네스

이 하네스는 한 이슈를 한 브랜치·한 worktree에 고정하고, 담당 경로 밖 변경이 통합 단계에 들어오는 것을 막는다. 모든 명령은 저장소 루트에서 실행한다.

## 작업 정의

`agent-harness/tasks.json`에 다음 항목을 추가한다.

- `id`, `issue`, `title`: 사람이 추적할 작업 식별자
- `branch`: `issue/`로 시작하는 전용 브랜치. 대소문자와 관계없이 `codex`를 포함할 수 없다.
- `baseRef`: 변경 범위를 계산할 공통 시작 커밋. 병렬 작업 중 브랜치가 이동하거나 삭제되어도 판정이 바뀌지 않도록 전체 커밋 해시를 권장한다.
- `worktreeHint`: 사람이 참고할 상대 경로. 실제 상태는 `git worktree list`에서 찾는다.
- `ownedPaths`: 이 작업이 변경할 수 있는 저장소 상대 POSIX glob
- `validationProfile`: 통합 전에 실행할 공통 품질 게이트

절대 경로와 `..`를 포함한 소유 경로는 거부된다. 여러 작업이 같은 파일을 소유해야 한다면 별도 worktree에서 커밋하고 통합 담당자가 순차 적용한다. 하네스는 무단 변경을 막지만 병합 충돌을 자동 해결하지 않는다.

## 에이전트 작업 절차

```bash
python3 tools/agent_harness.py validate-definitions
python3 tools/agent_harness.py status
python3 tools/agent_harness.py guard issue-22
```

`guard`는 현재 브랜치가 작업 정의와 정확히 같은지, 금지 문자열이 없는지, 기준 ref 이후의 커밋·staged·unstaged·untracked 파일이 모두 `ownedPaths` 안인지 검사한다. 작업 중인 소유 경로의 dirty 파일은 보고하되 허용한다.

구현과 로컬 커밋을 마친 후 전체 검증을 실행한다.

```bash
python3 tools/agent_harness.py verify issue-22 --require-clean
```

한 명령으로 다음 게이트를 순서대로 실행한다.

1. Python 계약 및 하네스 단위 테스트
2. Release 콘텐츠·픽셀 에셋·IAP 계약 검사
3. `tuist generate --no-open`
4. 사용 가능한 iPhone Simulator를 선택한 뒤 iOS XCTest

명령을 먼저 확인할 때는 `--dry-run`, 한 단계가 실패해도 나머지 결과가 필요할 때는 `--keep-going`을 붙인다. 실제 iOS 결과는 `Derived/AgentHarness`에 생성되어 Git dirty 상태에 포함되지 않는다.

## 통합 담당자 절차

1. `python3 tools/agent_harness.py status`에서 대상 작업이 `clean`, `OK/OK`인지 확인한다.
2. 대상 worktree에서 `verify <task> --require-clean` 결과가 모두 `PASS`인지 확인한다.
3. 기준 브랜치에 대상 커밋을 순차 적용한다. 기능 브랜치끼리 직접 병합하지 않는다.
4. 충돌 해결은 통합 브랜치에서 수행하고, 공통 `full-ios` 검증을 다시 실행한다.
5. 통합 후 이슈를 닫고 더 이상 쓰지 않는 worktree를 정리한다.

`status`의 `dirty(N)`은 커밋되지 않은 파일 수, `FAIL(N)`은 담당 범위를 벗어난 변경 파일 수다. `FAIL(base)`는 `baseRef`를 찾을 수 없다는 의미다.

저장소의 `Tuist/` 디렉터리는 Git worktree의 `.git` 파일을 Tuist 4가 루트로 인식하지 못하는 문제를 해결하는 최소 마커다. 삭제하면 일반 clone에서는 생성되더라도 worktree의 `tuist generate`가 실패한다.
