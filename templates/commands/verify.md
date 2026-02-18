---
description: Run verification loop (type check + lint + test + build)
---

Run the Boris Cherny verification feedback loop. Execute each step and fix errors before proceeding:

## Step 1: Type Check
Run the type checker for this project:
- TypeScript: `npx tsc --noEmit`
- Python: `mypy src/` or `pyright`

If errors found: Fix them, then re-run.

## Step 2: Lint
Run the linter:
- JavaScript/TypeScript: `npm run lint` or `npx eslint src/`
- Python: `ruff check src/` or `pylint src/`

If errors found: Fix them, then re-run.

## Step 3: Test
Run the test suite:
- JavaScript/TypeScript: `npm test`
- Python: `pytest --tb=short`

If failures: Fix them, then re-run.

## Step 4: Build (if applicable)
Run the build:
- `npm run build` or equivalent

If errors: Fix them, then re-run.

## Rules
- Fix errors at each step before moving to the next
- Maximum 2 fix attempts per step; if still failing, stop and analyze root cause
- Report final status: PASS or FAIL with details
- Never skip a step
