# Event Schemas — Tracing Operations 상세

각 trace event의 상세 데이터 스키마와 트레이싱 운영 레퍼런스. SKILL.md의 "상세 이벤트 스키마/메트릭" 포인터에서 referenced.

## Trace Events

### Event Types

| Event | Trigger | Data Captured |
|-------|---------|---------------|
| `agent_spawned` | Task tool called | agent_type, model, task_summary |
| `task_assigned` | Delegation created | task_id, agent, complexity |
| `tool_called` | Any tool invocation | tool_name, duration_ms |
| `result_received` | Agent completion | agent_id, status, findings_count |
| `decision_made` | Branching point | decision_type, choice, reasoning_length |
| `checkpoint_saved` | Memory save | checkpoint_type, location |
| `error_occurred` | Failure detected | error_type, agent, recoverable |
| `iteration_started` | Gap-filling loop | iteration_number, gaps_count |

### Event Format

```json
{
  "event": "agent_spawned",
  "timestamp": "2025-01-04T12:00:00.000Z",
  "session_id": "sess_abc123",
  "task_id": "task_xyz",
  "data": {
    "agent_type": "web-ui-specialist",
    "model": "sonnet",
    "task_summary": "Create AgentCard component",
    "complexity": "simple",
    "parent_agent": "aos-orchestrator"
  }
}
```

## 이벤트별 상세 데이터 스키마

### Start Session

```markdown
Event: session_started
Data:
  - session_id: generated UUID
  - task_description: summary (no content)
  - complexity_assessment: trivial|simple|moderate|complex
  - planned_agents: count
```

### Track Agent Spawn

```markdown
Event: agent_spawned
Data:
  - agent_id: unique ID
  - agent_type: specialist name
  - model: sonnet|opus|haiku
  - task_summary: 10-20 words max
  - dependencies: list of agent_ids to wait for
```

### Track Tool Call

```markdown
Event: tool_called
Data:
  - tool_name: read|edit|grep|etc
  - duration_ms: execution time
  - success: boolean
  - file_count: for file operations
```

### Track Decision

```markdown
Event: decision_made
Data:
  - decision_type: effort_scaling|delegation|iteration|completion
  - choice: what was decided
  - alternatives_considered: count
  - confidence: high|medium|low
```

### Track Error

```markdown
Event: error_occurred
Data:
  - error_type: timeout|validation|integration|tool_failure
  - agent_id: where it occurred
  - recoverable: boolean
  - recovery_action: retry|skip|abort
```

### End Session

```markdown
Event: session_ended
Data:
  - status: completed|partial|failed|aborted
  - deliverables_count: files created/modified
  - quality_gates_passed: boolean
```

## Trace Storage

```
.temp/traces/
├── sessions/
│   └── sess_{id}/
│       ├── events.jsonl      # Append-only event log
│       ├── metrics.json      # Aggregated metrics
│       └── summary.md        # Human-readable summary
└── archive/{date}/sess_{id}.tar.gz
```

### Event Log Format (JSONL)
```
{"event":"session_started","timestamp":"...","session_id":"sess_abc"}
{"event":"agent_spawned","timestamp":"...","session_id":"sess_abc","data":{...}}
{"event":"tool_called","timestamp":"...","session_id":"sess_abc","data":{...}}
```

## Per-Session Metrics

```json
{
  "session_id": "sess_abc123",
  "started_at": "...",
  "ended_at": "...",
  "duration_ms": 900000,
  "agents": {
    "spawned": 4, "succeeded": 3, "failed": 1,
    "by_type": { "web-ui-specialist": 1, ... }
  },
  "tools": {
    "total_calls": 47,
    "by_tool": { "read": 15, "edit": 12, "grep": 8, ... }
  },
  "tokens": { "estimated_input": 45000, "estimated_output": 12000 },
  "iterations": 2,
  "checkpoints": 3,
  "errors": 1
}
```

## Analysis Patterns

### Failure Diagnosis (실패 세션 분석 순서)

1. **Error Clustering** — 한 에이전트에 집중? 특정 phase? 어떤 tool call 직후?
2. **Decision Path** — 복잡도 평가가 맞았나? 경계가 명확했나? 반복 과다?
3. **Performance Anomalies** — tool call 폭증? 단순 작업에 긴 시간? 토큰 스파이크?

### Success Patterns (재사용 가치)

- 태스크 유형별 최적 에이전트 조합
- 효과적 위임 패턴
- 성공한 반복 횟수

## Privacy

**NEVER LOG**:
- 실제 파일 내용
- 사용자 메시지 (분류 외)
- 코드 스니펫
- 개인 정보
- API 키 / 시크릿

**ALWAYS LOG**:
- 구조 정보 (파일 카운트 — 파일명 아님)
- 타이밍 정보
- 성공/실패 상태
- 도구 이름 (인자 아님)
- 에이전트 타입 (출력 아님)

## Integration

### 실행 중 (Lead Orchestrator)
1. 세션 시작 시 session_id 생성
2. 각 Task 호출에 `agent_spawned` 로깅
3. 결정 지점 추적
4. 에러 컨텍스트와 함께 로깅
5. 세션 종료 시 메트릭 저장

### 실행 후 (분석)
1. 세션 메트릭 읽기
2. KPI와 비교
3. 이상치 식별
4. `agent-improvement` 스킬로 전달

## Quick Commands

```bash
# 최근 세션 보기
ls -lt .temp/traces/sessions/

# 최신 세션 이벤트
tail -100 .temp/traces/sessions/sess_latest/events.jsonl

# 세션 메트릭
cat .temp/traces/sessions/sess_latest/metrics.json

# 오래된 세션 아카이브 (7일 이상)
./scripts/archive-traces.sh 7
```

## Example Trace Summary

```markdown
# Session Summary: sess_abc123

## Overview
- Task: Add agent favorites feature
- Complexity: Moderate
- Duration: 12m 34s
- Status: COMPLETED

## Agent Activity
| Agent | Tools | Duration | Status |
|-------|-------|----------|--------|
| backend-integration | 15 | 4m 12s | Success |
| web-ui | 18 | 5m 45s | Success |
| test-automation | 12 | 2m 15s | Success |
| quality-validator | 4 | 22s | Success |

## Iterations
- Round 1: 3 agents, 2 gaps found
- Round 2: 1 follow-up agent, completed

## Metrics
- Total tool calls: 49
- Estimated tokens: 67,000
- Checkpoints saved: 2
- Errors: 0

## Performance
- Agent success rate: 100%
- Token efficiency: Good (<100K)
- Iteration count: Normal (2)
```
