# Agent Delegation Patterns

CLI 오케스트레이션에서 에이전트 위임을 위한 패턴과 전략입니다.

## 개요

에이전트 위임은 작업의 특성에 따라 적절한 에이전트에게 작업을 분배하는 패턴입니다.

```
CLI Orchestration Skill (워크플로우 정의)
    │
    ├── Direct Bash → 단순 CLI 명령
    ├── Agent(cli-worker) → 병렬 CLI 작업
    └── Agent(specialist) → 도메인별 전문 에이전트
```

## 위임 패턴 유형

### 1. Direct Execution (직접 실행)

단순한 CLI 명령은 Bash 도구로 직접 실행합니다.

**적합한 작업:**
- 파일 시스템 조작 (`ls`, `cp`, `mv`)
- Git 기본 명령 (`git status`, `git add`)
- 단일 명령어 실행

```yaml
pattern: direct
tool: Bash

examples:
  - command: "npm install"
  - command: "git status"
  - command: "ls -la"
```

**위임 기준:**
```yaml
direct_execution:
  criteria:
    - single_command: true
    - no_parallelism: true
    - simple_output: true
    - execution_time: "< 30s"
```

### 2. Worker Delegation (워커 위임)

병렬 실행이 필요하거나 복잡한 CLI 작업은 cli-worker 에이전트에 위임합니다.

**적합한 작업:**
- 병렬 빌드 (`npm run build:*`)
- 멀티 프로젝트 명령어
- 장시간 실행 작업

```yaml
pattern: worker
agent: cli-worker

examples:
  - task: "frontend, backend 동시 빌드"
  - task: "모든 패키지에 lint 실행"
```

**위임 기준:**
```yaml
worker_delegation:
  criteria:
    - parallel_tasks: ">= 2"
    - multi_directory: true
    - long_running: "> 1min"
    - complex_output_aggregation: true
```

### 3. Specialist Delegation (전문가 위임)

도메인 전문 지식이 필요한 작업은 전문 에이전트에 위임합니다.

**적합한 작업:**
- 테스트 작성 및 실행
- 성능 분석
- 백엔드 통합
- UI 개발

```yaml
pattern: specialist
agents:
  - test-automation-specialist
  - general-purpose
  - api-architect
  - ui-developer
```

## 에이전트 선택 매트릭스

| 작업 유형 | 복잡도 | 추천 에이전트 | 위임 패턴 |
|----------|--------|--------------|----------|
| 단순 CLI | 낮음 | Bash | Direct |
| 병렬 빌드 | 중간 | cli-worker | Worker |
| 테스트 실행 | 중간 | test-automation-specialist | Specialist |
| 커버리지 분석 | 높음 | test-automation-specialist | Specialist |
| 번들 최적화 | 높음 | general-purpose | Specialist |
| API 구현 | 높음 | api-architect | Specialist |
| UI 컴포넌트 | 높음 | ui-developer | Specialist |

## 위임 결정 로직

### 자동 선택 알고리즘

```yaml
delegation_logic:
  steps:
    # 1. 단순 명령 체크
    - check: "is_simple_command"
      true:
        agent: "Bash"
        pattern: "direct"
      false: continue

    # 2. 병렬 작업 체크
    - check: "requires_parallelism"
      true:
        agent: "cli-worker"
        pattern: "worker"
      false: continue

    # 3. 도메인 매칭
    - check: "domain_type"
      test:
        agent: "test-automation-specialist"
      performance:
        agent: "general-purpose"
      backend:
        agent: "api-architect"
      frontend:
        agent: "ui-developer"
      default:
        agent: "cli-worker"
```

### 키워드 기반 매칭

