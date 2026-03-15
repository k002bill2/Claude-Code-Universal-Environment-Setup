---
description: Run comprehensive health check (type check, lint, test, build)
---

Run a comprehensive project health check. Detect the project type and run all applicable checks:

## For TypeScript/JavaScript projects (package.json exists):
1. `npx tsc --noEmit` - Type check
2. `npm run lint` - Lint check (if script exists)
3. `npm test` - Run tests (if script exists)
4. `npm run build` - Build check (if script exists)

## For Python projects (pyproject.toml or setup.py exists):
1. `python -m mypy src/` - Type check (if mypy configured)
2. `ruff check src/` - Lint check (if ruff configured)
3. `pytest` - Run tests
4. `python -m build` - Build check (if applicable)

Report results in a summary table:

```
| Check | Status | Details |
|-------|--------|---------|
| Type Check | PASS/FAIL | ... |
| Lint | PASS/FAIL | ... |
| Tests | PASS/FAIL | ... |
| Build | PASS/FAIL | ... |
```

Skip checks that are not configured in the project.
$ARGUMENTS
