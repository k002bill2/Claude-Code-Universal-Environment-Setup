# Progress Tracking Protocol

CLI 작업의 진행 상황을 추적하고 예측하는 프로토콜입니다.

## 진행률 감지

### 1. 명시적 진행률

출력에서 직접 진행률을 파싱:

```yaml
explicit_patterns:
  # 퍼센트 패턴
  - regex: '(\d+)%'
    type: percentage

  # N/M 패턴
  - regex: '\[(\d+)/(\d+)\]'
    type: fraction

  # 단계 패턴
  - regex: 'Step (\d+) of (\d+)'
    type: steps
```

### 2. 추론 진행률

출력 패턴으로 진행률 추정:

```yaml
inferred_progress:
  npm_install:
    phases:
      - pattern: "npm WARN"
        progress: 10-30%
      - pattern: "added \\d+ packages"
        progress: 90%
      - pattern: "up to date"
        progress: 100%

  webpack_build:
    phases:
      - pattern: "Compiling"
        progress: 10%
      - pattern: "Building"
        progress: 30%
      - pattern: "Optimizing"
        progress: 70%
      - pattern: "Emitting"
        progress: 90%
```

### 3. 시간 기반 추정

히스토리 데이터로 진행률 추정:

```yaml
time_based_estimation:
  enabled: true

  # 과거 실행 시간 활용
  history_weight: 0.7
  current_weight: 0.3

  # 신뢰도 표시
  confidence_threshold: 0.8
  show_uncertainty: true  # ~45s (±10s)
```

## 도구별 진행률 파서

### npm/pnpm/yarn

```yaml
npm:
  install:
    - pattern: "reify:(.+): timing"
      type: package_progress
    - pattern: "idealTree:(.+): timing"
      type: tree_progress

  build:
    - pattern: "webpack (\d+)%"
      type: webpack
    - pattern: "vite: (\d+)%"
      type: vite
```

### pytest

```yaml
pytest:
  - pattern: '(\d+) passed'
    type: test_count
  - pattern: '(\d+)%'
    type: percentage
  - pattern: 'PASSED|FAILED'
    type: test_result

  # 테스트 수집 단계
  collection:
    - pattern: 'collected (\d+) items'
      type: total_tests
```

### Docker

```yaml
docker:
  build:
    - pattern: 'Step (\d+)/(\d+)'
      type: build_step
    - pattern: '\[(\d+)/(\d+)\]'
      type: layer_progress

  pull:
    - pattern: 'Downloading.*\[(.+)\]'
      type: download_bar
    - pattern: '(\d+\.\d+)MB/(\d+\.\d+)MB'
      type: download_size
```

## 진행 상태 머신

```
+----------+     +------------+     +-----------+
|  PENDING |---->|  RUNNING   |---->| COMPLETED |
+----------+     +------------+     +-----------+
     |                |                   |
     |                v                   |
     |           +--------+               |
     +---------->| FAILED |<--------------+
                 +--------+
                      |
                      v
                 +---------+
                 | RETRYING|
                 +---------+
```

### 상태 전이

```yaml
transitions:
  PENDING -> RUNNING:
    trigger: "process_started"

  RUNNING -> COMPLETED:
    trigger: "exit_code == 0"

  RUNNING -> FAILED:
    trigger: "exit_code != 0 OR timeout"

  FAILED -> RETRYING:
    trigger: "retry_enabled AND retry_count < max_retries"

  RETRYING -> RUNNING:
    trigger: "retry_delay_elapsed"
```

## 시간 예측

### 예측 알고리즘

```yaml
prediction:
  algorithm: "weighted_moving_average"

  factors:
    - name: "historical_average"
      weight: 0.5
    - name: "recent_runs"  # 최근 5회
      weight: 0.3
    - name: "current_pace"
      weight: 0.2

  adjustments:
    # 환경 변수에 따른 조정
    - condition: "CI=true"
      multiplier: 1.2  # CI 환경은 보통 느림
    - condition: "NODE_ENV=production"
      multiplier: 1.5  # 프로덕션 빌드는 더 오래 걸림
```

### 불확실성 표시

```
Time: 45s / ~60s (±10s)     # 신뢰도 높음
Time: 45s / ~60s (±30s)     # 신뢰도 중간
Time: 45s / ???             # 예측 불가
```

## 체크포인트

### 자동 체크포인트

```yaml
checkpoints:
  auto_save:
    enabled: true
    interval: 30s

  events:
    - "phase_complete"
    - "error_occurred"
    - "user_interrupt"

  storage:
    directory: ".temp/cli_checkpoints/"
    format: "json"

  retention:
    max_age: "24h"
    max_count: 10
```

### 체크포인트 데이터

```json
{
  "task_id": "build:frontend",
  "timestamp": "2024-01-30T14:32:15Z",
  "progress": 67,
  "phase": "compiling",
  "elapsed_time": 45000,
  "output_lines": 234,
  "last_output": "Compiling src/App.tsx",
  "environment": {
    "NODE_ENV": "development",
    "CI": "false"
  }
}
```

## 리포트 생성

### 실행 완료 리포트

```
╔══════════════════════════════════════════════════════════════╗
║                    Execution Summary                          ║
╠══════════════════════════════════════════════════════════════╣
║  Total Time: 2m 34s                                           ║
║  Tasks: 5 completed, 0 failed                                 ║
╠══════════════════════════════════════════════════════════════╣
║  Task                    │ Duration │ Status                  ║
║  ────────────────────────┼──────────┼─────────                ║
║  npm install             │    23s   │ OK                      ║
║  build:frontend          │  1m 02s  │ OK                      ║
║  build:backend           │  1m 15s  │ OK                      ║
║  test                    │    45s   │ OK                      ║
║  deploy                  │    12s   │ OK                      ║
╠══════════════════════════════════════════════════════════════╣
║  Parallelization Efficiency: 78%                              ║
║  Time Saved: ~1m 45s                                          ║
╚══════════════════════════════════════════════════════════════╝
```

### 효율성 메트릭

```yaml
metrics:
  # 병렬화 효율
  parallelization_efficiency:
    formula: "sequential_time / actual_time"

  # 예측 정확도
  prediction_accuracy:
    formula: "1 - abs(predicted - actual) / actual"

  # 리소스 활용
  resource_utilization:
    formula: "active_time / total_time"
```
