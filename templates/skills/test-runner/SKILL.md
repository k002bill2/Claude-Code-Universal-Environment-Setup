---
name: test-runner
description: Automated test execution, coverage analysis, and test generation. Use for running tests, fixing failures, and improving coverage.
---

# Test Runner Skill

## Capabilities
- Execute unit/integration/e2e tests
- Generate coverage reports
- Create missing tests
- Fix failing tests
- Identify coverage gaps

## Test Execution

### Run Tests
```bash
# JavaScript/TypeScript
npm test                          # All tests
npm test -- --coverage            # With coverage
npm test -- --watch               # Watch mode
npm test -- --testPathPattern=X   # Specific file

# Python
pytest                            # All tests
pytest --cov=src                  # With coverage
pytest -v --tb=short              # Verbose with short traceback
pytest tests/test_X.py::test_Y   # Specific test
```

## Test Generation Template

### Unit Test (TypeScript/Vitest)
```typescript
import { describe, it, expect, vi, beforeEach } from 'vitest';

describe('ModuleName', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  describe('functionName', () => {
    it('should handle normal case', () => {
      // Arrange
      const input = {};
      // Act
      const result = functionName(input);
      // Assert
      expect(result).toEqual(expected);
    });

    it('should handle edge case', () => {
      expect(() => functionName(null)).toThrow();
    });
  });
});
```

### Integration Test (Python/pytest)
```python
import pytest
from httpx import AsyncClient

@pytest.mark.asyncio
async def test_endpoint(client: AsyncClient):
    response = await client.get("/api/resource")
    assert response.status_code == 200
    assert "data" in response.json()
```

## Coverage Analysis
1. Run coverage report
2. Identify untested code paths
3. Prioritize by risk (business logic > utils > models)
4. Generate tests for gaps
5. Verify threshold met (>80%)

## Debugging Failures
1. Run failing test in isolation
2. Check test data setup
3. Verify mocks/stubs configuration
4. Review implementation changes
5. Update test expectations if behavior changed intentionally
