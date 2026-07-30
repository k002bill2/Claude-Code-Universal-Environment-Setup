---
# 출처: docs/Claude code system setup/Agent Skills 예시 모음.md
name: code-reviewer
description: Comprehensive code review for quality, security, and maintainability. Use when reviewing pull requests, code changes, or when code quality checks are needed.
---

# Code Review Skill

## Purpose
Perform thorough code reviews focusing on:
- Code quality and readability
- Security vulnerabilities
- Performance optimization
- Test coverage
- Documentation completeness

## Review Checklist

### 1. Code Quality
- [ ] Clear and descriptive variable names
- [ ] Functions are single-purpose and small
- [ ] No code duplication (DRY principle)
- [ ] Consistent coding style
- [ ] Proper abstraction levels

### 2. Security
- [ ] Input validation present
- [ ] No SQL injection vulnerabilities
- [ ] Proper authentication/authorization
- [ ] Sensitive data encrypted
- [ ] No hardcoded secrets

### 3. Performance
- [ ] Efficient algorithms (O(n) complexity analysis)
- [ ] Database queries optimized
- [ ] Caching implemented where appropriate
- [ ] No memory leaks
- [ ] Async operations handled properly

### 4. Testing
- [ ] Unit tests present (>80% coverage)
- [ ] Edge cases covered
- [ ] Integration tests for APIs
- [ ] Error scenarios tested
- [ ] Mocks/stubs used appropriately

### 5. Documentation
- [ ] JSDoc/docstrings for public methods
- [ ] README updated if needed
- [ ] Complex logic explained
- [ ] API changes documented
- [ ] Changelog updated

## Review Process

```python
def perform_code_review(changes):
    issues = {
        'critical': [],
        'warning': [],
        'suggestion': []
    }

    # Step 1: Analyze changes
    for file in changes:
        check_security(file, issues)
        check_performance(file, issues)
        check_style(file, issues)
        check_tests(file, issues)

    # Step 2: Generate report
    return format_review_report(issues)
```

## Output Format

### Review Summary
- **Status**: Approved / Needs Changes / Rejected
- **Risk Level**: Low / Medium / High
- **Test Coverage**: XX%

### Detailed Feedback
```
🟢 **Good Practices**:
- Well-structured component architecture
- Comprehensive error handling

🟡 **Suggestions**:
- Consider extracting magic numbers to constants
- Add retry logic for network requests

🔴 **Required Changes**:
- Fix SQL injection vulnerability in line 45
- Add input validation for user data
```

## Resources
- references/security-checklist.md
- references/performance-tips.md

## Best Practices
1. Run before every PR
2. Address all critical issues
3. Consider suggestions for improvement
4. Document decisions for ignored warnings
