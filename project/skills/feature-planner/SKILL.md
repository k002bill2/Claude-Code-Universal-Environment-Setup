---
name: feature-planner
description: Creates phase-based feature plans with quality gates and incremental delivery structure. Use when planning features, organizing work, breaking down tasks, creating roadmaps, or structuring development strategy.
disable-model-invocation: true
---

# Feature Planner

## Purpose
Generate structured, phase-based plans where:
- Each phase delivers complete, runnable functionality
- Quality gates enforce validation before proceeding
- User approves plan before any work begins
- Progress tracked via markdown checkboxes
- Each phase is 1-4 hours maximum

## Planning Workflow

### Step 1: Requirements Analysis
1. Read relevant files to understand codebase architecture
2. Identify dependencies and integration points
3. Assess complexity and risks
4. Determine appropriate scope (small/medium/large)

### Step 2: Phase Breakdown with TDD Integration
Break feature into 3-7 phases where each phase:
- **Test-First**: Write tests BEFORE implementation
- Delivers working, testable functionality
- Takes 1-4 hours maximum
- Follows Red-Green-Refactor cycle
- Has measurable test coverage requirements
- Can be rolled back independently
- Has clear success criteria

**Phase Structure**:
- Phase Name: Clear deliverable
- Goal: What working functionality this produces
- **Test Strategy**: What test types, coverage target, test scenarios
- Tasks (ordered by TDD workflow):
  1. **RED Tasks**: Write failing tests first
  2. **GREEN Tasks**: Implement minimal code to make tests pass
  3. **REFACTOR Tasks**: Improve code quality while tests stay green
- Quality Gate: TDD compliance + validation criteria
- Dependencies: What must exist before starting
- **Coverage Target**: Specific percentage or checklist for this phase

### Step 3: Plan Document Creation
Generate plan document including:
- Overview and objectives
- Architecture decisions with rationale
- Complete phase breakdown with checkboxes
- Quality gate checklists
- Risk assessment table
- Rollback strategy per phase
- Progress tracking section

### Step 4: User Approval
**CRITICAL**: Get explicit approval before proceeding.

### Step 5: Document Generation
1. Create plan document with all checkboxes unchecked
2. Add clear instructions in header about quality gates
3. Inform user of plan location and next steps

## Quality Gate Standards

Each phase MUST validate:

- [ ] Project builds/compiles without errors
- [ ] Tests written BEFORE production code
- [ ] All existing tests pass
- [ ] New tests added for new functionality
- [ ] Linting passes with no errors
- [ ] Type checking passes (if applicable)
- [ ] No regressions in existing functionality
- [ ] No new security vulnerabilities

## Phase Sizing Guidelines

**Small Scope** (2-3 phases, 3-6 hours):
- Single component or simple feature

**Medium Scope** (4-5 phases, 8-15 hours):
- Multiple components, DB changes, API work

**Large Scope** (6-7 phases, 15-25 hours):
- Complex feature spanning multiple areas

## Risk Assessment

For each risk, specify:
- Probability: Low/Medium/High
- Impact: Low/Medium/High
- Mitigation Strategy: Specific action steps
