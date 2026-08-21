# History Data Schema

CLI 실행 히스토리를 저장하고 학습에 활용하기 위한 데이터 스키마입니다.

## 저장소 구조

```
~/.claude/cli-orchestration/
├── history/
│   ├── executions.jsonl      # 실행 기록 (JSONL)
│   ├── patterns.json         # 학습된 패턴
│   ├── predictions.json      # 예측 모델 데이터
│   └── analytics/
│       ├── daily/            # 일별 집계
│       ├── weekly/           # 주별 집계
│       └── commands/         # 명령어별 통계
```

## 실행 기록 스키마

### ExecutionRecord

```json
{
  "id": "exec_20240130_143215_abc123",
  "timestamp": "2024-01-30T14:32:15.000Z",
  "session_id": "session_xyz789",

  "command": {
    "raw": "npm run build",
    "normalized": "npm run build",
    "type": "build",
    "tool": "npm",
    "working_directory": "/Users/user/project"
  },

  "execution": {
    "start_time": "2024-01-30T14:32:15.000Z",
    "end_time": "2024-01-30T14:33:17.000Z",
    "duration_ms": 62000,
    "exit_code": 0,
    "status": "success"
  },

  "environment": {
    "node_version": "20.10.0",
    "npm_version": "10.2.0",
    "os": "darwin",
    "ci": false,
    "project_type": "typescript"
  },

  "resources": {
    "peak_memory_mb": 512,
    "cpu_time_ms": 45000
  },

  "output": {
    "lines_count": 234,
    "errors_count": 0,
    "warnings_count": 3,
    "summary": "Built successfully in 62s"
  },

  "context": {
    "files_changed_since_last": 5,
    "previous_command": "npm install",
    "part_of_workflow": "ci-pipeline",
    "workflow_position": 2
  },

  "tags": ["build", "production", "frontend"]
}
```

### 필드 설명

| 필드 | 타입 | 설명 |
|------|------|------|
| `id` | string | 고유 식별자 |
| `timestamp` | ISO8601 | 실행 시작 시간 |
| `session_id` | string | Claude Code 세션 ID |
| `command.raw` | string | 원본 명령어 |
| `command.normalized` | string | 정규화된 명령어 |
| `command.type` | enum | build, test, lint, deploy 등 |
| `execution.duration_ms` | number | 실행 시간 (밀리초) |
| `execution.exit_code` | number | 종료 코드 |
| `execution.status` | enum | success, failure, timeout, cancelled |

## 패턴 스키마

### CommandPattern

```json
{
  "pattern_id": "pat_npm_build_ts",
  "pattern_type": "command_sequence",

  "trigger": {
    "command": "npm run build",
    "project_type": "typescript"
  },

  "statistics": {
    "occurrences": 150,
    "first_seen": "2024-01-01T00:00:00Z",
    "last_seen": "2024-01-30T14:32:15Z",
    "success_rate": 0.92,
    "avg_duration_ms": 58000,
    "duration_stddev_ms": 12000
  },

  "predictions": {
    "estimated_duration_ms": 60000,
    "confidence": 0.85,
    "likely_next_command": "npm test",
    "next_command_probability": 0.78
  },

  "common_failures": [
    {
      "error_pattern": "TS2322",
      "frequency": 0.15,
      "typical_resolution": "Fix type mismatch"
    }
  ],

  "optimizations": {
    "suggested_parallelization": ["npm run lint", "npm run typecheck"],
    "cache_recommendation": "Use .next/cache for faster builds"
  }
}
```

## 워크플로우 스키마

### WorkflowPattern

