---
description: Auto-detect task type and run full pipeline (plan -> implement -> verify -> commit)
---

Analyze the current request and automatically execute the appropriate pipeline.

## Step 1: Mode Detection

Detect the task type from the request:
- **feature**: New functionality (keyword: "추가", "만들어", "구현", "add", "create", "implement")
- **bugfix**: Bug fix (keyword: "수정", "고쳐", "버그", "fix", "bug", "error")
- **refactor**: Code improvement (keyword: "리팩토링", "개선", "정리", "refactor", "improve", "cleanup")

## Step 2: Plan

1. Analyze the codebase to understand the current state
2. Create a plan with phases and quality gates
3. Get user approval before proceeding

## Step 3: Implement (TDD)

For each phase:
1. Write failing tests first (RED)
2. Implement minimal code to pass (GREEN)
3. Refactor while tests stay green (REFACTOR)

## Step 4: Verify

Run the full verification loop:
- Type check
- Lint
- Tests
- Build

## Step 5: Commit

If all checks pass:
1. Stage changes
2. Generate Conventional Commits message
3. Commit (with user approval)

## Important
- Never skip the verification step
- Get user approval at plan and commit stages
- Follow TDD workflow strictly

$ARGUMENTS
