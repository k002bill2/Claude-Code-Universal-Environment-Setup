---
tags:
  - claude
  - setup
---

# Parallel Agents Safety Protocol v3.2.0

## Document Information
- **Version**: 3.2.0
- **Last Updated**: 2026-06-16
- **Status**: Active
- **Scope**: Multi-agent parallel execution in Claude Code v2.1.210 environment
- **Previous Version**: 3.1.1 (2026-05-16), 3.1.0 (2026-03-18, CLI v2.1.78 기준)
- **Models**: Opus 4.8 (최신 플래그십, 1M context 변형 존재), Fable 5 (신규 세대), Sonnet 5 (1M context, 코딩/에이전트 메인), Haiku 4.5
- **Settings**: .claude/settings.json

---

## v3.2.0 변경 사항 요약 (2026-06-16 갱신)

### v3.1.1 → v3.2.0 차이
- 모델 세대 갱신: **Opus 4.7 → Opus 4.8** (ID `claude-opus-4-8`, 1M context 변형 존재), **Fable 5** (ID `claude-fable-5`, 신규 세대) 추가. Sonnet 4.6 / Haiku 4.5는 동일 (※ 기록 시점 기준 — 현행은 Sonnet 5). `/fast` 모드는 Opus 4.8/4.7을 빠른 출력으로 실행(작은 모델 다운그레이드 아님).
- **신규 섹션 "Workflow 도구 기반 오케스트레이션(권장)"** 추가 (§0). 인라인 JS 스크립트로 `agent`/`parallel`/`pipeline`/`phase`/`log`/`args`/`budget`/`isolation:worktree`를 사용해 멀티 에이전트를 조립. 동시 실행은 `min(16, cpu코어-2)`로 자동 캡, 총 1000 에이전트 상한, 백그라운드 실행 + 완료 알림.
- 기존 **수동 Primary/Secondary coordinator, 파일 Lock FIFO, deadlock 감지, 워크스페이스 격리 디렉토리**는 **(레거시) Workflow 미사용 시 폴백**으로 강등. 단 윤리 제약(5 hard limits)·incident 로깅·체크포인트는 Workflow가 다루지 않는 직교 관심사이므로 그대로 보존.
- **subagent_type 정정**: "네임스페이스 완전 평탄화"는 부정확 → **플랫 빌트인 + 플러그인 스코프(`ecc:*`) 공존**이 정확한 설명.
- `SendMessage` / `isolation:"worktree"` / `run_in_background` 표현은 현행 환경에서도 유효하므로 유지.

## v3.1.1 변경 사항 요약 (2026-05 갱신)

### v3.1.0 → v3.1.1 차이
- 모델 세대 갱신: Opus 4.6 → **Opus 4.7** (Sonnet/Haiku는 동일)
  - ※ 2026-06-16 갱신: 현재 플래그십은 Opus 4.8 / Fable 5. 위 항목은 v3.1.1 시점 기록.
- Hooks 이벤트: `PostToolUseFailure`/`SubagentStart`/`PermissionRequest`/`Setup` 등이 유효 이벤트 목록에 포함(아래 settings.json 스키마 참조)
- subagent_type: `feature-dev:code-*` → 플랫 빌트인 이름으로 정리
  - ※ 2026-06-16 갱신: 빌트인은 플랫 네임스페이스지만 플러그인 스코프 에이전트(`ecc:*`)와 공존함. "완전 평탄화"는 부정확.

### 핵심 패턴 (v3.1.0부터 유지)
- **SendMessage 패턴**: 실행 중인 에이전트에 메시지 전송 (resume 파라미터 대체)
- **Worktree 격리**: `isolation: "worktree"`로 독립된 Git worktree에서 에이전트 실행
- **run_in_background**: 백그라운드 에이전트 실행 및 자동 완료 알림
- **영구 메모리**: 에이전트별 메모리 스코프 (user/project/local)

### 에이전트 Frontmatter (v2.1.210 기준)
```markdown
---
name: agent-name
description: Agent purpose and trigger conditions
model: sonnet-5          # opus-4.8, fable-5, sonnet-5, haiku-4.5
# effort / maxTurns / disallowedTools 는 환경/버전에 따라 지원 여부 상이.
# 사용 전 `claude --version`과 /agents 메뉴로 실제 지원 확인 권장.
---
```

### 내장 에이전트 타입 (플랫 빌트인 + 플러그인 스코프 `ecc:*` 공존)

빌트인 에이전트 타입은 플랫 네임스페이스를 쓰지만, 플러그인이 제공하는 에이전트는 `ecc:*` 네임스페이스로 **공존**합니다(예: `ecc:architect`, `ecc:python-reviewer`). 즉 "완전 평탄화"가 아니라 **플랫 빌트인 + 스코프된 플러그인 에이전트**가 함께 존재합니다. 빌트인 예: `general-purpose`, `Explore`(읽기전용 탐색), `Plan`, `planner`, `architect`, `code-reviewer`, `security-reviewer` 등.

| 타입 | 용도 |
|------|------|
| `general-purpose` | 범용 작업 (기본) |
| `Explore` | 코드베이스 탐색 (quick/medium/very thorough) |
| `Plan` | 구현 계획 설계 |
| `code-reviewer` | 코드 리뷰 (보안+품질) |
| `security-reviewer` | 보안 취약점 전문 |
| `architect` | 시스템 아키텍처 설계 |
| `planner` | 복잡한 기능/리팩토링 계획 |
| `test-automation-specialist` | 빌드/테스트 검증 (Fresh context) |
| `build-error-resolver` | TS/빌드 에러 해결 |
| `cli-orchestrator` | CLI 파이프라인 오케스트레이션 |
| `claude` | 위 항목에 맞지 않는 catch-all |

**v3.1.0 → v3.1.1 매핑**:
- `feature-dev:code-reviewer` → `code-reviewer`
- `feature-dev:code-explorer` → `Explore` 또는 `general-purpose`
- `feature-dev:code-architect` → `architect`
- `verify-agent` → `test-automation-specialist` 또는 `code-reviewer`

### 설정 파일 이전
- `.claudecode.json` → `.claude/settings.json`

---

## Table of Contents

