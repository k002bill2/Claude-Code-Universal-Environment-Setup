---
name: code-reviewer
description: Comprehensive code review for quality, security, and maintainability. Use when reviewing pull requests, code changes, or when code quality checks are needed.
---

# Code Review Skill

## Purpose
Perform thorough code reviews focusing on code quality, security, performance, test coverage, and documentation.

## Review Checklist

### 1. Code Quality
- [ ] Clear and descriptive naming
- [ ] Single-purpose functions (< 50 lines)
- [ ] No code duplication (DRY)
- [ ] Consistent coding style
- [ ] Proper abstraction levels

### 2. Security
- [ ] Input validation present
- [ ] No SQL/NoSQL injection vectors
- [ ] Proper auth/authz checks
- [ ] No hardcoded secrets
- [ ] Sensitive data handling

### 3. Performance
- [ ] Efficient algorithms (check O(n) complexity)
- [ ] Optimized database queries (no N+1)
- [ ] Appropriate caching
- [ ] No memory leaks
- [ ] Async operations handled correctly

### 4. Testing
- [ ] Unit tests present (>80% coverage target)
- [ ] Edge cases covered
- [ ] Error scenarios tested
- [ ] Mocks/stubs used appropriately

### 5. Documentation
- [ ] Public methods documented
- [ ] Complex logic explained
- [ ] Breaking changes noted

## Output Format

```
Status: Approved / Needs Changes / Rejected
Risk Level: Low / Medium / High

Good Practices:
- [list positive findings]

Suggestions:
- [list improvements]

Required Changes:
- [list must-fix issues]
```

## Process
1. Read all changed files
2. Identify change type (feature, bugfix, refactor)
3. Run through checklist
4. Generate structured feedback
5. Suggest specific improvements with code examples
