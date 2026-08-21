# Memory Schemas — Research Plan · Findings · Checkpoints · Snapshots

각 메모리 타입의 정확한 파일 포맷. SKILL.md의 "Memory Types"에서 referenced.

## 1. Research Plan

**목적**: context limit을 넘어 전략 방향 유지.
**위치**: `.temp/memory/research_plans/{task_id}.md`

```markdown
# Research Plan: {task_id}

## Objective
{What we're trying to accomplish}

## Strategy
{High-level approach}

## Key Questions
- [ ] Question 1
- [x] Question 2 (answered)

## Progress
- Completed: {list}
- In Progress: {list}
- Pending: {list}

## Constraints
- {constraint_1}
- {constraint_2}

## Next Actions
1. {action_1}
2. {action_2}
```

## 2. Findings

**목적**: subagent 발견을 합성 가능한 형태로 캡처.
**위치**: `.temp/memory/findings/{agent}_{timestamp}.md`

```markdown
# Findings: {agent_name}
**Task**: {task_description}
**Timestamp**: {ISO timestamp}
**Status**: completed|partial|failed

## Summary
{2-3 sentence summary}

## Key Discoveries
1. {discovery_1}
2. {discovery_2}

## Files Modified/Created
- `path/to/file.ts` - {description}

## Open Questions
- {question_1}

## Recommendations
- {recommendation_1}
```

## 3. Checkpoints

**목적**: 실패로부터 복구.
**위치**: `.temp/memory/checkpoints/cp_{phase}_{timestamp}.json`

```json
{
  "checkpoint_id": "cp_implementation_20250104T120000",
  "task_id": "feature_xyz",
  "phase": "implementation",
  "timestamp": "2025-01-04T12:00:00Z",
  "state": {
    "completed_subtasks": ["task_1", "task_2"],
    "pending_subtasks": ["task_3", "task_4"],
    "active_agents": ["web-ui-specialist"],
    "blocked_agents": [],
    "findings_count": 3
  },
  "context_summary": "Implementing agent detail feature. UI components done, backend integration in progress.",
  "next_action": "Wait for backend-integration-specialist to complete API service",
  "recovery_instructions": "Resume by checking workspace metadata for pending agents"
}
```

## 4. Context Snapshot

**목적**: 토큰 한계 직전 전체 컨텍스트 저장.
**위치**: `.temp/memory/context_snapshots/snap_{timestamp}.md`

```markdown
# Context Snapshot
**Timestamp**: {ISO timestamp}
**Token Count**: ~{estimated_count}
**Reason**: {token_limit|manual|phase_end}

## Conversation Summary
{Key points from conversation so far}

## Current State
- Task: {current_task}
- Phase: {exploration|planning|implementation|review}
- Agents: {active_agents}

## Important Context
{Critical information that must not be lost}

## Files in Play
- `file_1.ts` - {status}
- `file_2.ts` - {status}

## Pending Decisions
- {decision_1}

## Resume Instructions
{How to continue from this point}
```
