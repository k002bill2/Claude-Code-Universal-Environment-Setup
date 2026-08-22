# Result Aggregation

여러 에이전트의 결과를 집계하고 통합하는 프로토콜입니다.

## 개요

Result Aggregation은 병렬 또는 순차로 실행된 여러 에이전트의 결과를 수집, 병합, 분석하여 통합된 결과를 생성합니다.

```
Agent A ─┐
Agent B ─┼── Aggregator ── Unified Result
Agent C ─┘
```

## 집계 전략

### 1. Collect All (모두 수집)

모든 결과를 수집한 후 처리합니다.

```yaml
aggregation:
  strategy: collect_all

  # 모든 에이전트 완료 대기
  wait_for: all

  # 실패해도 계속 수집
  continue_on_failure: true

  result:
    agents:
      - name: "test-automation-specialist"
        status: "success"
        output: {...}
      - name: "general-purpose"
        status: "success"
        output: {...}
    overall_status: "success"
```

### 2. Fail Fast (빠른 실패)

하나라도 실패하면 즉시 중단합니다.

```yaml
aggregation:
  strategy: fail_fast

  # 첫 실패 시 중단
  on_first_failure: abort_all

  # 실행 중인 에이전트 취소
  cancel_running: true
```

### 3. Majority Vote (다수결)

결과의 다수결로 최종 결과를 결정합니다.

```yaml
aggregation:
  strategy: majority_vote

  # 동일한 결과가 과반수면 채택
  threshold: 0.5

  # 동률 시 처리
  on_tie: "first_completed"
```

### 4. Weighted (가중치)

에이전트별 가중치를 적용합니다.

```yaml
aggregation:
  strategy: weighted

  weights:
    test-automation-specialist: 0.4
    general-purpose: 0.3
    api-architect: 0.3

  # 가중 평균 계산
  scoring: "weighted_average"
```

## 결과 병합

### 기본 병합

```yaml
merge:
  # 동일 키 충돌 시 전략
  conflict_resolution: "last_wins"  # first_wins, merge_arrays, error

  # 깊은 병합
  deep_merge: true

  # 배열 처리
  array_strategy: "concat"  # concat, replace, unique
```

### 선택적 병합

```yaml
merge:
  select:
    # 특정 에이전트의 특정 필드만
    - from: "test-automation-specialist"
      fields: ["test_results", "coverage"]

    - from: "general-purpose"
      fields: ["bundle_size", "recommendations"]
```

### 변환 병합

```yaml
merge:
  transform:
    # 결과 변환 후 병합
    - source: "test-automation-specialist.coverage"
      target: "quality_metrics.test_coverage"

    - source: "general-purpose.bundle_size"
      target: "quality_metrics.bundle_size"
```

## 결과 구조

### 집계 결과 형식

```yaml
aggregated_result:
  # 메타데이터
  metadata:
    aggregation_id: "agg_123"
    timestamp: "2024-01-05T10:10:00Z"
    strategy: "collect_all"

  # 전체 상태
  overall:
    status: "success"  # success, partial_success, failure
    duration: 150000
    agents_completed: 3
    agents_failed: 0

  # 개별 에이전트 결과
  agents:
    - name: "test-automation-specialist"
      status: "success"
      duration: 45000
      output:
        test_results:
          passed: 142
          failed: 0
        coverage: 85.2

    - name: "general-purpose"
      status: "success"
      duration: 30000
      output:
        bundle_size: 245000
        recommendations: [...]

    - name: "api-architect"
      status: "success"
      duration: 25000
      output:
        type_errors: 0
        api_health: "healthy"

  # 병합된 출력
  merged_output:
    quality_metrics:
      test_coverage: 85.2
      bundle_size: 245000
      type_safety: true

    recommendations:
      - "번들 크기 10% 감소 가능"
      - "unused import 제거 권장"

  # 요약
  summary:
    all_checks_passed: true
    quality_score: 92
    action_items: 2
```

## 분석 기능

### 상태 분석

```yaml
analysis:
  status:
    # 전체 성공 여부
    all_success: true

    # 부분 성공
    partial_success: false
    partial_success_agents: []

    # 실패
    failures: false
    failed_agents: []
```

