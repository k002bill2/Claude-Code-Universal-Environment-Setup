---
name: external-memory
description: Context persistence system for long-running multi-agent tasks. Saves research plans, findings, and checkpoints to prevent context loss at token limits.
user-invocable: false
---

# External Memory System

## Purpose

장기 실행 다중 에이전트 태스크가 토큰 한계를 넘어 컨텍스트를 유지하도록 지원:
- 리서치 플랜 보존
- 중간 결과 저장
- 체크포인트 기반 복구
- 새 에이전트 핸드오프용 컨텍스트 스냅샷

## Directory Structure

```
.temp/memory/
├── research_plans/         # Active research strategies
│   └── {task_id}.md
├── findings/               # Subagent results
│   ├── {agent}_{ts}.md
│   └── merged_{ts}.md
├── checkpoints/            # Recovery points
│   └── cp_{phase}_{ts}.json
└── context_snapshots/      # Token limit saves
    └── snap_{ts}.md
```

## When to Use

### Automatic Triggers
1. **Context Budget Trigger** — 조언자 컨텍스트 예산 훅(`advisor-context-budget.js`)이
   CONTEXT BUDGET WARNING/CRITICAL 을 주입하면 저장한다. 고정 토큰 수(구 "150K")가 아니라
   세션 베이스라인 대비 델타 기준이다. 상세: docs/codex-advisor-worker-bundle/REVIEW_컨텍스트예산-리서치격리.md
2. **Phase Transition** — exploration/planning/implementation 완료 후
3. **Agent Completion** — 의미 있는 findings 반환 시
4. **Before Spawning** — 큰 병렬 batch 직전

### Manual Triggers
- 사용자가 "save progress" 요청
- 복잡한 결정 지점 도달
- 다음 단계 불확실

## Memory Types (요약)

| 타입 | 용도 | 위치 |
|------|------|------|
| Research Plan | 전략 방향 보존 | `research_plans/{task_id}.md` |
| Findings | subagent 결과 캡처 | `findings/{agent}_{ts}.md` |
| Checkpoint | 실패 복구 지점 | `checkpoints/cp_{phase}_{ts}.json` |
| Context Snapshot | 전체 컨텍스트 save | `context_snapshots/snap_{ts}.md` |

각 타입의 정확한 파일 포맷: [references/memory-schemas.md](references/memory-schemas.md)

## Operations

```bash
# Save research plan
.temp/memory/research_plans/{task_id}.md

# Save findings (subagent 완료 후)
.temp/memory/findings/{agent}_{timestamp}.md

# Merge multiple findings
.temp/memory/findings/merged_{timestamp}.md

# Create checkpoint (phase 경계)
.temp/memory/checkpoints/cp_{phase}_{timestamp}.json

# Context snapshot (토큰 한계/핸드오프 직전)
.temp/memory/context_snapshots/snap_{timestamp}.md
```

### Recovery 시 (Load)

1. 최신 checkpoint 확인: `ls -t .temp/memory/checkpoints/`
2. checkpoint JSON 읽기
3. 관련 findings 로드
4. `next_action`부터 재개

## Best Practices

1. **Save Early, Save Often** — 150K 도달 전, 발견마다, phase 전환마다
2. **Actionable Summaries** — what + why + 다음 단계 + 파일:line 참조
3. **Focused Findings** — 의미 있는 발견 1개씩, 대화 전체 덤프 금지
4. **Retrieval Structure** — 일관 네이밍, 타임스탬프, task_id 태그
5. **Cleanup** — 완료 태스크 아카이브, 24h 이상 stale checkpoint 삭제

## Integration with Orchestrator

Lead Orchestrator 책임:

1. **Initialize Memory** (태스크 시작)
   ```
   Create: .temp/memory/research_plans/{task_id}.md
   ```

2. **Save After Subagent Batch**
   ```
   For each completed agent:
     Save: .temp/memory/findings/{agent}_{ts}.md
   Create: .temp/memory/checkpoints/cp_{phase}_{ts}.json
   ```

3. **Monitor Token Usage**
   ```
   If tokens > 150K:
     Save: .temp/memory/context_snapshots/snap_{ts}.md
     Option: Spawn fresh agent with context file
   ```

4. **Recover on Failure**
   ```
   Read: latest checkpoint
   Load: relevant findings
   Resume: from recorded state
   ```

## Token Estimation

- 1 word ≈ 1.3 tokens
- 1 line of code ≈ 10 tokens
- 1 file read ≈ 500-2000 tokens
- 1 agent response ≈ 1000-3000 tokens

| Zone | 토큰 | 행동 |
|------|------|------|
| Warning | 120K (80%) | 다음 자연스러운 지점에서 저장 |
| Save | 150K | 즉시 snapshot |

## Example Usage Flow

```markdown
1. Create research plan
   └── .temp/memory/research_plans/agent_feature.md

2. After exploration phase
   └── .temp/memory/checkpoints/cp_exploration_*.json
   └── .temp/memory/findings/exploration_*.md

3. After spawning UI + Backend agents
   └── .temp/memory/findings/web-ui_*.md
   └── .temp/memory/findings/backend-integration_*.md

4. Merge and checkpoint
   └── .temp/memory/findings/merged_*.md
   └── .temp/memory/checkpoints/cp_implementation_*.json

5. Final review
   └── .temp/memory/checkpoints/cp_review_*.json
```

---

**Version**: 1.1 (Skills 2.0 migration)
