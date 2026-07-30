---
tags:
  - claude
  - setup
---

# Agent Skills 예시 모음
#claude-code #skills #examples

> 최종 업데이트: 2026-07-15
> Claude Code: v2.1.210 | 설정: .claude/settings.json
> Models: Opus 4.8 / Fable 5 / Sonnet 5 / Haiku 4.5

## 📌 개요
Claude Code Agent Skills의 실제 예시들입니다. 각 Skill은 특정 작업에 특화되어 있으며, 필요에 따라 자동으로 로드됩니다.

> ※ 2026-06-16 갱신: description 기반 자동 로드 외에 **Skill 도구로 명시 호출**도 가능합니다(예: `Skill(skill="code-reviewer")`). 새 스킬은 **skill-creator 스킬**로 생성하고, 빌트인 스킬과 플러그인 스코프 스킬(`ecc:*` 네임스페이스, 예: `ecc:code-review`)이 함께 공존합니다.

### 스킬 캐릭터 버짓 (v2.1.210)
- 스킬 콘텐츠는 컨텍스트 윈도우의 **약 2%**까지 자동 스케일링
- 1M 컨텍스트 (Opus 4.8/Sonnet 5) 기준 약 20K 토큰
- SKILL.md 메인 파일은 500줄 이하 권장
- 추가 내용은 번들 리소스(references/, scripts/, assets/)로 분리

### 번들 리소스 구조
```
.claude/skills/[skill-name]/
├── SKILL.md                # 메인 스킬 파일 (< 500줄)
├── scripts/                # 실행 가능한 스크립트
│   └── check.sh
├── references/             # 참고 문서 (Progressive Disclosure)
│   ├── patterns.md
│   └── checklist.md
└── assets/                 # 정적 리소스
    └── templates/
```

---

## 🔍 Code Reviewer Skill

### 파일 위치
`.claude/skills/code-reviewer/SKILL.md`

### 전체 코드
```markdown
---
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

\`\`\`python
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
\`\`\`

## Output Format

### Review Summary
- **Status**: Approved / Needs Changes / Rejected
- **Risk Level**: Low / Medium / High
- **Test Coverage**: XX%

### Detailed Feedback
\`\`\`
🟢 **Good Practices**:
- Well-structured component architecture
- Comprehensive error handling

🟡 **Suggestions**:
- Consider extracting magic numbers to constants
- Add retry logic for network requests

🔴 **Required Changes**:
- Fix SQL injection vulnerability in line 45
- Add input validation for user data
\`\`\`

## Resources
- references/security-checklist.md
- references/performance-tips.md

## Best Practices
1. Run before every PR
2. Address all critical issues
3. Consider suggestions for improvement
4. Document decisions for ignored warnings
```

---

## 📊 Excel Processor Skill

### 파일 위치
`.claude/skills/excel-processor/SKILL.md`

### 전체 코드
```markdown
---
name: excel-processor
description: Process Excel files with formulas, pivot tables, and charts. Use for spreadsheet analysis, data transformation, or report generation.
---

# Excel Processing Skill

## Capabilities
- Read/write Excel files preserving formulas
- Create pivot tables and charts
- Data validation and cleaning
- Multi-sheet operations
- Conditional formatting
- VLOOKUP/HLOOKUP operations

## Dependencies
\`\`\`python
import pandas as pd
import openpyxl
from openpyxl.chart import BarChart, LineChart, Reference
from openpyxl.styles import PatternFill, Font, Alignment
from openpyxl.utils.dataframe import dataframe_to_rows
import numpy as np
\`\`\`

## Core Functions

### 1. Read Excel with Formulas
\`\`\`python
def read_excel_with_formulas(filepath):
    workbook = openpyxl.load_workbook(filepath, data_only=False)
    sheets_data = {}
    for sheet_name in workbook.sheetnames:
        sheet = workbook[sheet_name]
        data = []
        for row in sheet.iter_rows():
            row_data = []
            for cell in row:
                if cell.value:
                    row_data.append({
                        'value': cell.value,
                        'formula': cell.formula if hasattr(cell, 'formula') else None,
                        'format': cell.number_format
                    })
                else:
                    row_data.append(None)
            data.append(row_data)
        sheets_data[sheet_name] = data
    return sheets_data, workbook
\`\`\`

### 2. Create Pivot Table
\`\`\`python
def create_pivot_table(df, index, columns, values, aggfunc='sum'):
    pivot = pd.pivot_table(
        df, index=index, columns=columns,
        values=values, aggfunc=aggfunc, fill_value=0
    )
    return pivot
\`\`\`

### 3. Data Validation
\`\`\`python
def validate_and_clean_data(df):
    df = df.drop_duplicates()
    numeric_columns = df.select_dtypes(include=[np.number]).columns
    df[numeric_columns] = df[numeric_columns].fillna(0)
    for col in numeric_columns:
        mean = df[col].mean()
        std = df[col].std()
        df = df[(df[col] > mean - 3*std) & (df[col] < mean + 3*std)]
    return df
\`\`\`

## Usage Examples
See references/excel-examples.md for complete usage patterns.
```

