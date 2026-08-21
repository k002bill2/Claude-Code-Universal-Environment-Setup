# TaskOutput Polling Strategy

백그라운드 작업의 상태를 효율적으로 폴링하는 전략입니다.

## 폴링 기본 원칙

### 1. 적응형 간격 (Adaptive Interval)

```yaml
adaptive_polling:
  # 초기 빠른 폴링 → 점진적 감소
  initial_interval: 500ms
  max_interval: 10000ms
  backoff_multiplier: 1.5

  # 상태별 조정
  state_adjustments:
    recently_started:
      interval: 500ms    # 시작 직후 빈번하게
    long_running:
      interval: 5000ms   # 오래 걸리면 느리게
    near_completion:
      interval: 1000ms   # 완료 예상 시 다시 빠르게
```

### 2. 예측 기반 폴링

```yaml
prediction_based:
  # 예상 완료 시간 활용
  use_estimated_completion: true

  strategy:
    # 예상 완료 5분 전까지: 느린 폴링
    before_threshold:
      time_before: 300s
      interval: 10000ms

    # 예상 완료 1분 전: 빈번한 폴링
    near_completion:
      time_before: 60s
      interval: 2000ms

    # 예상 완료 후: 매우 빈번
    after_expected:
      interval: 500ms
```

## 폴링 패턴

### 단일 작업 폴링

```yaml
single_task_polling:
  task_id: "{task_id}"

  loop:
    while: "status != completed AND status != failed"

    steps:
      1. call: TaskOutput
         params:
           task_id: "{task_id}"
           block: false
           timeout: 1000

      2. check: status
         if_running:
           - update_progress_display
           - calculate_next_interval
           - wait: "{next_interval}"

      3. return: final_result
```

### 다중 작업 폴링

```yaml
multi_task_polling:
  tasks: [task_1, task_2, task_3]

  strategy: "round_robin"  # 또는 "parallel", "priority"

  round_robin:
    # 각 작업 순서대로 확인
    for_each: task_id in pending_tasks
    steps:
      1. poll: task_id
      2. if: completed or failed
         remove_from: pending_tasks
      3. update: progress_display
      4. wait: "{interval / pending_count}"

  parallel:
    # 모든 작업 동시 폴링
    concurrent_polls: true
    aggregate_results: true
```

### 그룹 완료 대기

```yaml
wait_for_group:
  tasks: [build, test, lint]

  strategies:
    # 모두 완료 대기
    wait_all:
      condition: "all tasks completed or failed"
      result: "aggregated_results"

    # 하나라도 완료 시
    wait_any:
      condition: "any task completed"
      result: "first_completed"

    # 하나라도 실패 시
    fail_fast:
      condition: "any task failed"
      action: "cancel_remaining"
```

## 최적화 기법

### 1. 배치 폴링

```yaml
batch_polling:
  # 여러 작업을 한 번에 확인
  batch_size: 5

  implementation:
    # 현재 TaskOutput은 단일 task_id만 지원
    # 순차적으로 빠르게 호출
    rapid_sequential:
      interval_between: 50ms
      batch_interval: 2000ms
```

### 2. 이벤트 기반 하이브리드

```yaml
event_hybrid:
  # 출력 파일 모니터링 + 주기적 폴링
  primary:
    method: "file_watch"
    file: "{output_file}"
    on_change: "parse_progress"

  fallback:
    method: "polling"
    interval: 5000ms
    reason: "file_watch might miss events"
```

### 3. 스마트 스킵

```yaml
smart_skip:
  # 불필요한 폴링 건너뛰기
  skip_conditions:
    - "task_just_polled_within_100ms"
    - "task_estimated_far_from_completion"
    - "system_under_heavy_load"
```

## 폴링 상태 표시

### 진행 상황 UI

```
Polling Status
══════════════════════════════════════════════════

Task: build:frontend
├─ Status: Running
├─ Progress: 67%
├─ Elapsed: 45s
├─ ETA: ~20s
├─ Last Poll: 500ms ago
└─ Next Poll: in 1.5s

Task: test
├─ Status: Running
├─ Progress: 34%
├─ Elapsed: 23s
├─ ETA: ~45s
├─ Last Poll: 200ms ago
└─ Next Poll: in 2s

[Polling Efficiency: 85%]  [Active Polls: 2]
```

### 폴링 메트릭스

```yaml
metrics:
  # 효율성 지표
  efficiency:
    useful_polls: 45      # 상태 변경 감지
    redundant_polls: 5    # 변경 없음
    efficiency_ratio: 0.90

  # 리소스 사용
  resource_usage:
    avg_poll_latency: 50ms
    total_polls: 50
    api_calls_saved: 30  # 스킵된 불필요 폴링
```

## 에러 처리

### 폴링 실패 처리

```yaml
poll_failure_handling:
  # 일시적 실패
  transient:
    actions:
      - "log_warning"
      - "increase_interval"
      - "retry_with_backoff"
    max_consecutive_failures: 3

  # 지속적 실패
  persistent:
    after_failures: 5
    actions:
      - "mark_task_unknown"
      - "notify_user"
      - "offer_manual_check"
```

### 타임아웃 처리

```yaml
timeout_handling:
  poll_timeout:
    timeout: 5000ms
    on_timeout:
      - "use_last_known_state"
      - "schedule_next_poll"

  task_timeout:
    # 전체 작업 타임아웃
    global_timeout: 600000ms
    on_timeout:
      - "cancel_task"
      - "report_timeout_failure"
```

## 구현 예시

### 기본 폴링 루프

```yaml
basic_polling_loop:
  init:
    interval: 1000ms
    max_polls: 100
    polls_count: 0

  loop:
    while: "polls_count < max_polls"

    body:
      - call: TaskOutput
        params:
          task_id: "{task_id}"
          block: false
          timeout: 2000

      - match: result.status
        "completed":
          return: result
        "failed":
          return: result
        "running":
          - update_display(result.output)
          - sleep(interval)
          - adjust_interval()
          - polls_count++

    after_loop:
      return: "timeout_result"
```

### 다중 작업 폴링 루프

```yaml
multi_task_loop:
  init:
    pending: [task_1, task_2, task_3]
    results: {}
    interval: 500ms

  loop:
    while: "pending.length > 0"

    body:
      - for: task_id in pending
        - call: TaskOutput
          params:
            task_id: task_id
            block: false
            timeout: 1000

        - if: result.status in ["completed", "failed"]
          - results[task_id] = result
          - pending.remove(task_id)

        - update_aggregate_display()

      - sleep(interval)
      - adjust_interval_based_on_progress()

    after_loop:
      return: results
```

## 모범 사례

### DO

- 적응형 간격으로 리소스 절약
- 예상 완료 시간 활용
- 실패 시 백오프 적용
- 진행 상황 실시간 표시

### DON'T

- 고정 짧은 간격으로 과도한 폴링
- 폴링 실패 무시
- 타임아웃 없이 무한 대기
- 완료된 작업 계속 폴링
