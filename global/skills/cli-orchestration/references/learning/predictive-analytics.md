# Predictive Analytics Protocol

CLI 실행 시간 예측과 실패 가능성 분석을 위한 프로토콜입니다.

## 예측 모델

### 1. 실행 시간 예측

```yaml
duration_prediction:
  model: "weighted_ensemble"

  features:
    static:
      - command_type
      - project_size
      - dependency_count

    dynamic:
      - files_changed
      - time_since_last_run
      - cache_state

    environmental:
      - system_load
      - available_memory
      - ci_environment
```

#### 예측 알고리즘

```yaml
prediction_algorithm:
  # 가중 평균 모델
  components:
    historical_average:
      weight: 0.4
      window: "last_20_runs"

    recent_trend:
      weight: 0.3
      window: "last_5_runs"

    contextual_adjustment:
      weight: 0.2
      factors:
        - cache_hit: -0.3   # 캐시 있으면 30% 감소
        - ci_env: +0.2      # CI 환경 20% 증가
        - many_changes: +0.15  # 변경 많으면 15% 증가

    time_of_day:
      weight: 0.1
      adjustments:
        peak_hours: +0.1
        off_hours: -0.05
```

### 2. 실패 확률 예측

```yaml
failure_prediction:
  model: "logistic_regression"

  features:
    # 과거 실패 이력
    - recent_failure_rate        # 최근 10회 실패율
    - consecutive_failures       # 연속 실패 횟수

    # 코드 변경
    - lines_changed              # 변경 라인 수
    - files_in_critical_paths    # 핵심 파일 변경 여부

    # 환경 요인
    - time_since_deps_update     # 의존성 업데이트 후 경과 시간
    - unresolved_conflicts       # 미해결 충돌

  output:
    probability: 0.15  # 15% 실패 확률
    confidence: 0.82   # 82% 예측 신뢰도
    risk_level: "low"  # low, medium, high
```

### 3. 다음 명령어 예측

```yaml
next_command_prediction:
  model: "markov_chain"

  # 상태 전이 확률
  transition_matrix:
    "npm install":
      "npm run build": 0.45
      "npm run lint": 0.30
      "npm test": 0.15
      "other": 0.10

    "npm run lint":
      "npm run typecheck": 0.40
      "npm test": 0.35
      "npm run build": 0.20
      "other": 0.05

  # 컨텍스트 강화
  context_boost:
    - condition: "part_of_workflow"
      boost_next_in_workflow: +0.3
    - condition: "error_occurred"
      boost_retry_command: +0.5
```

## 예측 출력

### 실행 전 예측 보고서

```
╔══════════════════════════════════════════════════════════════╗
║              Prediction Report: npm run build                 ║
╠══════════════════════════════════════════════════════════════╣
║                                                               ║
║  Estimated Duration: 58s (±12s)                               ║
║  ████████████████████░░░░░░░░░░░░░░░░░░░░  Confidence: 85%   ║
║                                                               ║
║  Failure Risk: LOW (8%)                                       ║
║  ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░                    ║
║                                                               ║
║  Factors:                                                     ║
║  + Cache available: -15s expected                             ║
║  + Recent success streak: 5 runs                              ║
║  - Files changed: 12 (slight increase)                        ║
║                                                               ║
║  Suggested Parallelization:                                   ║
║  > Can run with 'npm run lint' (saves ~8s)                    ║
║                                                               ║
╚══════════════════════════════════════════════════════════════╝
```

### 리스크 알림

```yaml
risk_alerts:
  thresholds:
    low: 0.10
    medium: 0.25
    high: 0.50

  alerts:
    medium:
      message: "중간 실패 위험 ({probability}%)"
      suggestion: "변경사항을 검토하세요"

    high:
      message: "높은 실패 위험 ({probability}%)"
      suggestions:
        - "먼저 린트/타입체크 실행 권장"
        - "최근 실패 원인 확인"
        - "작은 단위로 테스트 후 전체 빌드"
```

## 정확도 측정

### 예측 vs 실제 비교

```yaml
accuracy_metrics:
  duration:
    mae: 8.5        # 평균 절대 오차 (초)
    mape: 12.3%     # 평균 절대 백분율 오차
    within_20%: 0.85  # 20% 오차 내 비율

  failure:
    accuracy: 0.88
    precision: 0.75   # 실패 예측 정확도
    recall: 0.82      # 실제 실패 감지율
    f1_score: 0.78
```

### 모델 개선

```yaml
model_improvement:
  # 자동 재학습
  auto_retrain:
    trigger:
      - "accuracy drops below 80%"
      - "every 100 new executions"

  # 피처 중요도 분석
  feature_importance:
    - { feature: "recent_failure_rate", importance: 0.35 }
    - { feature: "files_changed", importance: 0.25 }
    - { feature: "cache_state", importance: 0.20 }
    - { feature: "time_since_deps_update", importance: 0.12 }
    - { feature: "system_load", importance: 0.08 }
```

## 고급 예측

### 워크플로우 완료 시간

```yaml
workflow_completion:
  workflow: "CI Pipeline"

  predictions:
    sequential_time: 140s
    parallel_time: 85s

    breakdown:
      - step: "npm install"
        predicted: 15s
        can_parallel: false

      - step: "lint + typecheck"
        predicted: 12s
        parallel: true

      - step: "test"
        predicted: 45s

      - step: "build"
        predicted: 60s

  confidence: 0.82
```

### 리소스 사용량 예측

```yaml
resource_prediction:
  command: "npm run build"

  predictions:
    peak_memory_mb: 850 (±150)
    cpu_usage_percent: 85 (±10)
    disk_io_mb: 200 (±50)

  recommendations:
    - "현재 가용 메모리: 2GB - 충분"
    - "다른 빌드와 병렬 실행 가능"
```

### 실패 원인 예측

```yaml
failure_cause_prediction:
  command: "npm test"

  if_fails_likely_causes:
    - cause: "Test timeout"
      probability: 0.35
      evidence: "Recent long-running tests"

    - cause: "Type mismatch"
      probability: 0.30
      evidence: "TypeScript files changed"

    - cause: "Missing mock"
      probability: 0.20
      evidence: "New API integration added"

  suggested_preventions:
    - "npm run typecheck 먼저 실행"
    - "변경된 파일 관련 테스트만 실행"
```

## 예측 캐싱

```yaml
prediction_caching:
  # 캐시 전략
  cache:
    duration_predictions:
      key: "{command}_{project_hash}_{env_hash}"
      ttl: "1h"

    failure_predictions:
      key: "{command}_{files_changed_hash}"
      ttl: "30m"

  # 무효화 조건
  invalidation:
    - "new execution completed"
    - "environment changed"
    - "significant file changes"
```

## 사용자 인터페이스

### 예측 표시 옵션

```yaml
display_options:
  # 기본: 간단한 예측
  minimal:
    show: "estimated_duration"
    format: "~60s"

  # 상세: 전체 예측 리포트
  detailed:
    show:
      - duration_with_confidence
      - failure_risk
      - factors
      - suggestions

  # 비활성화
  disabled:
    show: none

  # 설정
  default: "minimal"
  show_on_long_tasks: true  # 30초 이상 예상 시 자동 표시
```

### 예측 피드백

```yaml
feedback:
  after_completion:
    show: "prediction_accuracy"
    format: "예측: 60s, 실제: 58s (정확도: 97%)"

  collect_feedback:
    prompt: "예측이 도움이 되었나요?"
    options: ["예", "아니오", "피드백 없음"]
```
