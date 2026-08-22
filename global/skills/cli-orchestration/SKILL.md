---
name: cli-orchestration
description: CLI 명령어 병렬/순차/DAG 실행, Git 워크플로우 자동화, 에이전트 위임 오케스트레이션
---

# CLI Orchestration

다중 CLI 명령어를 병렬 실행하고, 워크플로우 파이프라인을 조율하는 글로벌 스킬.

## Activation Triggers

이 스킬은 다음 요청에서 활성화됩니다:

- **병렬 실행**: "동시에", "병렬로", "한꺼번에", 쉼표로 구분된 2+ 독립 작업
- **순차 워크플로우**: "순서대로", "파이프라인", "→" 체인, "완료되면"
- **DAG 워크플로우**: 병렬+순차 혼합 ("A,B 병렬 후 C 실행")
- **Git 자동화**: "feature branch", "PR 생성", "release", "hotfix"
- **멀티 프로젝트**: "모든 패키지", "monorepo", "전체 프로젝트"
- **에이전트 위임**: "specialist에게 위임", "에이전트로 실행"

## Parallel Mode

독립적인 CLI 명령어를 `run_in_background=true`로 동시 실행하고 `TaskOutput`으로 결과를 수집합니다.

```
# 실행 패턴
1. 명령어 의존성 분석 → 독립 명령어 식별
2. 각 명령어를 Bash(run_in_background=true)로 실행
3. TaskOutput(task_id, block=true)로 결과 수집
4. 통합 리포트 생성

# 예시: lint + typecheck + test 병렬
Bash("cd frontend && npm run lint", run_in_background=true)    → task_1
Bash("cd frontend && npx tsc --noEmit", run_in_background=true) → task_2
Bash("cd frontend && npm test", run_in_background=true)         → task_3
TaskOutput(task_1) + TaskOutput(task_2) + TaskOutput(task_3)
```

최대 동시 실행: 5개. 초과 시 큐에 대기.

## Sequential Workflow

의존성 있는 작업을 순차 실행합니다. 각 스테이지는 이전 스테이지 성공 시에만 진행합니다.

```
# 실행 패턴 (abort-on-failure)
1. Stage 실행 → exit_code 확인
2. 성공(0) → 다음 Stage 진행
3. 실패(non-0) → on_failure 전략 적용 (abort/continue/retry)

# 예시: install → lint → test → build
Bash("npm ci")                          → 성공 시 계속
Bash("npm run lint")                    → 성공 시 계속
Bash("npm test")                        → 성공 시 계속
Bash("npm run build")                   → 완료
```

실패 시 이전 스테이지 결과는 보존됩니다. 특정 스테이지부터 재시작 가능.

## DAG Mode

병렬과 순차를 혼합하여 실행합니다. 의존성 그래프를 토폴로지컬 정렬합니다.

```
# 실행 패턴
1. 노드 의존성 분석 → 실행 레벨 결정
2. 같은 레벨의 노드는 병렬 실행
3. 모든 의존 노드가 성공해야 다음 레벨 진행

# 예시: install → (lint, typecheck 병렬) → test → build
Level 0: install
Level 1: lint + typecheck (병렬, install 완료 후)
Level 2: test (lint, typecheck 모두 성공 후)
Level 3: build (test 성공 후)
```

조건부 실행: 특정 노드의 성공/실패에 따라 분기 가능.

## Git Workflow

Git 브랜치 전략을 자동화합니다.

```
# Feature Branch
git checkout -b feature/<name> → 작업 → git add → git commit → git push -u → gh pr create

# Release
git checkout -b release/<version> → 버전 범프 → 커밋 → PR → 머지 후 태그

# Hotfix
git checkout -b hotfix/<name> main → 수정 → 커밋 → PR (main + develop)
```

PR 생성 시 `gh pr create` 사용. 커밋 메시지는 Conventional Commits 형식.

## Multi-Project

모노레포 또는 여러 디렉토리에 동일 명령을 실행합니다.

```
# 실행 패턴
1. 프로젝트 디렉토리 탐지 (package.json, pyproject.toml 등)
2. 의존성 순서 분석 (있으면 토폴로지컬 정렬)
3. 독립 프로젝트는 병렬, 의존 프로젝트는 순차 실행

# 예시: 모노레포 전체 빌드
packages/shared → packages/ui → packages/app (의존성 순서)
```

## Error Handling

| 전략 | 동작 | 사용 시점 |
|------|------|----------|
| `abort` | 즉시 중단, 병렬 작업도 취소 | 빌드/배포 파이프라인 (기본값) |
| `continue` | 실패 무시, 다음 작업 계속 | 독립적인 lint/test |
| `retry` | 최대 3회 재시도 후 실패 | 네트워크/일시적 오류 |

2회 동일 전략 실패 시 → 중단하고 다른 접근법 제안 (프로젝트 디버깅 가이드라인 준수).

## Agent Delegation

작업 특성에 따라 적절한 에이전트에게 위임합니다.

```
# 위임 패턴
Agent(subagent_type="cli-worker", prompt="...")
Agent(subagent_type="test-automation-specialist", prompt="...")
Agent(subagent_type="general-purpose", prompt="...")

# 결과 집계
각 에이전트 결과를 TaskOutput으로 수집 → 통합 리포트
```

| 작업 유형 | 에이전트 |
|----------|---------|
| 단순/병렬 CLI | `cli-worker` (Haiku) |
| 테스트 | `test-automation-specialist` |
| 성능 분석 | `general-purpose` |
| 백엔드 | `backend-integration-specialist` |
| UI | `web-ui-specialist` |

## Resource Limits

| 리소스 | 값 |
|--------|-----|
| 최대 동시 실행 | 5 |
| 명령어 타임아웃 | 300s |
| 재시도 횟수 | 3 |
| 상태 디렉토리 | `~/.claude/state/cli-orchestration/` |

## Hooks

등록된 자동화 훅 (`~/.claude/settings.json`):

| Event | Script | 용도 |
|-------|--------|------|
| PreToolUse(Bash) | `pre-bash-check.sh` | CLI 세션 추적 |
| PostToolUse(Bash) | `post-bash-collect.sh` | 결과 수집 |
| Stop | `session-cleanup.sh` | 세션 정리 |

## 사용하지 말아야 할 때

- 단일 명령 또는 2-3개의 순차 Bash 호출로 끝나는 작업은 이 스킬 없이 직접 실행하라.
- 명시적인 다중 명령 동시 실행, 모노레포 전체 작업, DAG 파이프라인 맥락에서만 이 스킬을 사용한다.
- 의존성이 없는 단순 작업까지 오케스트레이션으로 감싸면 오히려 오버헤드만 늘어난다.
