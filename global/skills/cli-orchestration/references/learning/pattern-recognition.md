# Pattern Recognition Protocol

CLI 실행 히스토리에서 패턴을 인식하고 학습하는 프로토콜입니다.

## 패턴 유형

### 1. 명령어 시퀀스 패턴

연속적으로 실행되는 명령어 조합:

```yaml
sequence_pattern:
  name: "CI Pipeline"
  confidence: 0.92

  sequence:
    - "npm install"
    - "npm run lint"
    - "npm run typecheck"
    - "npm test"
    - "npm run build"

  statistics:
    occurrences: 45
    avg_interval_ms: 5000  # 명령어 간 평균 간격
    completion_rate: 0.89  # 끝까지 실행 비율
```

### 2. 시간 기반 패턴

특정 시간대에 자주 실행되는 명령어:

```yaml
temporal_pattern:
  name: "Morning Build"
  confidence: 0.78

  time_window:
    days: ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"]
    hours: [9, 10]  # 9-11 AM

  typical_commands:
    - command: "git pull"
      probability: 0.95
    - command: "npm install"
      probability: 0.70
    - command: "npm run build"
      probability: 0.85
```

### 3. 컨텍스트 기반 패턴

파일 변경이나 이전 명령어에 따른 패턴:

```yaml
context_pattern:
  name: "After Package Update"
  confidence: 0.88

  trigger:
    file_changed: "package.json"

  expected_sequence:
    - "npm install"
    - "npm run build"

  statistics:
    trigger_to_action_rate: 0.92
```

### 4. 오류-해결 패턴

특정 오류 후 실행되는 해결 명령어:

```yaml
error_resolution_pattern:
  name: "Module Not Found Fix"
  confidence: 0.85

  trigger:
    error_pattern: "Cannot find module"
    exit_code: 1

  resolution_sequence:
    - "npm install"
    - "npm cache clean --force"  # 실패 시
    - "rm -rf node_modules && npm install"  # 여전히 실패 시

  success_rate: 0.95
```

## 패턴 감지 알고리즘

### 시퀀스 마이닝

```yaml
sequence_mining:
  algorithm: "PrefixSpan"

  parameters:
    min_support: 0.05        # 최소 5% 발생
    min_confidence: 0.70     # 70% 신뢰도
    max_gap: 5               # 최대 5개 명령어 간격

  preprocessing:
    normalize_commands: true  # 경로 제거, 옵션 정규화
    group_by_session: true    # 세션 단위로 분석
```

### 연관 규칙

```yaml
association_rules:
  algorithm: "FP-Growth"

  rules:
    # "npm install" 후 "npm run build" 실행 확률
    - antecedent: ["npm install"]
      consequent: ["npm run build"]
      support: 0.35
      confidence: 0.78
      lift: 2.1

    # 복합 규칙
    - antecedent: ["npm install", "npm run lint"]
      consequent: ["npm test"]
      support: 0.25
      confidence: 0.85
      lift: 1.8
```

### 클러스터링

```yaml
clustering:
  algorithm: "DBSCAN"

  features:
    - command_type
    - execution_time
    - time_of_day
    - day_of_week

  clusters:
    - id: "cluster_morning_ci"
      centroid:
        time_of_day: 9.5
        commands: ["build", "test"]
      size: 120

    - id: "cluster_hotfix"
      centroid:
        commands: ["test", "deploy"]
        time_pattern: "any"
      size: 25
```

## 패턴 점수화

### 신뢰도 계산

```yaml
confidence_calculation:
  factors:
    # 발생 빈도
    frequency:
      weight: 0.3
      formula: "occurrences / total_sessions"

    # 최근성
    recency:
      weight: 0.25
      formula: "exp(-days_since_last / 30)"

    # 일관성
    consistency:
      weight: 0.25
      formula: "1 - stddev(intervals) / avg(intervals)"

    # 완료율
    completion:
      weight: 0.2
      formula: "completed_sequences / started_sequences"

  final_score:
    formula: "sum(factor.weight * factor.value)"
    threshold: 0.70  # 이 이상이면 활성 패턴
```

### 패턴 우선순위

```yaml
priority_ranking:
  criteria:
    1. "confidence >= 0.85"
    2. "occurrences >= 10"
    3. "recency <= 7 days"

  tiebreaker:
    - "higher confidence"
    - "more recent"
    - "higher completion rate"
```

## 패턴 활용

### 명령어 제안

```yaml
command_suggestion:
  # 현재 상황
  context:
    last_command: "npm run lint"
    session_commands: ["npm install", "npm run lint"]
    time: "10:30 AM Monday"

  # 패턴 매칭
  matched_patterns:
    - pattern: "CI Pipeline"
      confidence: 0.88
      next_command: "npm run typecheck"

    - pattern: "Quick Check"
      confidence: 0.72
      next_command: "npm test"

  # 제안
  suggestion:
    command: "npm run typecheck"
    reason: "CI Pipeline 패턴과 88% 일치"
    alternatives:
      - "npm test (72% 일치)"
```

### 자동 워크플로우 구성

```yaml
auto_workflow:
  # 감지된 패턴 기반 워크플로우 제안
  detected_pattern:
    commands: ["lint", "typecheck", "test", "build"]
    frequency: 35

  suggested_workflow:
    name: "Quality Check Pipeline"
    parallel_groups:
      - ["lint", "typecheck"]  # 병렬 가능
      - ["test"]
      - ["build"]
    estimated_time_saved: "40%"
```

### 이상 감지

```yaml
anomaly_detection:
  # 정상 패턴
  normal_pattern:
    command: "npm run build"
    avg_duration: 60000ms
    stddev: 10000ms

  # 이상 감지
  anomaly:
    current_duration: 150000ms
    deviation: 9.0  # 표준편차 9배
    alert: "빌드 시간이 비정상적으로 깁니다"

  # 가능한 원인
  possible_causes:
    - "캐시 무효화"
    - "의존성 대량 추가"
    - "시스템 리소스 부족"
```

## 패턴 관리

### 패턴 생명주기

```yaml
pattern_lifecycle:
  states:
    EMERGING:
      criteria: "3 <= occurrences < 10"
      confidence_threshold: 0.5

    ESTABLISHED:
      criteria: "occurrences >= 10"
      confidence_threshold: 0.7

    DECLINING:
      criteria: "no occurrence in 30 days"
      action: "reduce confidence by 10%/week"

    ARCHIVED:
      criteria: "confidence < 0.3"
      action: "move to archive, stop suggesting"
```

### 패턴 병합

```yaml
pattern_merging:
  # 유사 패턴 감지
  similarity_threshold: 0.85

  # 병합 규칙
  merge_rules:
    - condition: "same commands, different order"
      action: "keep most frequent order"

    - condition: "subset relationship"
      action: "keep longer pattern if confident"
```

### 사용자 피드백

```yaml
user_feedback:
  actions:
    confirm:
      effect: "increase confidence by 5%"

    reject:
      effect: "decrease confidence by 10%"

    modify:
      effect: "create variant pattern"
```
