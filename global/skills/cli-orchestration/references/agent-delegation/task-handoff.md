# Task Handoff Protocol

에이전트 간 작업 전달(Handoff) 프로토콜입니다.

## 개요

Task Handoff는 오케스트레이터가 서브에이전트에게 작업을 전달하고 결과를 받는 프로토콜입니다.

```
Orchestrator
    │
    ├─ [Handoff] → Agent A
    │              ↓
    │        [Execute Task]
    │              ↓
    │  ← [Return Result] ─┘
    │
    ├─ [Handoff] → Agent B (with context from A)
    │              ↓
    └─ ...
```

## Handoff 구조

### 기본 메시지 형식

```yaml
handoff:
  # 메타데이터
  id: "handoff_123"
  timestamp: "2024-01-05T10:00:00Z"
  orchestrator: "cli-orchestration"

  # 대상 에이전트
  target_agent: "test-automation-specialist"

  # 작업 정의
  task:
    type: "run_tests"
    description: "유닛 테스트 실행 및 커버리지 분석"

    # 입력 파라미터
    input:
      command: "npm test -- --coverage"
      working_dir: "./packages/frontend"

    # 기대 출력
    expected_output:
      - test_results
      - coverage_report

  # 컨텍스트
  context:
    previous_results: []
    workflow_state: {}
    environment: {}

  # 제약 조건
  constraints:
    timeout: 300000
    max_retries: 2
    priority: "normal"
```

### 결과 메시지 형식

```yaml
result:
  # 메타데이터
  handoff_id: "handoff_123"
  agent: "test-automation-specialist"
  timestamp: "2024-01-05T10:05:00Z"

  # 실행 결과
  status: "success"  # success, failure, timeout, cancelled

  # 출력 데이터
  output:
    test_results:
      passed: 142
      failed: 0
      skipped: 3
    coverage_report:
      statements: 85.2
      branches: 78.5
      functions: 90.1
      lines: 84.8

  # 실행 정보
  execution:
    duration: 45000
    exit_code: 0
    logs: [...]

  # 다음 에이전트를 위한 컨텍스트
  forward_context:
    tests_passed: true
    coverage_met: true
```

## Handoff 유형

### 1. Simple Handoff (단순 전달)

```yaml
handoff_type: simple

# 단일 작업 전달 후 결과 대기
orchestrator:
  - handoff:
      to: "test-automation-specialist"
      task: "npm test"
  - await_result
  - process_result
```

### 2. Parallel Handoff (병렬 전달)

```yaml
handoff_type: parallel

# 여러 에이전트에 동시 전달
orchestrator:
  - handoff_parallel:
      tasks:
        - to: "test-automation-specialist"
          task: "유닛 테스트"
        - to: "performance-optimizer"
          task: "번들 분석"
  - await_all_results
  - aggregate_results
```

### 3. Chained Handoff (연쇄 전달)

```yaml
handoff_type: chained

# 결과를 다음 에이전트에 전달
orchestrator:
  - handoff:
      to: "test-automation-specialist"
      task: "테스트 실행"
  - await_result
  - handoff:
      to: "performance-optimizer"
      task: "빌드 최적화"
      context:
        previous: "{{previous_result}}"
  - await_result
```

### 4. Conditional Handoff (조건부 전달)

```yaml
handoff_type: conditional

orchestrator:
  - handoff:
      to: "test-automation-specialist"
      task: "테스트 실행"
  - await_result
  - if:
      condition: "result.status == 'success'"
      then:
        handoff:
          to: "performance-optimizer"
          task: "빌드 최적화"
      else:
        handoff:
          to: "test-automation-specialist"
          task: "실패한 테스트 분석"
```

## 컨텍스트 전달

### 컨텍스트 구조

```yaml
context:
  # 이전 작업 결과
  previous_results:
    - agent: "test-automation-specialist"
      task: "테스트 실행"
      result:
        status: "success"
        output: {...}

  # 워크플로우 상태
  workflow_state:
    current_step: 3
    total_steps: 5
    started_at: "2024-01-05T10:00:00Z"

  # 공유 환경 정보
  environment:
    project_path: "/path/to/project"
    node_version: "18.17.0"
    npm_version: "9.6.7"

  # 사용자 설정
  user_preferences:
    verbose_output: true
    fail_fast: false
```

