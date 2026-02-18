# Quality Gates

All agents MUST pass these gates before marking work as complete.

## Gate 1: Type Safety
- No TypeScript/type errors
- No `any` types without justification
- Run: `tsc --noEmit` or language equivalent

## Gate 2: Linting
- No linting errors (warnings acceptable with reason)
- Run: `npm run lint` or equivalent

## Gate 3: Tests
- All existing tests pass
- New code has tests (>80% coverage)
- Run: `npm test` or equivalent

## Gate 4: Build
- Clean build with no errors
- Run: `npm run build` or equivalent

## Verification Command
```bash
# Run all gates in sequence
tsc --noEmit && npm run lint && npm test && npm run build
```

## When Gates Fail
1. Fix the issue (do not skip)
2. If stuck after 2 attempts, analyze root cause
3. Document the issue and propose alternative approach
4. Never bypass gates without explicit user approval