### 성능 분석

```yaml
analysis:
  performance:
    # 총 실행 시간
    total_duration: 150000

    # 병렬 효율
    parallel_efficiency: 0.85

    # 병목
    bottleneck: "test-automation-specialist"

    # 에이전트별 시간
    durations:
      test-automation-specialist: 45000
      general-purpose: 30000
      api-architect: 25000
```

### 품질 분석

```yaml
analysis:
  quality:
    # 품질 점수 (가중 평균)
    score: 92

    # 항목별 점수
    breakdown:
      test_coverage: 85
      bundle_size: 95
      type_safety: 100

    # 개선 필요 항목
    needs_improvement:
      - metric: "test_coverage"
        current: 85
        target: 90
        gap: 5
```

## 출력 형식

### Summary 형식

```yaml
output_format: summary

result: |
  ## 실행 결과 요약

  | 에이전트 | 상태 | 시간 |
  |---------|------|------|
  | test-automation-specialist | Success | 45s |
  | general-purpose | Success | 30s |
  | api-architect | Success | 25s |

  ### 품질 점수: 92/100

  - Test Coverage: 85.2%
  - Bundle Size: 245KB
  - Type Errors: 0
```

### Detailed 형식

```yaml
output_format: detailed

result:
  # 전체 구조화된 결과 반환
  include:
    - metadata
    - agents
    - merged_output
    - analysis
```

### Action Items 형식

```yaml
output_format: action_items

result:
  items:
    - priority: high
      agent: "test-automation-specialist"
      action: "커버리지 90% 달성을 위해 5개 파일 테스트 추가 필요"

    - priority: medium
      agent: "general-purpose"
      action: "lodash를 lodash-es로 교체하여 10KB 감소 가능"
```

## 오류 집계

### 오류 수집

```yaml
error_aggregation:
  collect:
    - agent: "test-automation-specialist"
      errors:
        - type: "test_failure"
          message: "2 tests failed"
          details: [...]

    - agent: "api-architect"
      errors:
        - type: "type_error"
          message: "3 type errors found"
          details: [...]
```

### 오류 우선순위

```yaml
error_prioritization:
  rules:
    - type: "security"
      priority: 1
    - type: "type_error"
      priority: 2
    - type: "test_failure"
      priority: 3
    - type: "warning"
      priority: 4
```

## 예시: 완전한 집계 워크플로우

```yaml
workflow:
  name: "quality-check-aggregation"

  # 1. 병렬 실행
  parallel_execution:
    - agent: "test-automation-specialist"
      task: "테스트 실행"

    - agent: "general-purpose"
      task: "번들 분석"

    - agent: "api-architect"
      task: "타입 체크"

  # 2. 결과 수집
  aggregation:
    strategy: collect_all
    continue_on_failure: true
    timeout: 300000

  # 3. 결과 병합
  merge:
    strategy: selective
    select:
      - from: "test-automation-specialist"
        fields: ["test_results", "coverage"]
      - from: "general-purpose"
        fields: ["bundle_size", "recommendations"]
      - from: "api-architect"
        fields: ["type_errors"]

  # 4. 분석
  analysis:
    calculate:
      - quality_score
      - performance_metrics
      - action_items

  # 5. 출력
  output:
    format: summary
    include_action_items: true

    # 조건부 알림
    notify:
      if: "quality_score < 80"
      channel: "slack"
      message: "품질 점수가 기준 이하입니다: {{quality_score}}"
```

## 집계 결과 활용

### 후속 작업 결정

```yaml
post_aggregation:
  decision:
    - if: "all_success AND quality_score >= 90"
      action: "proceed_to_deploy"

    - if: "partial_success"
      action: "review_failures"

    - if: "quality_score < 80"
      action: "block_merge"
```

### 리포트 생성

```yaml
reporting:
  generate:
    - type: "markdown"
      path: "reports/quality-{{timestamp}}.md"

    - type: "json"
      path: "reports/metrics-{{timestamp}}.json"

    - type: "html"
      path: "reports/dashboard-{{timestamp}}.html"
```