```json
{
  "workflow_id": "wf_ci_pipeline",
  "name": "CI Pipeline",

  "sequence": [
    { "step": 1, "command": "npm install", "typical_duration_ms": 15000 },
    { "step": 2, "command": "npm run lint", "typical_duration_ms": 8000 },
    { "step": 3, "command": "npm run typecheck", "typical_duration_ms": 12000 },
    { "step": 4, "command": "npm test", "typical_duration_ms": 45000 },
    { "step": 5, "command": "npm run build", "typical_duration_ms": 60000 }
  ],

  "statistics": {
    "total_runs": 50,
    "success_rate": 0.88,
    "avg_total_duration_ms": 140000,
    "parallelizable_steps": [[2, 3]]
  },

  "common_failure_points": [
    { "step": 4, "failure_rate": 0.08, "reason": "Test failures" }
  ]
}
```

## 분석 집계 스키마

### DailyAggregate

```json
{
  "date": "2024-01-30",

  "summary": {
    "total_executions": 45,
    "successful": 42,
    "failed": 3,
    "success_rate": 0.933,
    "total_time_ms": 1800000
  },

  "by_command_type": {
    "build": { "count": 15, "success_rate": 0.93 },
    "test": { "count": 12, "success_rate": 0.83 },
    "lint": { "count": 10, "success_rate": 1.0 },
    "deploy": { "count": 8, "success_rate": 1.0 }
  },

  "peak_hours": [
    { "hour": 10, "executions": 12 },
    { "hour": 14, "executions": 15 }
  ],

  "common_errors": [
    { "pattern": "TS2322", "count": 2 },
    { "pattern": "ENOENT", "count": 1 }
  ]
}
```

## 데이터 관리

### 보존 정책

```yaml
retention_policy:
  # 상세 실행 기록
  executions:
    keep_detailed: "30d"    # 30일간 상세 보관
    keep_summary: "1y"      # 1년간 요약 보관

  # 패턴 데이터
  patterns:
    min_occurrences: 3      # 3회 이상 발생 시 패턴화
    decay_factor: 0.95      # 시간 경과에 따른 가중치 감소
    max_age: "180d"         # 180일 미사용 시 삭제

  # 집계 데이터
  aggregates:
    daily: "90d"
    weekly: "1y"
    monthly: "forever"
```

### 개인정보 보호

```yaml
privacy:
  # 민감 정보 필터링
  redaction:
    - pattern: "password=.*"
      replace: "password=***"
    - pattern: "API_KEY=.*"
      replace: "API_KEY=***"
    - pattern: "/Users/[^/]+"
      replace: "/Users/***"

  # 저장 제외
  exclusions:
    - commands_containing: ["secret", "token", "key"]
    - environment_vars: ["AWS_SECRET", "GITHUB_TOKEN"]
```

### 동기화

```yaml
sync:
  # 로컬 전용 (기본)
  mode: "local"

  # 선택적 동기화 (향후)
  optional:
    anonymized_stats: true   # 익명화된 통계만 공유
    command_patterns: false  # 명령어 패턴 비공유
```

## 쿼리 인터페이스

### 기본 쿼리

```yaml
queries:
  # 최근 실행 조회
  recent_executions:
    params: [limit, command_type, status]
    returns: ExecutionRecord[]

  # 명령어 통계
  command_stats:
    params: [command, date_range]
    returns: CommandStatistics

  # 패턴 검색
  find_patterns:
    params: [trigger_command, min_occurrences]
    returns: CommandPattern[]
```

### 예시 쿼리

```yaml
example_queries:
  # "npm run build"의 평균 실행 시간
  - query: "avg_duration"
    command: "npm run build"
    date_range: "last_30_days"
    result: 58234  # ms

  # 가장 자주 실패하는 명령어
  - query: "top_failures"
    limit: 5
    result:
      - { command: "npm test", failure_rate: 0.12 }
      - { command: "npm run build", failure_rate: 0.08 }
```

## 인덱싱

```yaml
indexes:
  # 빠른 조회를 위한 인덱스
  primary:
    - field: "id"
      type: "unique"

  secondary:
    - field: "timestamp"
      type: "btree"
    - field: "command.normalized"
      type: "hash"
    - field: "execution.status"
      type: "hash"
    - fields: ["command.type", "timestamp"]
      type: "composite"
```
