---
# 출처: docs/Claude code system setup/실전 예제.md
name: pr-generator
description: Generate comprehensive PR descriptions from git diff and commit messages
---

# PR Description Generator

## Instructions
1. Analyze git diff
2. Read commit messages
3. Identify changed files
4. Detect breaking changes
5. Generate PR description

## Output Format
```markdown
## Summary
[Brief description of changes]

## Changes
- Feature: [New features added]
- Fix: [Bugs fixed]
- Refactor: [Code improvements]

## Breaking Changes
[Any breaking changes]

## Testing
- [ ] Unit tests updated
- [ ] E2E tests passed
- [ ] Manual testing completed

## Screenshots
[If UI changes]

## Related Issues
Closes #[issue-number]
```
