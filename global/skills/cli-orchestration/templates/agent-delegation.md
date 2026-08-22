# Agent Delegation Template

에이전트 위임 워크플로우 템플릿입니다.

## 템플릿 정의

```yaml
delegation:
  name: "{{workflow_name}}"
  description: "{{description}}"

  tasks:
    {{#each tasks}}
    - agent: "{{this.agent}}"
      task: "{{this.task}}"
      {{#if this.input}}
      input:
        {{#each this.input}}
        {{@key}}: {{this}}
        {{/each}}
      {{/if}}
      {{#if this.timeout}}
      timeout: {{this.timeout}}
      {{/if}}
    {{/each}}

  execution: "{{execution | parallel}}"
  aggregate_results: {{aggregate | true}}
```

## 사용 예시

### 1. 품질 검사 위임

```yaml
delegation:
  name: "quality-check"
  description: "코드 품질 종합 검사"

  tasks:
    - agent: "test-automation-specialist"
      task: |
        다음 작업을 수행하세요:
        1. 모든 테스트 실행
        2. 커버리지 리포트 생성
        3. 실패한 테스트 분석

      input:
        test_command: "npm test -- --coverage"
        coverage_threshold: 80

      timeout: 600000

    - agent: "general-purpose"
      task: |
        번들 분석을 수행하세요:
        1. 번들 크기 측정
        2. 청크 분석
        3. 최적화 권장사항

      input:
        build_command: "npm run build"
        analyze_command: "npm run analyze"

      timeout: 300000

    - agent: "api-architect"
      task: |
        타입 안전성을 검사하세요:
        1. TypeScript 체크
        2. API 스키마 검증

      input:
        typecheck_command: "npm run typecheck"

      timeout: 120000

  execution: parallel
  aggregate_results: true

  output:
    format: summary
    include:
      - quality_score
      - action_items
      - recommendations
```

### 2. 빌드 파이프라인 위임

```yaml
delegation:
  name: "build-pipeline"
  description: "풀스택 빌드 파이프라인"

  tasks:
    # Phase 1: 병렬 테스트
    - phase: 1
      parallel:
        - agent: "test-automation-specialist"
          task: "프론트엔드 테스트 실행"
          input:
            working_dir: "./packages/frontend"

        - agent: "test-automation-specialist"
          task: "백엔드 테스트 실행"
          input:
            working_dir: "./packages/backend"

    # Phase 2: 조건부 빌드
    - phase: 2
      condition: "phase_1.all_success"
      parallel:
        - agent: "ui-developer"
          task: "프론트엔드 빌드"
          input:
            command: "npm run build"
            optimize: true

        - agent: "api-architect"
          task: "백엔드 빌드"
          input:
            command: "npm run build"

    # Phase 3: 통합 검증
    - phase: 3
      condition: "phase_2.all_success"
      sequential:
        - agent: "test-automation-specialist"
          task: "E2E 테스트 실행"

  execution: phased
  aggregate_results: true
```

### 3. 코드 리뷰 위임

```yaml
delegation:
  name: "code-review"
  description: "자동 코드 리뷰"

  context:
    pr_number: "{{pr_number}}"
    changed_files: "{{changed_files}}"

  tasks:
    - agent: "test-automation-specialist"
      task: |
        PR의 테스트 커버리지를 분석하세요:
        1. 변경된 파일의 테스트 커버리지 확인
        2. 누락된 테스트 케이스 식별
        3. 테스트 추가 권장사항

    - agent: "general-purpose"
      task: |
        PR의 성능 영향을 분석하세요:
        1. 번들 크기 변화
        2. 렌더링 성능 영향
        3. 최적화 기회

    - agent: "api-architect"
      task: |
        PR의 타입 안전성을 검토하세요:
        1. 타입 변경 사항
        2. API 호환성
        3. 스키마 변경

  execution: parallel
  aggregate_results: true

  output:
    format: review_comment
    post_to_pr: true
```

## CLI 명령어

### 단일 에이전트 위임

```bash
# 테스트 에이전트에 위임
"test-automation-specialist한테 테스트 실행 시켜줘"

# 성능 분석 에이전트에 위임
"general-purpose로 번들 분석해줘"

# 상세 지시
"test-automation-specialist에게 커버리지 80% 이상 확인하도록 위임해줘"
```

### 복수 에이전트 병렬 위임

```bash
# 병렬 품질 검사
"테스트, 성능 분석, 타입 체크 병렬로 실행해줘"

# 에이전트 지정
"test-automation-specialist와 general-purpose 동시에 실행해줘"
```

### 순차 위임

```bash
# 순차 파이프라인
"테스트 통과하면 빌드하고, 빌드 성공하면 배포 준비해줘"
```

## 에이전트 선택 가이드

| 작업 | 추천 에이전트 | 용도 |
|------|--------------|------|
| 테스트 실행 | test-automation-specialist | 유닛/E2E 테스트 |
| 커버리지 분석 | test-automation-specialist | 테스트 커버리지 |
| 번들 최적화 | general-purpose | 번들 크기, 청킹 |
| 성능 분석 | general-purpose | 런타임 성능 |
| API 개발 | api-architect | FastAPI, DB |
| 타입 체크 | api-architect | TypeScript |
| UI 개발 | ui-developer | React 컴포넌트 |
| 스타일링 | ui-developer | TailwindCSS |

## 결과 집계

### 집계 전략

```yaml
aggregation:
  strategy: collect_all

  scoring:
    test-automation-specialist:
      weight: 0.4
      metrics: [test_pass_rate, coverage]

    general-purpose:
      weight: 0.3
      metrics: [bundle_size, load_time]

    api-architect:
      weight: 0.3
      metrics: [type_safety, api_health]

  output:
    quality_score:
      formula: "weighted_average(all_metrics)"
      threshold: 80

    action_items:
      collect_from: all
      priority: by_severity
```

### 출력 형식

```yaml
output:
  format: detailed

  sections:
    - summary:
        quality_score: 85
        status: "passed"

    - by_agent:
        - agent: "test-automation-specialist"
          status: "success"
          metrics:
            tests_passed: 142
            coverage: 82%

        - agent: "general-purpose"
          status: "success"
          metrics:
            bundle_size: "245KB"
            recommendations: 3

        - agent: "api-architect"
          status: "success"
          metrics:
            type_errors: 0

    - action_items:
        - priority: medium
          description: "커버리지 90%까지 8% 증가 필요"
        - priority: low
          description: "lodash-es 마이그레이션 권장"
```

## 오류 처리

### 에이전트 실패 처리

```yaml
error_handling:
  on_agent_failure:
    retry:
      max: 2
      delay: 5000

    fallback:
      test-automation-specialist: "cli-worker"
      general-purpose: "Bash"

    escalate:
      to: user
      after: 2_failures
```

### 타임아웃 처리

```yaml
timeout:
  default: 300000

  per_agent:
    test-automation-specialist: 600000
    general-purpose: 300000

  on_timeout:
    cancel: true
    return_partial: true
    notify: true
```

## 모니터링

```yaml
monitoring:
  display:
    - active_agents
    - completed_tasks
    - current_progress
    - estimated_time

  format: |
    Delegation Progress
    ━━━━━━━━━━━━━━━━━━━━
    Active: {{active_agents}}
    Completed: {{completed}}/{{total}}

    {{#each agents}}
    [{{status_icon}}] {{name}}: {{status}}
    {{/each}}
```
