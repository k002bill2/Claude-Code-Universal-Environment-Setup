---
name: verify-implementation
description: 프로젝트의 모든 verify 스킬을 순차 실행하여 통합 검증 보고서를 생성합니다. 기능 구현 후, PR 전, 코드 리뷰 시 사용.
disable-model-invocation: true
argument-hint: "[verify 스킬 이름]"
---

# 구현 검증

## 목적

프로젝트에 등록된 모든 `verify-*` 스킬을 순차적으로 실행하여 통합 검증을 수행합니다:

- 각 스킬의 Workflow에 정의된 검사를 실행
- 각 스킬의 Exceptions를 참조하여 false positive 방지
- 발견된 이슈에 대해 수정 방법을 제시
- 사용자 승인 후 수정 적용 및 재검증

## 실행 시점

- 새로운 기능을 구현한 후
- Pull Request를 생성하기 전
- 코드 리뷰 중
- 코드베이스 규칙 준수 여부를 감사할 때

## 실행 대상 스킬

이 스킬이 순차 실행하는 검증 스킬 목록입니다.
프로젝트의 `.claude/skills/` 에서 `verify-*` 패턴의 스킬을 자동 탐지합니다.

## 워크플로우

### Step 1: 소개

`.claude/skills/verify-*/SKILL.md` 패턴으로 검증 스킬을 탐지합니다.

**등록된 스킬이 0개인 경우**: 안내 메시지를 표시하고 종료합니다.

### Step 2: 순차 실행

각 스킬에 대해:
1. 스킬 SKILL.md를 읽고 Workflow, Exceptions, Related Files 파싱
2. Workflow에 정의된 검사를 순서대로 실행
3. Exceptions에 해당하는 패턴은 면제 처리
4. FAIL인 경우 파일 경로, 문제, 수정 권장 사항 기록

### Step 3: 통합 보고서

```markdown
## 구현 검증 보고서

### 요약
| 검증 스킬 | 상태 | 이슈 수 |
|-----------|------|---------|
| verify-<name> | PASS / X개 이슈 | N |
```

### Step 4: 사용자 액션 확인

이슈 발견 시 옵션 제시:
1. **전체 수정** - 모든 권장 수정사항 자동 적용
2. **개별 수정** - 하나씩 검토 후 적용
3. **건너뛰기** - 변경 없이 종료

### Step 5: 수정 적용

사용자 선택에 따라 수정을 적용합니다.

### Step 6: 수정 후 재검증

이슈가 있었던 스킬만 재실행하여 Before/After 비교합니다.

## 예외사항

1. **등록된 스킬이 없는 프로젝트** — 오류가 아닌 안내 메시지를 표시하고 종료
2. **스킬의 자체적 예외** — 각 verify 스킬의 Exceptions 섹션에 정의된 패턴은 이슈로 보고하지 않음
3. **verify-implementation 자체** — 실행 대상에 자기 자신을 포함하지 않음
