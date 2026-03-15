---
description: Boris Cherny style verification loop - verify all quality gates pass
---

Run Boris Cherny style verification feedback loop.

## Process

1. **Detect project type** from package.json, pyproject.toml, etc.

2. **Run verification checks** in order:

### TypeScript/JavaScript
```bash
npx tsc --noEmit          # Type check
npm run lint               # Lint
npm test                   # Tests
npm run build              # Build
```

### Python
```bash
python -m mypy src/        # Type check
ruff check src/            # Lint
pytest                     # Tests
```

3. **Report results** with pass/fail for each check

4. **If any check fails**:
   - Show exact error messages
   - Suggest fixes
   - After fixing, re-run failed checks

5. **Success criteria**: ALL checks must pass with 0 errors

## Important
- Run checks in order (type -> lint -> test -> build)
- Stop and report on first failure
- After fix, only re-run the failed check and subsequent ones
- Never skip a failing check

$ARGUMENTS
