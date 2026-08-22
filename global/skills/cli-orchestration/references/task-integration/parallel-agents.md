# Parallel Agents Protocol

Claude Code의 Agent 도구를 활용하여 여러 서브에이전트를 병렬로 실행하는 프로토콜입니다.

## 개요

```
┌─────────────────────────────────────────────────────────────┐
│                   CLI Orchestrator (Main)                    │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│   ┌──────────────┐  ┌──────────────┐  ┌──────────────┐      │
│   │   Task #1    │  │   Task #2    │  │   Task #3    │      │
│   │ (Subagent A) │  │ (Subagent B) │  │ (Subagent C) │      │
│   │              │  │              │  │              │      │
│   │ npm build    │  │ npm test     │  │ npm lint     │      │
│   └──────┬───────┘  └──────┬───────┘  └──────┬───────┘      │
│          │                 │                 │               │
│          └─────────────────┼─────────────────┘               │
│                            ▼                                 │
│                    ┌───────────────┐                         │
│                    │ Result Merger │                         │
│                    └───────────────┘                         │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

## 에이전트 유형별 CLI 역할

| 에이전트 | CLI 작업 | 병렬화 가능 |
|----------|----------|-------------|
| `test-automation-specialist` | `npm test`, `npm run coverage` | Yes |
| `general-purpose` | `npm run analyze`, `lighthouse` | Yes |
| `api-architect` | `docker-compose`, `npm run typecheck` | Partial |
| `Bash` (기본) | 모든 CLI 명령어 | Yes |

## 병렬 실행 전략

### 1. 독립 작업 병렬화

의존성이 없는 작업들을 동시에 실행:

```yaml
parallel_execution:
  tasks:
    - agent: "Bash"
      command: "npm run lint"

    - agent: "Bash"
      command: "npm run typecheck"

    - agent: "Bash"
      command: "npm run test"

  max_concurrent: 3
  fail_fast: true  # 하나 실패 시 전체 중단
```

### 2. 전문 에이전트 분배

작업 특성에 맞는 에이전트 할당:

```yaml
specialized_distribution:
  tasks:
    - task: "테스트 실행 및 커버리지 분석"
      agent: "test-automation-specialist"
      model: "haiku"  # 빠른 모델

    - task: "빌드 성능 분석"
      agent: "general-purpose"
      model: "sonnet"

    - task: "타입체크 및 Docker 빌드"
      agent: "api-architect"
      model: "haiku"
```

### 3. 팬아웃/팬인 패턴

```yaml
fan_out_fan_in:
  # Fan-out: 여러 에이전트에 분배
  fan_out:
    projects:
      - "packages/frontend"
      - "packages/backend"
      - "packages/shared"
    task_per_project: "npm run build"

  # Fan-in: 결과 통합
  fan_in:
    strategy: "wait_all"
    merge: "aggregate_results"
```

## 구현 패턴

### 병렬 호출: Bash 인가 Agent 인가

순수 CLI 명령은 서브에이전트가 필요 없다 — Bash 호출을 한 메시지에 모아 병렬 실행한다
(`subagent_type` 에는 도구 이름이 올 수 없다):

```yaml
# 단일 메시지에서 여러 Bash 도구 호출
parallel_bash_calls:
  - tool: Bash
    params:
      command: "cd packages/frontend && npm run build"
      description: "Frontend 빌드"
      run_in_background: true

  - tool: Bash
    params:
      command: "cd packages/backend && npm run build"
      description: "Backend 빌드"
      run_in_background: true

  - tool: Bash
    params:
      command: "cd packages/shared && npm run build"
      description: "Shared 빌드"
      run_in_background: true
```

조사·구현처럼 판단이 필요한 작업만 Agent 로 위임한다:

```yaml
parallel_agent_calls:
  - tool: Agent
    params:
      subagent_type: "cli-worker"
      description: "빌드 실패 원인 조사"
      prompt: "packages/backend 빌드 로그를 분석해 실패 원인을 특정하세요"
```

### 결과 수집

```yaml
result_collection:
  # 백그라운드 작업 결과 조회
  polling:
    tool: "TaskOutput"
    params:
      task_id: "{task_id}"
      block: true  # 완료까지 대기
      timeout: 300000  # 5분

  # 전체 완료 확인
  completion_check:
    strategy: "poll_all"
    interval: 1000ms
```

## 에러 처리

### 부분 실패 처리

```yaml
error_handling:
  partial_failure:
    strategy: "continue_others"  # 다른 작업 계속

    on_completion:
      success_count: 2
      failure_count: 1
      action: "report_partial_success"

  total_failure:
    strategy: "abort_all"
    cleanup: true
```

### 재시도 로직

```yaml
retry_logic:
  # 에이전트별 재시도 설정
  per_agent:
    "Bash":
      max_retries: 3
      backoff: "exponential"

    "test-automation-specialist":
      max_retries: 2
      backoff: "linear"
```

## 리소스 관리

### 동시성 제어

```yaml
concurrency:
  # 전체 제한
  global_max: 5

  # 에이전트 타입별 제한
  per_type:
    "Bash": 3
    "test-automation-specialist": 1
    "general-purpose": 1

  # 리소스 기반 제한
  resource_based:
    memory_threshold: "4GB"
    cpu_threshold: 80%
```

### 우선순위

```yaml
priority:
  rules:
    - agent: "Bash"
      command_pattern: "npm install"
      priority: "high"  # 의존성 설치 우선

    - agent: "test-automation-specialist"
      priority: "normal"

    - agent: "general-purpose"
      priority: "low"  # 분석은 마지막
```

## 상태 모니터링

### 진행 상황 집계

```yaml
progress_aggregation:
  display:
    format: "summary"

    # 예시 출력
    template: |
      Parallel Execution Status
      ─────────────────────────
      [OK] frontend-build: Complete (23s)
      [>>] backend-build: Building... 67%
      [>>] shared-build: Compiling... 45%
      [..] deploy: Waiting (depends: frontend, backend)

      Overall: 1/4 complete, 2 running, 1 pending
```

### 이벤트 알림

```yaml
notifications:
  events:
    - type: "task_complete"
      action: "log"

    - type: "task_failed"
      action: "alert"

    - type: "all_complete"
      action: "summary_report"
```

## 모범 사례

### DO
- 독립적인 작업은 항상 병렬로 실행
- 가벼운 작업에는 `haiku` 모델 사용
- 백그라운드 실행으로 메인 스레드 차단 방지
- 실패 시 부분 성공 결과도 보존

### DON'T
- 의존성 있는 작업을 병렬로 실행하지 않음
- 무제한 동시 실행으로 리소스 고갈
- 에러 무시하고 계속 진행
- 결과 수집 없이 작업 종료
