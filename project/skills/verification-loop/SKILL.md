---
name: verification-loop
description: Boris Cherny style verification feedback loop automation. Run type check, lint, test, and build verification. Use after code changes to ensure quality.
---

# Verification Loop Skill

Boris Cherny가 강조하는 **검증 피드백 루프**를 자동화하는 스킬입니다.

## 핵심 원칙

> "검증 피드백 루프는 Claude Code 워크플로우에서 가장 중요한 요소입니다."
> — Boris Cherny

## 검증 체크리스트

### Level 1: Quick Check (1분 이내)
```bash
# TypeScript 프로젝트
npm run type-check
# Python 프로젝트
mypy src/
```
- 타입 에러 0개 확인
- 빠른 피드백 루프

### Level 2: Standard Check (2-3분)
```bash
# TypeScript
npm run type-check && npm run lint && npm test
# Python
mypy src/ && ruff check src/ && pytest
```
- 타입 + 린트 + 테스트
- 기능 구현 완료 시

### Level 3: Full Check (5분 이상)
```bash
# TypeScript
npm run type-check && npm run lint && npm test -- --coverage && npm run build
# Python
mypy src/ && ruff check src/ && pytest --cov && python -m build
```
- 전체 검증
- PR 생성 전 필수

## 검증 기준

### TypeScript
| 기준 | 상태 |
|------|------|
| 타입 에러 0개 | 필수 |
| `any` 사용 금지 | 필수 |
| strict mode 활성화 | 필수 |

### Python
| 기준 | 상태 |
|------|------|
| mypy 에러 0개 | 필수 |
| ruff 에러 0개 | 필수 |
| 타입 힌트 필수 | 필수 |

### 테스트 커버리지
| 지표 | 목표 |
|------|------|
| Statements | ≥75% |
| Functions | ≥70% |
| Branches | ≥60% |

### 빌드
| 기준 | 상태 |
|------|------|
| 빌드 성공 | 필수 |
| 번들 크기 경고 없음 | 권장 |

## 실패 시 대응

### 우선순위
1. **타입 에러**: 즉시 수정 (블로커)
2. **테스트 실패**: 코드 또는 테스트 수정
3. **린트 에러**: `--fix` 시도
4. **커버리지 미달**: 테스트 추가

### 수정 후 재검증
```bash
# 수정 후 반드시 재검증
npm run type-check && npm test
# 또는
mypy src/ && pytest
```

## PR 리뷰 기준
- [ ] 타입 에러 없음
- [ ] 린트 에러 없음
- [ ] 모든 테스트 통과
- [ ] 커버리지 목표 충족
- [ ] 빌드 성공