---

## 🧪 Test Runner Skill

### 파일 위치
`.claude/skills/test-runner/SKILL.md`

### 전체 코드
```markdown
---
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
\`\`\`bash
# JavaScript/TypeScript
npm test
npm run test:coverage

# Python
pytest
pytest --cov=src --cov-report=html

# Go
go test ./...
go test -cover
\`\`\`

## Test Generation

### Unit Test Template
\`\`\`typescript
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
\`\`\`

## Coverage Analysis
\`\`\`javascript
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
\`\`\`

## Best Practices
1. Write tests before fixing bugs (TDD)
2. Keep tests simple and focused
3. Use descriptive test names
4. Maintain test independence
5. Mock external dependencies
6. Regular coverage monitoring
```

---

## 📝 Documentation Generator Skill

### 파일 위치
`.claude/skills/docs-generator/SKILL.md`

### 전체 코드
```markdown
---
name: docs-generator
description: Generate comprehensive documentation including API docs, README files, and technical guides. Use for documentation tasks.
---

# Documentation Generator Skill

## Capabilities
- API documentation generation
- README file creation
- Code documentation extraction
- Markdown formatting
- Diagram generation (Mermaid)
- Changelog management

## Documentation Types

### 1. API Documentation
See references/api-template.md

### 2. README Template
See references/readme-template.md

### 3. Architecture Diagram (Mermaid)
\`\`\`mermaid
graph TB
    Client[Client App]
    API[API Gateway]
    Auth[Auth Service]
    User[User Service]
    DB[(Database)]
    Cache[(Redis Cache)]

    Client --> API
    API --> Auth
    API --> User
    Auth --> DB
    User --> DB
    User --> Cache
\`\`\`

## Best Practices
1. Keep documentation close to code
2. Use consistent formatting
3. Include examples for everything
4. Update docs with code changes
5. Version documentation
6. Use diagrams for complex concepts
```

---

## 🔌 플러그인 기반 스킬 예시 (신규)

### 플러그인 구조
```
.claude/plugins/dev-quality/
├── plugin.json
├── skills/
│   ├── code-reviewer/
│   │   ├── SKILL.md
│   │   └── references/
│   │       └── security-checklist.md
│   └── test-runner/
│       └── SKILL.md
└── hooks/
    └── post-review.sh
```

### plugin.json
```json
{
  "name": "dev-quality",
  "version": "1.0.0",
  "description": "코드 품질 및 테스트 자동화 플러그인",
  "skills": ["skills/"],
  "hooks": {
    "PostToolUse": ["hooks/post-review.sh"]
  }
}
```

플러그인으로 패키징하면 프로젝트 간 재사용 및 팀 공유가 편리합니다.

---

## 🎯 사용 가이드

### Skill 생성 방법

1. **자동 생성 (추천)**
   ```
   "Use the skill-creator skill to help me create a skill for [작업]"
   ```

2. **수동 생성**
   ```bash
   mkdir -p .claude/skills/skill-name/references
   touch .claude/skills/skill-name/SKILL.md
   ```

3. **테스트**
   ```
   "Test the [skill-name] skill with this sample data"
   ```

### Skill 활용 팁

1. **명확한 설명**: description 필드가 핵심 (자동 로드 트리거)
2. **모듈화**: 하나의 Skill은 하나의 목적
3. **번들 리소스**: references/, scripts/, assets/로 보조 파일 구조화
4. **캐릭터 버짓**: SKILL.md는 500줄 이하, 나머지는 references로
5. **재사용성**: 팀과 공유 가능하게 설계 (플러그인으로 패키징)
6. **버전 관리**: Git으로 관리

---

*태그: #claude-code #skills #examples #automation #plugins*