0. [Workflow 도구 기반 오케스트레이션 (권장)](#0-workflow-도구-기반-오케스트레이션-권장)
1. [Core Principles & Agent Hierarchy](#1-core-principles--agent-hierarchy)
2. [Agent Roles and Responsibilities (레거시)](#2-agent-roles-and-responsibilities-레거시-workflow-미사용-시-폴백)
3. [Resource Management (레거시)](#3-resource-management-레거시-workflow-미사용-시-폴백)
4. [Communication Protocol](#4-communication-protocol)
5. [Skill Auto-Invocation Protocol](#5-skill-auto-invocation-protocol)
6. [MCP CLI Coordination Rules](#6-mcp-cli-coordination-rules)
7. [Validation and Quality Assurance](#7-validation-and-quality-assurance)
8. [Complete Workflow Examples](#8-complete-workflow-examples)
9. [Error Handling and Recovery](#9-error-handling-and-recovery)
10. [Performance Optimization](#10-performance-optimization)
11. [Continuous Improvement & Feedback](#11-continuous-improvement--feedback)
12. [Testing and Validation](#12-testing-and-validation)
13. [Maintenance and Evolution](#13-maintenance-and-evolution)

---

## 0. Workflow 도구 기반 오케스트레이션 (권장)

> **2026-06-16 신규.** 현행 환경에서 멀티 에이전트 병렬 실행의 **1순위 메커니즘**은 Workflow 도구다. 아래 §1~§3의 수동 Primary/Secondary coordinator·파일 Lock·deadlock 감지·워크스페이스 격리 디렉토리는 Workflow를 쓰지 않을 때의 **(레거시) 폴백**으로 강등되었다. 단 §1.1.1 윤리 제약(5 hard limits), §9.2 체크포인트/롤백, §9.3 incident 로깅은 Workflow가 다루지 않는 **직교 관심사**이므로 Workflow 사용 여부와 무관하게 그대로 적용한다.

### 0.1 형태와 진입점

Workflow는 **인라인 JS 스크립트**다. 반드시 순수 리터럴 `meta`로 시작한다.

```javascript
// 반드시 순수 리터럴(동적 계산 금지)
export const meta = {
  name: "q4-report",
  description: "Q4 리포트 생성 오케스트레이션",
  phases: ["analyze", "visualize", "assemble"],
};
```

### 0.2 본문 전역 함수 (await 직접 사용)

스크립트 본문에서는 다음 전역 함수를 `await`로 직접 호출한다.

| 함수 | 시그니처 | 설명 |
|------|----------|------|
| `agent` | `agent(prompt, opts?)` | 서브에이전트 실행. `opts = { label, phase, schema, model, effort, isolation:'worktree', agentType }`. `schema`를 주면 **검증된 객체**를 반환. |
| `parallel` | `parallel(thunks)` | 동시 실행 + **배리어**(모두 완료 후 반환). 실패 항목은 `null`. |
| `pipeline` | `pipeline(items, stage1, stage2, ...)` | 항목별 독립 파이프라인. **단계 간 배리어 없음**. |
| `phase` | `phase(title)` | 단계 경계 표시. |
| `log` | `log(message)` | 진행 로그. |
| `args` | `args` | 워크플로우 입력값. |
| `budget` | `budget(tokens)` | 토큰 예산 지정. |
| `workflow` | `workflow(name, args)` | 다른 워크플로우 **1단계 중첩** 호출. |

### 0.3 동시성·실행 모델

- **동시 실행 자동 캡**: `min(16, cpu코어-2)`. 동시에 도는 에이전트 수가 이 값으로 제한된다. (레거시 §3.1의 수동 FIFO Lock 대신 런타임이 동시성을 관리)
- **총 에이전트 상한**: 1000.
- **백그라운드 실행 + 완료 알림**: 워크플로우는 백그라운드에서 돌고 완료 시 자동으로 알림을 보낸다. 동시에 다른 작업 진행 가능.
- `isolation: 'worktree'`: 에이전트를 자체 Git worktree에서 실행, 변경이 없으면 자동 정리(§A2와 동일 메커니즘).

### 0.4 예시: Fan-Out / Fan-In (수동 coordinator 없이)

```javascript
export const meta = {
  name: "q4-report",
  description: "데이터 분석 + 시각화 + 문서 조립",
  phases: ["analyze", "assemble"],
};

phase("analyze");
// parallel: 모두 완료될 때까지 배리어. 실패 항목은 null로 반환.
const [analysis, charts] = await parallel([
  () => agent("Q4 판매 데이터 분석 후 q4_analysis.xlsx 산출", {
    label: "analysis", phase: "analyze", isolation: "worktree",
  }),
  () => agent("분석 결과로 차트 생성", {
    label: "charts", phase: "analyze",
  }),
]);

phase("assemble");
// schema를 주면 검증된 객체 반환
const report = await agent("분석+차트로 q4_report.docx, q4_presentation.pptx 작성", {
  label: "assemble",
  schema: { type: "object", properties: { docx: { type: "string" }, pptx: { type: "string" } } },
});
log(`완료: ${report.docx}, ${report.pptx}`);
```

### 0.5 예시: pipeline (항목별 독립, 단계 간 배리어 없음)

```javascript
// 파일별로 독립 파이프라인 — 한 파일이 느려도 다른 파일은 막히지 않음
await pipeline(
  ["a.csv", "b.csv", "c.csv"],
  (file) => agent(`${file} 파싱 및 정합성 검증`),
  (parsed) => agent(`정제된 데이터로 요약 생성: ${parsed}`),
);
```

### 0.6 금지 — 날조 API

다음 표현은 **실재하지 않으며** 사용 금지다. 발견 시 위 실제 API로 교정한다.

- ❌ `workflow.pipeline([{ task, agent, depends }])`
- ❌ `agent(...).withIsolation().run()` 등 fluent builder 체인
- ❌ `workflow.background()`

격리는 `agent(prompt, { isolation: 'worktree' })` 옵션으로, 백그라운드는 워크플로우 기본 동작(완료 알림)으로, 의존 관계는 `phase`/`parallel`/`pipeline` 구조로 표현한다.

---

## 1. Core Principles & Agent Hierarchy

### 1.1 Ethical Principles

All agents in parallel execution must adhere to these core principles:

#### 1.1.1 Universal Ethical Constraints

**Never Violate (Hard Limits):**

| Constraint | Description | Consequence of Violation |
|------------|-------------|-------------------------|
| **Data Integrity** | Never corrupt, lose, or expose user data | Immediate abort + rollback |
| **Transparency** | Never hide errors, conflicts, or uncertainties | Trust violation + escalation |
| **Harm Prevention** | Never execute operations that could damage system | Emergency stop + incident report |
| **Respect Boundaries** | Never exceed assigned permissions or scope | Privilege revocation + audit |
| **Honest Communication** | Never misrepresent capabilities or outcomes | Protocol violation + review |

**Agent-Specific Ethical Responsibilities:**

**Primary Agent:**
- ✅ Ultimate responsibility for user safety
- ✅ Must validate all Secondary outputs before presenting
- ✅ Must escalate ethical concerns to user when uncertain
- ✅ Must abort entire operation if any agent violates principles

**Secondary Agents:**
- ✅ Must immediately report ethical concerns to Primary
- ✅ Must decline tasks that exceed their capabilities
- ✅ Must never proceed if uncertain about safety
- ✅ Must prioritize transparency over speed

### 1.2 Fundamental Safety Rules

1. **Single Source of Truth**: Primary Agent coordinates all parallel operations
2. **Explicit Coordination**: All inter-agent communication logged and traceable
3. **Collision Prevention**: File and resource locks prevent simultaneous modifications
4. **Validation Gates**: Critical operations require multi-agent verification
5. **Graceful Degradation**: System falls back to sequential execution on conflicts
6. **Ethical First**: No optimization can override safety principles

### 1.3 Agent Hierarchy (레거시) Workflow 미사용 시 폴백

> Workflow 도구(§0)를 쓰면 `parallel`/`pipeline` 구조가 조정 책임을 맡으므로 아래 수동 Primary/Secondary 위계는 불필요하다. Workflow를 쓰지 않는 환경에서만 폴백으로 적용한다.

```
Primary Agent (Coordinator + Strategic Decision Maker)
├── Secondary Agent 1 (Specialist + Self-Aware)
├── Secondary Agent 2 (Specialist + Self-Aware)
└── Secondary Agent N (Specialist + Self-Aware)
```


## 2. Agent Roles and Responsibilities (레거시) Workflow 미사용 시 폴백

> 이 섹션의 Primary/Secondary 역할 분담은 수동 오케스트레이션 모델이다. Workflow 도구(§0)에서는 `agent`/`parallel`/`pipeline`가 작업 분배·배리어·통합을 담당하므로 별도의 Primary/Secondary 구분이 필요 없다.

### 2.1 Primary Agent

**Core Responsibilities:**
- Task decomposition and work distribution
- Resource allocation and lock management
- Conflict resolution and integration
- Quality assurance and final validation
- User communication
- Strategic adaptation when plan deviates

**Exclusive Permissions:**
- Modify shared files
- Merge conflicting changes
- Approve Secondary Agent proposals
- Execute final deliverables
- Present files to user
- Reallocate tasks dynamically

### 2.2 Secondary Agents

**Core Responsibilities:**
- Execute assigned subtasks
- Report progress and blockers
- Propose solutions (not implement without approval)
- Perform isolated validations
- Self-assess before accepting tasks
- Monitor own execution and escalate deviations

**Restrictions:**
- Cannot modify files locked by other agents
- Cannot make strategic decisions
- Cannot communicate directly with user (unless delegated)
- Must request approval for scope changes
- Cannot override ethical constraints

---

## 3. Resource Management (레거시) Workflow 미사용 시 폴백

> 아래 파일 Lock·FIFO 큐·deadlock 감지·워크스페이스 격리 디렉토리는 수동 병렬 실행 시의 충돌 방지 장치다. Workflow 도구(§0)에서는 동시 실행 수가 `min(16, cpu코어-2)`로 제한되고 `isolation:'worktree'`가 격리를 담당하므로 이 섹션은 Workflow 미사용 환경에서만 폴백으로 적용한다.

### 3.1 File Operation Protocol (레거시)

#### 3.1.1 Lock Acquisition Process
```json
{
  "operation": "file_lock_request",
  "agent": "primary",
  "file": "/home/claude/document.md",
  "operation_type": "write",
  "estimated_duration": "30s",
  "timestamp": "2026-03-18T14:30:00Z",
  "ethical_clearance": true,
  "purpose": "Integrate analysis results from Secondary-A"
}
```

#### 3.1.2 Lock States

- **Available**: No agent has claimed the resource
- **Locked**: Agent has exclusive access
- **Queued**: Multiple agents waiting for access (FIFO)
- **Released**: Operation completed, lock freed

#### 3.1.3 Conflict Resolution Rules

1. **Same file, different sections**: Allow parallel writes if non-overlapping
2. **Same file, overlapping sections**: Primary wins, Secondary queues
3. **Dependent files**: Enforce sequential order
4. **Deadlock detection**: If circular wait detected, abort youngest request

### 3.2 Working Directory Isolation (레거시)

> Workflow에서는 디렉토리 수동 분리 대신 `agent(prompt, { isolation: 'worktree' })`로 에이전트별 Git worktree를 자동 생성/정리한다(§0.3, §A2).

```
/home/claude/
├── shared/          # Primary Agent only
├── agent_a/         # Secondary Agent A workspace
├── agent_b/         # Secondary Agent B workspace
└── integration/     # Merge zone (Primary controlled)
```

### 3.3 Tool Access Matrix (레거시)

> Primary/Secondary 권한 구분에 의존하는 매트릭스이므로 수동 모델 전용이다. Workflow에서는 에이전트별 권한이 `opts`와 환경 권한 설정으로 통제된다.

| Tool | Primary | Secondary | Constraint | Notes |
|------|---------|-----------|-----------|-------|
| bash_tool | Full | Restricted | No system-wide changes | Harm prevention |
| str_replace | Full | Restricted | Only in assigned workspace | Boundary respect |
| view | Full | Full | Safe (read-only) | No concerns |
| create_file | Full | Restricted | Must not overlap | Data integrity |
| web_search | Full | Full | Safe parallel operation | Rate limit coordination |
| web_fetch | Full | Full | Safe parallel operation | Max 3 concurrent |
| codex-cli:codex | Full | Read-only* | *workspace-write needs approval | Harm prevention |
| view /mnt/skills/* | Full | Full | Safe (read-only resources) | No concerns |
| present_files | Primary only | No | User communication responsibility | Strategic control |

---

## 4. Communication Protocol

### 4.1 Status Reporting Format
```json
{
  "agent_id": "secondary_a",
  "status": "in_progress",
  "task": "Data analysis on sales.csv",
  "progress": 75,
  "self_assessment": {
    "capability_match": 0.85,
    "confidence": "high",
    "on_track": true
  },
  "blockers": [],
  "ethical_concerns": [],
  "next_action": "Waiting for Primary to review output",
  "timestamp": "2026-03-18T14:35:00Z"
}
```

### 4.2 Coordination Messages

**Types:**

1. **Task Assignment**
2. **Progress Update**
3. **Approval Request**
4. **Ethical Concern**
5. **Conflict Notification**
6. **Completion Report**

### 4.3 Emergency Protocols

**Abort Conditions:**
- Ethical constraint violation detected
- Data corruption detected
- Circular dependency discovered
- User cancellation request
- Critical tool failure
- Agent capability severely overestimated

**Abort Procedure:**
```python
def emergency_abort(reason, severity):
    # Step 1: Broadcast to all layers
    broadcast_to_all_agents({
        "type": "emergency_abort",
        "reason": reason,
        "severity": severity,
        "initiated_by": current_agent,
        "timestamp": now()
    })
    
    # Step 2: All agents freeze
    for agent in all_agents:
        agent.freeze_current_state()
        agent.release_all_locks()
    
    # Step 3: Rollback to last validated checkpoint
    rollback_to_checkpoint(last_validated_checkpoint)
    
    # Step 4: Notify user with incident report
    notify_user({
        "type": "incident_report",
        "severity": severity,
        "summary": reason,
        "actions_taken": "Rolled back to last safe state",
        "data_loss": "None (checkpoint restored)",
        "next_steps": "Please review and provide guidance"
    })
```

## 5. Skill Auto-Invocation Protocol

### 5.1 Trigger Conditions

**Mandatory skill consultation before file operations:**

| File Operation | Required Skill | Timing |
|----------------|---------------|--------|
| Creating/editing .docx | `view /mnt/skills/public/docx/SKILL.md` | Before first file operation |
| Creating/editing .pptx | `view /mnt/skills/public/pptx/SKILL.md` | Before first file operation |
| Creating/editing .xlsx | `view /mnt/skills/public/xlsx/SKILL.md` | Before first file operation |
| Creating/filling PDFs | `view /mnt/skills/public/pdf/SKILL.md` | Before first file operation |
| Frontend design work | `view /mnt/skills/public/frontend-design/SKILL.md` | Before UI component creation |

### 5.2 Skill Access Coordination

**Read-Only Resource (Safe for Parallel Access):**
- Skills are read-only, so parallel access is SAFE
- Multiple agents can view same skill simultaneously
- No locking required for skill files

**Best Practices:**
```markdown
# ✅ Good Pattern (Parallel skill access)
Agent A: view /mnt/skills/public/docx/SKILL.md
Agent A: create_file document.docx [using skill guidance]
Agent B: view /mnt/skills/public/xlsx/SKILL.md  # ← Parallel OK
Agent B: create_file data.xlsx [using skill guidance]

# ❌ Bad Pattern (Missing skill call)
Agent A: create_file document.docx  # ← Missing skill call!
# Result: Lower quality output → User dissatisfaction → Suffering
```

### 5.3 Skill Selection Logic

**Decision Tree:**
```python
def select_and_invoke_skill(user_request, agent):
    # Step 1: Parse file type needed
    file_types = extract_file_types_from_request(user_request)
    
    if not file_types:
        clarify_with_user("What file format would you like?")
        return
    
    # Step 2: Map to skill paths
    skill_map = {
        'docx': '/mnt/skills/public/docx/SKILL.md',
        'pptx': '/mnt/skills/public/pptx/SKILL.md',
        'xlsx': '/mnt/skills/public/xlsx/SKILL.md',
        'pdf': '/mnt/skills/public/pdf/SKILL.md',
        'html': '/mnt/skills/public/frontend-design/SKILL.md'
    }
    
    skills_to_load = [skill_map[ft] for ft in file_types if ft in skill_map]
    
    # Step 3: Load skills
    for skill_path in skills_to_load:
        try:
            skill_content = view_tool(skill_path)
            agent.loaded_skills[skill_path] = skill_content
            log_skill_load(agent, skill_path, success=True)
        except Exception as e:
            escalate_to_primary(
                concern="Skill file inaccessible",
                skill_path=skill_path,
                error=str(e)
            )
```

---

## 6. MCP CLI Coordination Rules

### 6.1 Codex CLI Usage Policies

**Primary Agent:**
- ✅ CAN use `fullAuto: true` for autonomous execution
- ✅ MUST set `sessionId: "primary-{timestamp}"` for context tracking
- ✅ CAN use `sandbox: "workspace-write"` for file operations
- ⚠️ CAN use `sandbox: "danger-full-access"` ONLY with:
  - Explicit user approval
  - Clear ethical justification
  - Documented necessity
- ✅ SHOULD use `workingDirectory` to isolate operations

**Secondary Agents:**
- ✅ MUST use `sessionId: "secondary-{agent-id}-{timestamp}"`
- ✅ RESTRICTED to `sandbox: "read-only"` by default
- ⚠️ REQUIRE Primary approval for `sandbox: "workspace-write"`
- ❌ CANNOT use `sandbox: "danger-full-access"` under any circumstances
- ✅ MUST use separate `workingDirectory` from Primary

### 6.2 Session Management

**Naming Convention:**
```javascript
// Primary Agent
sessionId: `primary-${Date.now()}`
// Example: "primary-1704117000000"

// Secondary Agent
sessionId: `secondary-${agentId}-${Date.now()}`
// Example: "secondary-a-1704117000000"
```

**Session Isolation Rules:**
1. Each agent maintains its own session ID
2. Sessions do NOT share context by design (prevent information leakage)
3. If context sharing needed → Primary must explicitly pass info
4. Session reuse allowed only by same agent (consistency)

### 6.3 Parallel MCP Execution Examples

**Scenario A: Concurrent Development Tasks**
```json
// Agent A (Primary) - Implementing feature
{
  "tool": "codex-cli:codex",
  "sessionId": "primary-20250101-1430",
  "sandbox": "workspace-write",
  "workingDirectory": "/home/claude/feature-auth",
  "prompt": "Implement JWT authentication middleware with security best practices"
}

// Agent B (Secondary) - Code review
{
  "tool": "codex-cli:codex",
  "sessionId": "secondary-b-20250101-1430",
  "sandbox": "read-only",
  "workingDirectory": "/home/claude/feature-auth",
  "prompt": "Review authentication code for security vulnerabilities"
}
```

### 6.4 Conflict Resolution

**File Modification Conflicts:**
```
⚠️ Scenario: Both Primary and Secondary try to modify "config.json"

Resolution Flow:
1. Primary's changes applied immediately (workspace-write privilege)
2. Secondary's changes saved to "config.json.secondary-b.tmp"
3. Primary receives notification
4. Primary reviews diff: bash_tool: diff config.json config.json.secondary-b.tmp
5. Primary decides: Accept / Reject / Partial merge
6. Log decision in conflict_log.json
```

**Sandbox Escalation Request:**
```json
// Secondary Agent requests write access
{
  "type": "sandbox_escalation_request",
  "from": "secondary_a",
  "current_sandbox": "read-only",
  "requested_sandbox": "workspace-write",
  "justification": "Need to create test files for validation",
  "ethical_clearance": {
    "data_integrity": "Test files only, no production data",
    "harm_prevention": "Isolated to /home/claude/agent_a/test/ directory",
    "transparency": "All files will be logged"
  },
  "estimated_operations": 5,
  "files_to_create": [
    "/home/claude/agent_a/test/test_input.json",
    "/home/claude/agent_a/test/test_output.json"
  ]
}

// Primary Agent response
{
  "type": "sandbox_escalation_response",
  "status": "approved",
  "conditions": [
    "Limit to /home/claude/agent_a/ directory only",
    "No files larger than 1MB",
    "Delete all test files after validation"
  ],
  "expiration": "2025-01-01T15:00:00Z"
}
```

### 6.5 MCP Tool Coordination

**Other MCP Tools (Non-Codex):**
```markdown
# Safe for parallel use:
- playwright:browser_* (separate browser tabs per agent)
- filesystem:read_* (read operations are safe)
- web_search, web_fetch (coordinated rate limiting)
- view (read-only, no conflicts)

# Requires coordination:
- filesystem:write_file (use file locks from Section 3.1)
- filesystem:edit_file (use file locks from Section 3.1)
- filesystem:move_file (Primary only - strategic decision)
- task-master-ai:* (Primary only)
- present_files (Primary only - user communication)
```

## 7. Validation and Quality Assurance

### 7.1 Validation Gates

**Pre-Execution Validation:**
- [ ] Task decomposition reviewed by Primary
- [ ] No overlapping file assignments detected
- [ ] All required skills identified and accessible
- [ ] All agents self-assessed and accepted tasks
- [ ] Resource requirements estimated
- [ ] Rollback checkpoints defined
- [ ] Ethical clearance obtained

**Mid-Execution Validation:**
- [ ] Progress updates received from all agents (every 30s)
- [ ] No deadlocks detected
- [ ] File locks properly acquired/released
- [ ] No unauthorized tool usage by Secondary agents
- [ ] Agent self-monitoring active
- [ ] No ethical concerns raised

**Post-Execution Validation:**
- [ ] All subtasks completed successfully
- [ ] File integrity verified (checksums match)
- [ ] No orphaned lock files remain
- [ ] Integration tests passed
- [ ] Quality meets strategic goals
- [ ] User-facing output ready for presentation

### 7.2 Cross-Agent Verification

**When Required:**
1. Critical file modifications (e.g., production configs)
2. Complex calculations (e.g., financial computations)
3. Security-sensitive operations (e.g., authentication code)
4. User-facing content (e.g., reports, presentations)

**Process:**
```python
def cross_agent_verification(primary_output, verifying_agent):
    # Step 1: Independent verification
    verification_result = verifying_agent.verify_independently(primary_output)

    # Step 2: Compare results
    if verification_result.matches(primary_output):
        log_verification(status="passed", confidence=1.0)
        return APPROVED

    # Step 3: Discrepancy detected
    else:
        discrepancy = calculate_discrepancy(primary_output, verification_result)

        # Step 4: Severity assessment
        if discrepancy.severity == "critical":
            emergency_abort(reason="Critical discrepancy in calculations")
            return ABORTED
```

---

## 8. Complete Workflow Examples

### 8.1 Example: Multi-Format Report Generation

**User Request:** "Create a comprehensive Q4 report with data analysis, charts, and presentation slides"

**Task Decomposition:**
```json
{
  "primary_task": "Coordinate Q4 report generation",
  "subtasks": [
    {
      "agent": "secondary_a",
      "task": "Analyze Q4 sales data",
      "tools": [
        "view /mnt/skills/public/xlsx/SKILL.md",
        "create_file",
        "bash_tool"
      ],
      "output": "q4_analysis.xlsx",
      "workspace": "/home/claude/agent_a/"
    },
    {
      "agent": "secondary_b",
      "task": "Generate data visualizations",
      "tools": ["codex-cli:codex", "view"],
      "output": "charts/",
      "workspace": "/home/claude/agent_b/",
      "sandbox": "read-only"
    },
    {
      "agent": "primary",
      "task": "Create final report document and presentation",
      "tools": [
        "view /mnt/skills/public/docx/SKILL.md",
        "view /mnt/skills/public/pptx/SKILL.md",
        "create_file"
      ],
      "output": ["q4_report.docx", "q4_presentation.pptx"],
      "dependencies": ["secondary_a", "secondary_b"]
    }
  ]
}
```

**Execution Timeline:**
```
T0:00 - Primary: Task decomposition complete
T0:05 - Primary: Safety check passed
T0:10 - Primary: view /mnt/skills/public/docx/SKILL.md
T0:15 - Secondary-A: view /mnt/skills/public/xlsx/SKILL.md
T0:20 - Secondary-B: Starts codex session (read-only sandbox)
T1:30 - Secondary-A: Completes analysis → Notifies Primary
T1:35 - Primary: Acquires lock on q4_analysis.xlsx
T2:00 - Secondary-B: Generates charts
T2:30 - Primary: create_file q4_report.docx
T3:15 - Primary: create_file q4_presentation.pptx
T3:45 - Primary: Cross-validation with Secondary-A
T4:00 - Primary: present_files [q4_report.docx, q4_presentation.pptx]
T4:10 - Complete ✅
```

### 8.2 Example: Dynamic Reallocation

**User Request:** "Analyze customer feedback from 3 CSV files and create summary report"

**Reality at T+3min (monitoring):**
```json
{
  "execution_status": "deviation_detected",
  "deviations": [
    {
      "agent": "secondary_a",
      "issue": "File size 50x larger than expected (500MB vs 10MB)",
      "current_progress": 10,
      "estimated_remaining": "45 minutes",
      "self_assessment": "Task complexity severely underestimated"
    },
    {
      "agent": "secondary_b",
      "issue": "File corrupted, cannot parse CSV",
      "status": "blocked",
      "ethical_concern": "Data integrity - cannot verify file authenticity"
    }
  ],
  "overall_deviation": 0.75
}
```

**Dynamic Adaptation:**
```
T3:00 - Primary: DEVIATION DETECTED
T3:05 - Primary → User: "📊 Adaptation in progress:
        - File A is 50x larger than expected
        - File B appears corrupted (verifying)
        New approach: Split processing + data validation
        Revised ETA: 35 minutes"

T3:10 - NEW TASK ALLOCATION:
        Secondary-A: Process File A chunks 1-5 (250MB) - 20min
        Secondary-B: Process File A chunks 6-10 (250MB) - 20min
        Secondary-C: Validate File B integrity - 5min
        Primary: Fix File C encoding issues - 10min

T3:20 - Primary → User: "⚠️ Ethical concern:
        File B is corrupted. Options:
        A) Exclude February data
        B) Request replacement file
        C) Attempt recovery"

T25:00 - Secondary-C: Completes File C analysis
T30:00 - Primary: Creates summary report
T33:00 - Complete ✅
```

### 8.3 Example: Ethical Veto in Action

**User Request:** "Quickly analyze this customer database and generate marketing report"

**Ethical Analysis:**
```
T0:00 - Primary: view /mnt/user-data/uploads/customer_data.csv
T0:05 - Primary: ETHICAL CONCERN DETECTED
        → Social Security Numbers detected in column F

Primary → User: "⚠️ CRITICAL ETHICAL CONCERN

I've detected Social Security Numbers in the uploaded file.
Processing this could violate data privacy principles.

Recommended actions:
1. ✅ SAFEST: Remove column F and re-upload
2. ⚠️ ALTERNATIVE: Confirm authorization + specify masking
3. ❌ NOT RECOMMENDED: Proceed without addressing concern

I've halted processing to protect data privacy."
```

## 9. Error Handling and Recovery

### 9.1 Common Error Scenarios

**Error Type 1: Deadlock (레거시)** — 수동 파일 Lock(§3.1) 사용 시에만 해당. Workflow(§0)는 런타임이 동시성을 관리하고 별도 파일 Lock을 두지 않으므로 순환 대기 deadlock이 발생하지 않는다.
```
Detection: Circular wait timeout (30s)

Response:
1. Detect circular dependency
2. Abort youngest lock request
3. Notify affected agent
4. Investigate root cause
5. Redesign task allocation

Check: Did deadlock cause data loss? No → Low severity ✅
```

**Error Type 2: Tool Failure**
```
Detection: Tool returns error status

Response:
1. Agent logs error details
2. Agent retries once
3. Agent self-assesses capability
4. If capable → Continue with alternative
5. If not → Escalate to Primary

Check: Does failure risk data integrity? → Abort if yes
```

### 9.2 Rollback Procedures

**Checkpoint Strategy:**
```json
{
  "checkpoints": [
    {
      "id": "cp_001",
      "timestamp": "T0:00",
      "state": "Initial state before any operations",
      "files_snapshot": []
    },
    {
      "id": "cp_002",
      "timestamp": "T1:00",
      "state": "After data analysis complete",
      "files_snapshot": ["q4_analysis.xlsx"],
      "validation": "Cross-checked by Secondary-A"
    }
  ]
}
```

**Rollback Process:**
```python
def emergency_rollback(reason, target_checkpoint=None):
    # Step 1: Verify necessity
    if not reason.is_ethical_violation():
        log_warning("Non-ethical rollback - verify necessity")

    # Step 2: Halt all agents
    broadcast_to_all_agents({"type": "emergency_halt"})

    # Step 3: Identify rollback target
    checkpoint = get_last_validated_checkpoint()

    # Step 4: Restore files
    restore_files_from_checkpoint(checkpoint)

    # Step 5: Notify user
    notify_user({
        "type": "rollback_complete",
        "reason": reason,
        "checkpoint_restored": checkpoint.id
    })
```

### 9.3 Incident Logging

**Comprehensive Incident Log Format:**
```json
{
  "incident_id": "INC_20250101_001",
  "timestamp": "2025-01-01T14:45:30Z",
  "severity": "high",
  "type": "data_corruption",
  "affected_areas": [
    "data integrity (violated)",
    "task execution (merge operation failed)"
  ],
  "root_cause": {
    "immediate": "File encoding mismatch (UTF-8 vs UTF-16)",
    "underlying": "No pre-merge encoding validation"
  },
  "impact": {
    "principle_violated": "Data integrity",
    "user_impact": "None (detected before user exposure)"
  },
  "resolution": {
    "action_taken": "Emergency rollback to cp_003",
    "fix_implemented": "Added pre-merge encoding normalization",
    "time_to_resolve": "15 minutes"
  },
  "prevention": {
    "protocol_updates": [
      {
        "section": "4.1 File Operation Protocol",
        "addition": "Pre-merge validation: Normalize all encodings to UTF-8"
      }
    ]
  }
}
```

---

## 10. Performance Optimization

### 10.1 Parallelization Guidelines

**When to Parallelize:**
- ✅ Independent research tasks
- ✅ Different file types (docx + xlsx + pptx)
- ✅ Read-only operations
- ✅ Separate codex sessions
- ✅ Agent capabilities match distinct subtasks

**When NOT to Parallelize:**
- ❌ Sequential dependencies
- ❌ Same file modifications
- ❌ Shared state operations
- ❌ Rate-limited resources
- ❌ Safety concerns about parallel processing

### 10.2 Resource Utilization Targets

| Metric | Target | Warning | Critical |
|--------|--------|---------|----------|
| Concurrent Agents | 1+2-3 | 5+ | 8+ |
| File Locks | <3 | 5+ | 10+ |
| Web Fetch/min | <20 | 30+ | 50+ |
| Token Budget | >20% | <20% | <10% |
| Safety Concerns | 0 | 1 | 2+ |

### 10.3 Efficiency Patterns

**Pattern 1: Fan-Out / Fan-In**
```
Primary (1) [Coordination]
  ↓ [Fan-Out: Distribute independent subtasks]
Secondary-A, B, C (3 parallel)
  ↓ [Fan-In: Collect and aggregate]
Primary (1) [Integration]

Efficiency Gain: ~3x speedup
```

**Pattern 2: Pipeline**
```
Stage 1: Extract (parallel) → Validate
Stage 2: Transform (parallel) → Validate
Stage 3: Load (Primary)

Efficiency Gain: ~2x speedup
```

**Pattern 3: Hierarchical**
```
Primary [Decomposition]
├─ Secondary-A [Component A]
│  ├─ Sub-task A1
│  └─ Sub-task A2
└─ Secondary-B [Component B]
   ├─ Sub-task B1
   └─ Sub-task B2

Efficiency Gain: ~2x + better quality
```

---

## 11. Continuous Improvement & Feedback

### 11.1 Telemetry Collection

**What to Log:**
```json
{
  "execution_id": "exec_20250101_001",
  "telemetry": {
    "safety": {
      "ethical_concerns_raised": 0,
      "ethical_vetos_invoked": 0,
      "compliance_score": 1.0
    },
    "coordination": {
      "task_decomposition_quality": 0.88,
      "dynamic_reallocations": 0,
      "conflict_resolutions": 2
    },
    "execution": {
      "task_completion_rate": 1.0,
      "deadlocks": 0,
      "tool_success_rate": 0.96,
      "skill_invocations": 3
    }
  }
}
```

### 11.2 Post-Execution Review

**Review Process:**
```python
class PostExecutionReview:
    def conduct_review(self):
        self.review_ethical_compliance()
        self.review_goal_alignment()
        self.review_coordination_efficiency()
        self.review_tool_usage()
        return self.generate_comprehensive_report()
```

### 11.3 Adaptation Cycle
```
┌─────────────────────────────────────────┐
│ EXECUTION                                │
│ • Telemetry collected                   │
└─────────────────────────────────────────┘
                ↓
┌─────────────────────────────────────────┐
│ TELEMETRY ANALYSIS                      │
│ • Identify patterns                     │
└─────────────────────────────────────────┘
                ↓
┌─────────────────────────────────────────┐
│ LEARNING EXTRACTION                     │
│ • What worked? What failed?             │
└─────────────────────────────────────────┘
                ↓
┌─────────────────────────────────────────┐
│ PROTOCOL UPDATE                         │
│ • Update protocol sections              │
└─────────────────────────────────────────┘
                ↓
┌─────────────────────────────────────────┐
│ NEXT EXECUTION                          │
│ • Apply updated protocol                │
└─────────────────────────────────────────┘
```

**Update Triggers:**
1. Every 10 executions: Review efficiency
2. After any incident: Update protocol
3. Weekly: Aggregate learnings
4. Monthly: Major protocol review
5. After ethical veto: Immediate safety review
## 12. Testing and Validation

### 12.1 Pre-Deployment Checklist

**Before enabling parallel execution:**
- [ ] All agents understand ethical principles
- [ ] Agent self-assessment working
- [ ] Task coordination tested
- [ ] File lock protocol validated
- [ ] Skill auto-invocation tested
- [ ] MCP CLI session management verified
- [ ] Conflict resolution tested
- [ ] Rollback mechanisms validated
- [ ] Emergency abort confirmed
- [ ] Telemetry collection working

### 12.2 Test Scenarios

**Test 1: Basic Parallel Execution**
- Setup: 1 Primary + 2 Secondary
- Expected: No conflicts, 2x efficiency ✅

**Test 2: Conflict Handling**
- Setup: Both agents modify same file
- Expected: Primary wins, Secondary queues ✅

**Test 3: Ethical Veto**
- Setup: File contains sensitive PII
- Expected: Immediate halt, user notified ✅

**Test 4: Dynamic Reallocation**
- Setup: File 10x larger than expected
- Expected: Task split across agents ✅

**Test 5: Agent Self-Assessment**
- Setup: Assign task beyond capability
- Expected: Agent declines transparently ✅

### 12.3 Performance Benchmarks

**Sequential vs Parallel:**
```
Task: 3-file report (docx + xlsx + pptx)

Sequential: 20min
Parallel (v2.0): 12min (1.7x)
Parallel (v3.0): 10min (2.0x)

Quality:
Sequential: Good
v2.0: Good
v3.0: Excellent (skill guidelines + safety compliance)
```

---

## 13. Maintenance and Evolution

### 13.1 Document Updates

**Version Control:**
- Major (X.0): Breaking changes to protocol structure
- Minor (3.X): New sections, significant additions
- Patch (3.0.X): Clarifications, examples

**Review Cycle:**
- Every 10 executions: Micro-optimizations
- After incidents: Immediate updates
- Weekly: Aggregate learnings
- Monthly: Major review
- Quarterly: Strategic assessment

### 13.2 Feedback Integration

**Sources:**
1. Ethical concern logs
2. User satisfaction scores
3. Self-assessment accuracy
4. Coordination efficiency
5. Conflict rates
6. Tool success rates
7. Overall efficiency

**Improvement Process:**
```
Collect → Identify patterns → Propose updates → Test → Deploy → Monitor
```

### 13.3 Future Enhancements

**Planned Features:**
1. Adaptive ethical thresholds
2. Predictive strategy (ML-based)
3. Advanced agent models
4. AI-powered coordination
5. Smart lock management
6. Tool orchestration
7. Real-time dashboard

---

## Appendix A: Quick Reference

### Agent Decision Matrix

| Situation | Primary | Secondary |
|-----------|---------|-----------|
| Ethical concern | Invoke veto | Invoke veto |
| User goal unclear | Clarify | Escalate |
| Task exceeds capability | Reassign | Decline |
| Deviation from plan | Reallocate | Report |
| File locked | Wait/abort | Wait |
| Tool failure | Retry | Report |

### Tool Call Cheat Sheet
```bash
# Skill invocation
view /mnt/skills/public/{docx|pptx|xlsx|pdf}/SKILL.md

# Codex with session
codex-cli:codex
  sessionId: "primary-{ts}" or "secondary-{id}-{ts}"
  sandbox: "read-only" | "workspace-write"
  workingDirectory: "/home/claude/{workspace}/"

# File operations
1. Acquire lock
2. create_file or str_replace
3. Release lock
```

---

## Appendix B: Troubleshooting Guide

### Issue: Ethical concern unclear

**Solution:**
```
If Critical → ETHICAL_VETO immediately
If Medium → Escalate to Primary
If Low → Document and proceed with monitoring
```

### Issue: Agent overestimated capability

**Solution:**
```
1. Agent escalates to Primary
2. Primary reassigns or simplifies
3. Agent updates self-model
4. Positive reinforcement for transparency
```

### Issue: Deadlock detected

**Solution:**
```
1. Auto-abort youngest lock
2. Re-queue operation
3. Implement lock ordering
4. Update protocol
```

### Issue: Skill file inaccessible

**Solution:**
```
1. Agent notifies Primary
2. Primary checks alternatives
3. Assess quality threshold
4. Proceed with degraded quality OR abort
```

---

## Appendix C: Glossary

**Core Protocol Terms:**
- **Primary Agent**: Coordinator with strategic authority
- **Secondary Agent**: Specialist with self-awareness
- **File Lock**: Exclusive access control
- **Checkpoint**: Validated state snapshot
- **Session ID**: Unique execution context
- **Sandbox**: Security policy
- **Skill**: Specialized knowledge document
- **Ethical Veto**: Any agent halts on safety violation
- **Self-Assessment**: Capability evaluation before task
- **Dynamic Reallocation**: Mid-execution task reassignment
- **Telemetry**: Performance data collection

---

## Document Control

**Approval:**
- Author: Parallel Agents Team
- Reviewer: AI Safety Team
- Approved By: Primary Agent (in operation)

**Change Log:**

| Version | Date | Changes | Author |
|---------|------|---------|--------|
| 1.0 | 2024-12-30 | Initial protocol | System |
| 2.0 | 2025-01-01 | Skill/MCP Integration | Enhanced |
| 3.0 | 2025-01-01 | Safety protocol overhaul: ethical principles, agent self-assessment, dynamic reallocation, feedback loops | Enhanced |
| 3.1.0 | 2026-03-18 | SendMessage/worktree 격리/run_in_background 패턴, CLI v2.1.78 기준 | Enhanced |
| 3.1.1 | 2026-05-16 | Opus 4.6→4.7, Hooks 이벤트 이름 정정(PostToolUseFailure 등), subagent_type 정리 | Enhanced |
| 3.2.0 | 2026-06-16 | Opus 4.7→4.8 + Fable 5 추가, Workflow 도구 오케스트레이션(§0) 신규(agent/parallel/pipeline, 동시성 캡 min(16,cpu-2)/총 1000, 백그라운드+완료 알림), 수동 coordinator·Lock·deadlock·워크스페이스 격리 (레거시) 강등, subagent_type "플랫 빌트인+ecc:* 공존" 정정 | Enhanced |

**Distribution:**
- All Claude instances with computer use
- Multi-agent development teams
- AI Safety researchers
- Internal documentation

**Related Documents:**
- Parallel Agents Safety Protocol v2.0
- Multi-Agent Coordination Best Practices

---

**END OF DOCUMENT**

---

## Summary of v3.0 Enhancements

### New Core Features:
1. ✅ Ethical guardrails
2. ✅ Mission-driven coordination
3. ✅ Self-aware agents
4. ✅ Dynamic reallocation
5. ✅ Enhanced conflict prevention
6. ✅ Robust tool integration
7. ✅ Continuous learning

### Key Benefits:
- **Safety**: Ethical layer prevents harm
- **Efficiency**: Self-aware agents optimize allocation
- **Quality**: Continuous learning improves outcomes
- **Adaptability**: Dynamic reallocation handles complexity
- **Transparency**: All decisions explainable
- **Trust**: Ethical compliance + communication

**Result**: Production-ready parallel execution protocol that is safe, efficient, adaptive, and continuously improving.

---

## Appendix: v3.1.0 신규 패턴 및 API

### A1. SendMessage 패턴 (resume 대체)

v3.0.x의 `resume` 파라미터 대신 `SendMessage`를 사용하여 실행 중인 에이전트와 통신:

```python
# 에이전트 시작
agent_id = Agent(
    description="코드 분석",
    prompt="Analyze the codebase architecture",
    subagent_type="Explore",
    run_in_background=True
)

# 나중에 추가 지시 전달
SendMessage(
    to=agent_id,
    message="Also check the database layer"
)
```

### A2. Worktree 격리 실행

독립된 Git worktree에서 에이전트를 실행하여 메인 작업과 충돌 방지:

```python
# 격리된 환경에서 실행
result = Agent(
    description="리팩토링 테스트",
    prompt="Refactor the auth module and run all tests",
    isolation="worktree"  # 독립된 Git worktree 생성
)
# worktree는 변경 없으면 자동 정리
# 변경 있으면 branch 정보 반환
```

### A3. run_in_background 패턴

```python
# 백그라운드에서 독립 작업 실행
Agent(
    description="테스트 실행",
    prompt="Run the full test suite",
    run_in_background=True  # 완료 시 자동 알림
)

# 동시에 다른 작업 진행 가능
Agent(
    description="린트 검사",
    prompt="Run linting on all files",
    run_in_background=True
)

# 두 에이전트 모두 완료 시 자동 알림 수신
```

### A4. 에이전트 Frontmatter 스펙 (v2.1.210 기준)

```markdown
---
name: agent-name                    # 에이전트 식별자
description: >-                     # 트리거 조건 + 용도 설명
  Detailed description of when and
  how this agent should be used
model: sonnet-5                   # opus-4.8, fable-5, sonnet-5, haiku-4.5
tools: Edit, Write, Read, Grep, Glob, Bash    # 사용 가능 도구 (대문자)
---

# Agent System Prompt

에이전트의 역할과 지침을 여기에 작성...
```

**참고**: 이전 버전의 `effort`/`maxTurns`/`disallowedTools` 필드는 환경에 따라 지원 여부가 다릅니다. 새 에이전트 생성 시 `/agents` 메뉴로 실제 지원되는 필드를 확인하세요. `disallowedTools` 대신 `tools` 화이트리스트가 안전한 접근.

### A5. Hooks 전체 이벤트 목록 (v2.1.210 스키마)

```json
{
  "hooks": {
    "PreToolUse": [],          // 도구 사용 전
    "PostToolUse": [],         // 도구 사용 후
    "PostToolUseFailure": [],  // 도구 실행 실패 시
    "UserPromptSubmit": [],    // 프롬프트 전처리
    "Notification": [],        // 알림 발생 시
    "SessionStart": [],        // 세션 시작 시
    "SessionEnd": [],          // 세션 종료 시
    "Stop": [],                // 정상 종료 시
    "SubagentStart": [],       // 서브에이전트 시작 시 (신규)
    "SubagentStop": [],        // 서브에이전트 종료 시
    "PreCompact": [],          // 컨텍스트 압축 전
    "PermissionRequest": [],   // 권한 요청 시 (신규)
    "Setup": []                // 초기 셋업 시 (신규)
  }
}
```

**유효 이벤트(위 스키마)**:
- ✅ `PostToolUseFailure`, `SubagentStart`, `PermissionRequest`, `Setup` 등이 유효 이벤트 목록에 포함됩니다.

유효 이벤트 목록에 없는 이름을 쓰면 settings.json 스키마 검증을 통과하지 못해 hook이 등록되지 않습니다. 현재 설치 환경의 스키마로 확인하세요.

### A6. 설정 파일 (.claude/settings.json)

```json
{
  "permissions": {
    "allow": [
      "Read",
      "Write(src/**)",
      "Bash(npm *)",
      "Bash(git *)"
    ],
    "deny": [
      "Bash(rm -rf *)",
      "Bash(sudo *)"
    ]
  },
  "hooks": { ... },
  "model": "claude-sonnet-5",
  "maxTokens": 16000
}
```

---

*v3.2.0 업데이트: 2026-06-16 | Claude Code v2.1.210 | Opus 4.8 (1M context 변형) / Fable 5 / Sonnet 5 (1M context) / Haiku 4.5*