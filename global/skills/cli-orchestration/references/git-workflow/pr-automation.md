# PR Automation

CLI 오케스트레이션을 통한 Pull Request 자동화 가이드입니다.

## 개요

PR 자동화는 다음을 지원합니다:

1. **PR 생성**: 브랜치에서 자동 PR 생성
2. **PR 템플릿**: 일관된 PR 설명 작성
3. **자동 라벨링**: 변경 파일 기반 라벨 자동 부여
4. **리뷰어 자동 할당**: CODEOWNERS 기반 할당
5. **체크 자동화**: CI 체크 및 머지 조건 검증

## PR 생성

### 기본 생성

```yaml
create_pr:
  base: main
  head: feature/new-login
  title: "feat: 새로운 로그인 화면 구현"
  body: |
    ## 변경 사항
    - 로그인 폼 UI 구현
    - 인증 로직 연동

    ## 테스트
    - [x] 유닛 테스트 통과
    - [x] E2E 테스트 통과
```

### gh CLI 사용

```bash
gh pr create \
  --base main \
  --head feature/new-login \
  --title "feat: 새로운 로그인 화면 구현" \
  --body "$(cat PR_TEMPLATE.md)" \
  --label "enhancement" \
  --assignee @me
```

### 자동 생성 워크플로우

```yaml
git_workflow:
  type: feature
  auto_pr:
    enabled: true
    template: ".github/PULL_REQUEST_TEMPLATE.md"

  steps:
    - create_branch: "feature/user-auth"
    - work
    - commit
    - push
    - create_pr:
        auto_fill: true       # 커밋에서 제목/본문 추출
        draft: false          # 바로 리뷰 가능
        labels: ["feature"]
        reviewers: ["team-lead"]
```

## PR 템플릿

### 기본 템플릿 (.github/PULL_REQUEST_TEMPLATE.md)

```markdown
## Summary
<!-- 변경 사항 요약 (1-2문장) -->

## Changes
<!-- 상세 변경 목록 -->
-

## Type
- [ ] Feature
- [ ] Bug fix
- [ ] Refactor
- [ ] Documentation
- [ ] Test

## Testing
<!-- 테스트 방법 및 결과 -->
- [ ] Unit tests passed
- [ ] E2E tests passed
- [ ] Manual testing done

## Screenshots
<!-- UI 변경 시 스크린샷 첨부 -->

## Checklist
- [ ] Code follows project style guidelines
- [ ] Self-reviewed the code
- [ ] Added necessary documentation
- [ ] No console.log or debug code
```

### 타입별 템플릿 사용

```yaml
pr_templates:
  feature: ".github/PULL_REQUEST_TEMPLATE/feature.md"
  bugfix: ".github/PULL_REQUEST_TEMPLATE/bugfix.md"
  hotfix: ".github/PULL_REQUEST_TEMPLATE/hotfix.md"

create_pr:
  template_type: "feature"  # 자동 선택
```

## 자동 라벨링

### 파일 기반 라벨

```yaml
auto_labels:
  rules:
    - pattern: "src/components/**"
      labels: ["frontend", "ui"]

    - pattern: "src/api/**"
      labels: ["backend", "api"]

    - pattern: "*.test.ts"
      labels: ["test"]

    - pattern: "package.json"
      labels: ["dependencies"]

    - pattern: "docs/**"
      labels: ["documentation"]
```

### 커밋 메시지 기반 라벨

```yaml
auto_labels:
  commit_patterns:
    - pattern: "^feat:"
      labels: ["enhancement"]

    - pattern: "^fix:"
      labels: ["bug"]

    - pattern: "^BREAKING CHANGE:"
      labels: ["breaking-change"]
```

### 크기 기반 라벨

```yaml
auto_labels:
  size:
    XS: { lines: 10 }     # 0-10줄
    S: { lines: 50 }      # 11-50줄
    M: { lines: 200 }     # 51-200줄
    L: { lines: 500 }     # 201-500줄
    XL: { lines: null }   # 500줄 이상
```

## 리뷰어 자동 할당

### CODEOWNERS 연동

```yaml
# .github/CODEOWNERS
/src/components/    @frontend-team
/src/api/           @backend-team
/src/auth/          @security-team
*.test.ts           @qa-team
```

