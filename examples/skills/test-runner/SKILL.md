---
# 출처: docs/Claude code system setup/Agent Skills 예시 모음.md
name: test-runner
description: Automated test execution, coverage analysis, and test generation. Use for running tests, fixing failures, and improving coverage.
---

# Test Runner Skill

## Capabilities
- Execute unit tests
- Run integration tests
- Generate test coverage reports
- Create missing tests
- Fix failing tests
- Performance testing

## Supported Frameworks
- JavaScript: Jest, Vitest, Mocha
- Python: pytest, unittest
- Go: testing package
- Java: JUnit, TestNG

## Test Execution

### Run All Tests
```bash
# JavaScript/TypeScript
npm test
npm run test:coverage

# Python
pytest
pytest --cov=src --cov-report=html

# Go
go test ./...
go test -cover
```

## Test Generation

### Unit Test Template
```typescript
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { UserService } from '../src/services/UserService';

describe('UserService', () => {
  let service: UserService;
  let mockRepository: any;

  beforeEach(() => {
    mockRepository = {
      findById: vi.fn(),
      save: vi.fn(),
      delete: vi.fn()
    };
    service = new UserService(mockRepository);
  });

  describe('getUser', () => {
    it('should return user when found', async () => {
      const userId = '123';
      const expectedUser = { id: userId, name: 'John' };
      mockRepository.findById.mockResolvedValue(expectedUser);

      const result = await service.getUser(userId);

      expect(result).toEqual(expectedUser);
      expect(mockRepository.findById).toHaveBeenCalledWith(userId);
    });

    it('should throw error when user not found', async () => {
      mockRepository.findById.mockResolvedValue(null);
      await expect(service.getUser('999')).rejects.toThrow('User not found');
    });
  });
});
```

## Coverage Analysis
```javascript
// vitest.config.ts
export default defineConfig({
  test: {
    coverage: {
      provider: 'v8',
      thresholds: {
        branches: 80,
        functions: 80,
        lines: 80,
        statements: 80
      }
    }
  }
});
```

## Best Practices
1. Write tests before fixing bugs (TDD)
2. Keep tests simple and focused
3. Use descriptive test names
4. Maintain test independence
5. Mock external dependencies
6. Regular coverage monitoring
