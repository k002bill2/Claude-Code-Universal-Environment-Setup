# Parallel Agents Safety Protocol

## Overview
Protocol for coordinating multiple agents working in parallel.

## Core Principles

### 1. File Ownership
- Each file is owned by ONE agent at a time
- No concurrent edits to the same file
- Claim files before editing

### 2. Communication
- Use task list for coordination
- Report blockers immediately
- Mark tasks complete when done

### 3. Conflict Prevention
- Check file status before editing
- Use lock-free patterns where possible
- Resolve conflicts through task priority

## Agent Hierarchy
```
Lead Agent (Orchestrator)
├── Specialist Agent A (owns files in domain A)
├── Specialist Agent B (owns files in domain B)
└── Specialist Agent C (owns files in domain C)
```

## Workflow
1. Lead decomposes task into independent subtasks
2. Each subtask gets assigned to a specialist
3. Specialists work on non-overlapping files
4. Lead reviews and integrates results
5. Quality gates run on merged output

## Error Recovery
- If agent fails: Lead re-assigns or fixes
- If conflict detected: Stop, resolve, continue
- If blocked: Notify lead, work on unblocked tasks