### 자동 할당 규칙

```yaml
auto_assign:
  enabled: true

  rules:
    # 팀 기반 할당
    - files: ["src/frontend/**"]
      reviewers:
        teams: ["frontend-team"]
        count: 2  # 팀에서 2명 무작위 선택

    # 개인 기반 할당
    - files: ["src/api/**"]
      reviewers:
        users: ["alice", "bob", "charlie"]
        count: 1

    # 필수 리뷰어
    - files: ["src/security/**"]
      reviewers:
        users: ["security-lead"]
        required: true  # 반드시 승인 필요
```

### 부하 분산

```yaml
auto_assign:
  load_balancing:
    enabled: true
    algorithm: "round-robin"  # 또는 "least-reviews"

  exclude:
    users_on_vacation: true
    pr_author: true  # 작성자 제외
```

## 머지 자동화

### 머지 조건

```yaml
auto_merge:
  enabled: true

  conditions:
    - ci_passed: true         # CI 통과
    - approved_count: 1       # 최소 1명 승인
    - no_changes_requested: true
    - no_conflicts: true
    - labels_present: ["ready-to-merge"]
    - labels_absent: ["do-not-merge", "wip"]
```

### 머지 전략

```yaml
merge_strategy:
  default: "squash"  # squash, merge, rebase

  rules:
    - branch_pattern: "feature/*"
      strategy: "squash"
      delete_branch: true

    - branch_pattern: "release/*"
      strategy: "merge"
      delete_branch: true

    - branch_pattern: "hotfix/*"
      strategy: "merge"
      delete_branch: true
```

### 자동 머지 워크플로우

```yaml
git_workflow:
  type: feature
  auto_merge:
    enabled: true
    wait_for_checks: true

  steps:
    - create_pr
    - wait_for_review     # 리뷰 대기
    - wait_for_checks     # CI 대기
    - auto_merge          # 조건 충족 시 자동 머지
    - delete_branch
```

## CI 체크 연동

### 필수 체크 정의

```yaml
required_checks:
  - lint
  - typecheck
  - test-unit
  - test-e2e
  - build
  - security-scan
```

### 체크 상태 모니터링

```yaml
check_monitoring:
  poll_interval: 30000  # 30초
  timeout: 1800000      # 30분

  on_failure:
    - notify: "slack"
    - comment: "CI 체크 실패: ${failed_check}"

  on_success:
    - label_add: ["ci-passed"]
    - auto_merge_check: true
```

## CLI 명령어

### PR 생성

```bash
# 기본 PR 생성
"feature/login에서 main으로 PR 생성해줘"

# 상세 옵션
"feature/login PR 생성해줘
  - 제목: 새 로그인 구현
  - 리뷰어: alice, bob
  - 라벨: enhancement, frontend"
```

### PR 상태 확인

```bash
# PR 목록
"열려있는 PR 보여줘"

# 특정 PR 상태
"PR #123 체크 상태 확인해줘"
```

### PR 머지

```bash
# 수동 머지
"PR #123 squash 머지해줘"

# 자동 머지 활성화
"PR #123 자동 머지 켜줘"
```

## 완전한 워크플로우 예시

```yaml
git_workflow:
  name: "feature-to-production"

  steps:
    # 1. 브랜치 생성
    - create_branch:
        from: main
        name: "feature/checkout-v2"

    # 2. 개발 작업
    - work

    # 3. 커밋 및 푸시
    - commit:
        message: "feat: 새 체크아웃 플로우 구현"
        sign: true
    - push

    # 4. PR 생성
    - create_pr:
        base: main
        title: "feat: 새 체크아웃 플로우"
        template: "feature"
        labels: ["enhancement", "checkout"]
        reviewers:
          teams: ["frontend-team"]
          count: 2
        draft: false

    # 5. CI 대기
    - wait_for_checks:
        required: [lint, test, build]
        timeout: 1800000

    # 6. 리뷰 대기
    - wait_for_review:
        min_approvals: 1

    # 7. 머지
    - merge:
        strategy: squash
        delete_branch: true

    # 8. 배포 트리거
    - trigger_deployment:
        environment: staging
```