### 컨텍스트 필터링

```yaml
context_filter:
  # 다음 에이전트에 전달할 정보 선택
  include:
    - previous_results.output
    - workflow_state.current_step

  exclude:
    - previous_results.logs
    - environment.sensitive_vars

  transform:
    - path: "previous_results.output.coverage"
      to: "coverage_threshold"
```

## Task 도구 사용

### Task 호출 형식

```yaml
# Orchestrator가 Task 도구 사용
task_call:
  subagent_type: "test-automation-specialist"
  description: "테스트 실행 및 커버리지 분석"
  prompt: |
    다음 작업을 수행하세요:

    ## 작업
    유닛 테스트를 실행하고 커버리지 리포트를 생성합니다.

    ## 입력
    - 작업 디렉토리: {{working_dir}}
    - 테스트 명령어: {{test_command}}
    - 커버리지 임계값: {{coverage_threshold}}%

    ## 기대 출력
    1. 테스트 결과 요약
    2. 커버리지 퍼센트
    3. 실패한 테스트 목록 (있는 경우)

    ## 컨텍스트
    {{context}}
```

### 결과 파싱

```yaml
result_parsing:
  # 에이전트 응답에서 구조화된 데이터 추출
  patterns:
    test_results:
      regex: "Tests: (\\d+) passed, (\\d+) failed"
      groups: ["passed", "failed"]

    coverage:
      regex: "Coverage: ([\\d.]+)%"
      groups: ["percentage"]

  # 또는 JSON 블록 추출
  json_extraction:
    start_marker: "```json"
    end_marker: "```"
```

## 오류 처리

### 핸드오프 실패 처리

```yaml
error_handling:
  on_handoff_failure:
    # 재시도
    retry:
      max_attempts: 2
      delay: 5000
      backoff: "exponential"

    # 대체 에이전트
    fallback_agent: "cli-worker"

    # 에스컬레이션
    escalate:
      to: "user"
      message: "에이전트 작업 실패. 수동 개입 필요."
```

### 타임아웃 처리

```yaml
timeout_handling:
  default: 300000

  on_timeout:
    actions:
      - cancel_task: true
      - notify: "작업이 {{timeout}}ms 후 타임아웃됨"
      - return_partial: true
```

### 결과 검증

```yaml
result_validation:
  required_fields:
    - status
    - output

  schema:
    status:
      enum: ["success", "failure", "timeout"]
    output:
      type: object

  on_invalid:
    action: "retry"
    max_attempts: 1
```

## 상태 추적

### 핸드오프 상태 기계

```
PENDING → DISPATCHED → EXECUTING → COMPLETED
                          │
                          ├── FAILED
                          ├── TIMEOUT
                          └── CANCELLED
```

### 상태 모니터링

```yaml
monitoring:
  track_states:
    - pending_handoffs
    - active_handoffs
    - completed_handoffs

  metrics:
    - handoff_latency
    - agent_response_time
    - success_rate

  alerts:
    - condition: "pending_handoffs > 10"
      message: "핸드오프 백로그 증가"
```

## 예시: 전체 핸드오프 시퀀스

```yaml
workflow:
  name: "ci-pipeline-handoff"

  steps:
    # 1. 테스트 에이전트에 핸드오프
    - handoff:
        id: "h1"
        to: "test-automation-specialist"
        task:
          type: "run_tests"
          input:
            command: "npm test -- --coverage"
        timeout: 300000

    # 2. 결과 대기 및 검증
    - await:
        handoff_id: "h1"
        validation:
          required: ["test_results", "coverage"]

    # 3. 조건부 다음 핸드오프
    - conditional:
        if: "h1.result.status == 'success' AND h1.result.output.coverage >= 80"
        then:
          - handoff:
              id: "h2"
              to: "performance-optimizer"
              task:
                type: "bundle_analysis"
              context:
                tests_passed: true
                coverage: "{{h1.result.output.coverage}}"
        else:
          - handoff:
              id: "h3"
              to: "test-automation-specialist"
              task:
                type: "analyze_failures"
              context:
                failures: "{{h1.result.output.failures}}"

    # 4. 최종 결과 수집
    - collect_results:
        handoffs: ["h1", "h2", "h3"]
        aggregate: true
```
