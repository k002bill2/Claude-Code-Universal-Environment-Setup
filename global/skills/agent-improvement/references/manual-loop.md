# Manual Improvement Loop — Data 수집·분석·개선 액션

수동으로 트레이스를 수집하고 패턴을 추출해 에이전트/도구 설명을 개선하는 절차. SKILL.md의 1-4단계 사이클(COLLECT/ANALYZE/DIAGNOSE/IMPROVE)에서 referenced.

## Data Collection Schemas

### Failure/Success Pattern (`.temp/improvement/patterns/`)

```json
{
  "pattern_id": "pat_001",
  "type": "failure|success",
  "frequency": 5,
  "context": {
    "task_type": "ui_component_creation",
    "agent": "web-ui-specialist",
    "phase": "implementation"
  },
  "description": "Agent often misses accessibility labels",
  "examples": [
    {
      "session_id": "sess_abc",
      "file": "AgentCard.tsx",
      "issue": "Missing accessibilityLabel on TouchableOpacity"
    }
  ],
  "proposed_fix": "Add explicit reminder in agent prompt",
  "status": "identified|proposed|implemented|validated"
}
```

### Tool Usage Pattern

```json
{
  "tool": "read",
  "usage_count": 1523,
  "success_rate": 0.98,
  "avg_duration_ms": 45,
  "common_errors": [
    {
      "error": "File not found",
      "frequency": 23,
      "cause": "Path alias not resolved"
    }
  ],
  "improvement_opportunities": [
    "Add path alias resolution hint to tool description"
  ]
}
```

## Analysis Templates

### Failure Analysis Report

```markdown
## Failure Analysis Report

### Category 1: Agent Boundary Violations
- Frequency: 12 occurrences
- Pattern: UI agent attempting to modify services
- Root Cause: Task boundaries not clear in delegation
- Fix: Add explicit "DO NOT" list to delegation template

### Category 2: Missing Dependencies
- Frequency: 8 occurrences
- Pattern: UI agent starts before types available
- Root Cause: Dependency order not enforced
- Fix: Add dependency check before spawning

### Category 3: Tool Misuse
- Frequency: 5 occurrences
- Pattern: Using grep instead of read for known files
- Root Cause: Tool descriptions don't clarify when to use each
- Fix: Update tool descriptions with decision criteria
```

### Bottleneck Analysis Report

```markdown
## Bottleneck Analysis

### Bottleneck 1: Sequential Agent Spawning
- Impact: 40% time overhead
- Pattern: Agents spawned one at a time
- Fix: Spawn independent agents in parallel

### Bottleneck 2: Excessive Iterations
- Impact: 2x token usage
- Pattern: Average 3.2 iterations per task
- Fix: Improve initial task decomposition

### Bottleneck 3: Quality Gate Failures
- Impact: 25% rework
- Pattern: TypeScript errors on first integration
- Fix: Add pre-integration type check
```

## Improvement Action Templates

### Tool Description Update

**Before:**
```
Read: Reads a file from the filesystem
```

**After:**
```
Read: Reads a file from the filesystem.
- Use when you know the exact file path
- Prefer over grep for reading specific known files
- Use path aliases (@components, @services)
- Returns line-numbered content
```

### Agent Prompt Update

**Before:**
```
You are a web UI specialist...
```

**After:**
```
You are a web UI specialist...

CRITICAL REMINDERS:
- Always add accessibilityLabel to interactive elements
- Use memo() for components with complex props
- Check LINE_COLORS constant for subway line colors
```

### Delegation Template Update

**Before:**
```
### Task Boundaries
- DO NOT modify services
```

**After:**
```
### Task Boundaries (EXPLICIT)
Files you CAN modify:
- src/components/**
- src/screens/**

Files you CANNOT modify:
- src/services/** (backend agent)
- src/models/** (shared types)
- **/__tests__/** (test agent)

STOP if you need to modify excluded files.
```