```yaml
keyword_matching:
  test-automation-specialist:
    keywords: ["test", "테스트", "coverage", "커버리지", "jest", "vitest"]
    commands: ["npm test", "npm run test:*", "npx jest"]

  general-purpose:
    keywords: ["성능", "performance", "bundle", "번들", "optimize", "최적화"]
    commands: ["npm run analyze", "npm run lighthouse"]

  api-architect:
    keywords: ["api", "backend", "서버", "database", "db"]
    commands: ["npm run typecheck", "docker-compose"]

  ui-developer:
    keywords: ["ui", "컴포넌트", "component", "스타일", "style"]
    commands: ["npm run storybook", "npm run dev"]
```

## 위임 템플릿

### 단일 에이전트 위임

```yaml
delegate:
  to: "test-automation-specialist"
  task: "모든 테스트 실행하고 커버리지 리포트 생성"

  context:
    project_path: "./packages/frontend"
    test_framework: "vitest"

  expected_output:
    - test_results
    - coverage_report
    - failure_summary
```

### 복수 에이전트 병렬 위임

```yaml
delegate:
  parallel: true

  tasks:
    - agent: "test-automation-specialist"
      task: "유닛 테스트 실행"

    - agent: "general-purpose"
      task: "번들 크기 분석"

    - agent: "api-architect"
      task: "API 타입 체크"

  aggregate_results: true
  timeout: 300000
```

### 순차 위임 (파이프라인)

```yaml
delegate:
  sequential: true

  pipeline:
    - agent: "test-automation-specialist"
      task: "테스트 실행"
      pass_result_to_next: true

    - agent: "general-purpose"
      task: "테스트 통과한 빌드 최적화"
      condition: "previous.success"
```

## 에이전트별 위임 프로토콜

### test-automation-specialist

```yaml
agent: test-automation-specialist
capabilities:
  - run_tests
  - generate_coverage
  - identify_flaky_tests
  - suggest_new_tests

delegation:
  input:
    test_command: string
    coverage_threshold: number
    test_files: [string]

  output:
    passed: boolean
    coverage: number
    failures: [TestFailure]
    suggestions: [string]
```

### general-purpose

```yaml
agent: general-purpose
capabilities:
  - bundle_analysis
  - code_splitting
  - tree_shaking
  - lazy_loading

delegation:
  input:
    build_command: string
    analyze_command: string
    targets: [string]

  output:
    bundle_size: BundleReport
    recommendations: [Recommendation]
    optimizations_applied: [string]
```

### api-architect

```yaml
agent: api-architect
capabilities:
  - api_development
  - database_operations
  - docker_management
  - type_checking

delegation:
  input:
    task_type: string  # api, db, docker, typecheck
    target_files: [string]

  output:
    status: string
    errors: [Error]
    artifacts: [string]
```

### ui-developer

```yaml
agent: ui-developer
capabilities:
  - component_development
  - styling
  - responsive_design
  - accessibility

delegation:
  input:
    component_type: string
    design_specs: DesignSpec

  output:
    files_created: [string]
    preview_url: string
    accessibility_score: number
```

## 오류 처리

### 위임 실패 처리

```yaml
error_handling:
  on_agent_failure:
    retry:
      max_attempts: 2
      delay: 5000

    fallback:
      - try_alternative_agent: true
      - escalate_to_user: true

    notification:
      message: "에이전트 {{agent}} 작업 실패: {{error}}"
```

### 타임아웃 처리

```yaml
timeout_handling:
  default_timeout: 300000  # 5분

  per_agent:
    test-automation-specialist: 600000  # 10분
    general-purpose: 300000        # 5분

  on_timeout:
    cancel_task: true
    notify_user: true
    return_partial_results: true
```

## 모니터링

### 위임 상태 추적

```yaml
monitoring:
  track:
    - delegation_start_time
    - agent_assigned
    - task_progress
    - completion_time
    - result_status

  reporting:
    format: "progress_bar"
    update_interval: 5000
```

### 결과 집계

```yaml
result_aggregation:
  parallel_tasks:
    strategy: "collect_all"  # 또는 "fail_fast"

  format:
    summary: true
    detailed_per_agent: true
    combined_output: true
```
