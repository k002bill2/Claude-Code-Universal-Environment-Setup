# Git Feature Branch Template

Feature 브랜치 워크플로우 템플릿입니다.

## 템플릿 정의

```yaml
git_workflow:
  type: feature
  branch_name: "{{branch_name}}"
  base_branch: "{{base_branch | develop}}"

  naming:
    pattern: "feature/{{ticket_id}}-{{description}}"
    # 예: feature/PROJ-123-user-authentication

  steps:
    - create_branch
    - work
    - commit
    - push
    - create_pr

  pr_config:
    title: "{{pr_title}}"
    template: "{{pr_template | .github/PULL_REQUEST_TEMPLATE.md}}"
    labels: [{{labels}}]
    reviewers: [{{reviewers}}]
    draft: {{draft | false}}
```

## 사용 예시

### 1. 기본 Feature 브랜치

```yaml
git_workflow:
  type: feature
  branch_name: "feature/user-login"
  base_branch: "develop"

  steps:
    - create_branch:
        from: develop
        name: "feature/user-login"

    - work:
        description: "사용자 로그인 기능 구현"

    - commit:
        message: "feat: implement user login functionality"
        files:
          - "src/auth/*"
          - "src/components/Login/*"

    - push:
        set_upstream: true

    - create_pr:
        base: develop
        title: "feat: 사용자 로그인 기능"
        body: |
          ## 변경 사항
          - 로그인 폼 UI 구현
          - 인증 로직 연동
          - 세션 관리

          ## 테스트
          - [x] 유닛 테스트 통과
          - [x] E2E 테스트 통과
        labels: ["feature", "auth"]
        reviewers: ["@frontend-team"]
```

### 2. 티켓 기반 Feature 브랜치

```yaml
git_workflow:
  type: feature
  ticket_id: "PROJ-456"

  steps:
    - create_branch:
        from: develop
        name: "feature/PROJ-456-shopping-cart"

    - work

    - commit:
        message: "feat(cart): implement shopping cart"
        reference: "PROJ-456"

    - push

    - create_pr:
        base: develop
        title: "[PROJ-456] 장바구니 기능"
        body_from_template: true
        auto_link_issues: true
```

### 3. 협업 Feature 브랜치

```yaml
git_workflow:
  type: feature
  branch_name: "feature/checkout-redesign"
  collaboration: true

  steps:
    - create_branch:
        from: develop

    - work

    - commit:
        message: "feat: checkout step 1"
        co_authors:
          - "Alice <alice@example.com>"
          - "Bob <bob@example.com>"

    - push

    - create_pr:
        base: develop
        title: "feat: 체크아웃 리디자인"
        draft: true  # WIP
        labels: ["feature", "wip"]
        assignees: ["alice", "bob"]
```

## CLI 명령어

### 브랜치 생성

```bash
# 기본 생성
"feature/user-settings 브랜치 만들어줘"

# 티켓 기반
"PROJ-789 이슈로 feature 브랜치 만들어줘"

# 베이스 브랜치 지정
"main에서 feature/hotfix 브랜치 만들어줘"
```

### 커밋

```bash
# Conventional Commit
"feat: 사용자 설정 페이지 추가"로 커밋해줘

# 여러 파일
"src/settings 폴더 변경사항 커밋해줘"
```

### PR 생성

```bash
# 기본 PR
"develop으로 PR 생성해줘"

# 상세 옵션
"PR 생성해줘
  - 제목: 사용자 설정 페이지
  - 리뷰어: alice, bob
  - 라벨: feature, frontend"
```

## 전체 워크플로우

```yaml
feature_workflow:
  name: "feature-complete"

  # 1. 시작
  start:
    - git fetch origin
    - git checkout {{base_branch}}
    - git pull origin {{base_branch}}
    - git checkout -b {{branch_name}}

  # 2. 개발
  develop:
    loop:
      - work
      - git add {{files}}
      - git commit -m "{{message}}"
      - git push origin {{branch_name}}

  # 3. 완료
  finish:
    - create_pr
    - request_review
    - wait_for_approval
    - merge
    - delete_branch
```

## 커밋 컨벤션

### Conventional Commits

```yaml
commit_convention:
  format: "<type>(<scope>): <description>"

  types:
    - feat: 새 기능
    - fix: 버그 수정
    - docs: 문서 변경
    - style: 포맷팅, 세미콜론 등
    - refactor: 리팩토링
    - test: 테스트 추가
    - chore: 빌드, 설정 변경

  examples:
    - "feat(auth): add social login"
    - "fix(cart): resolve quantity update bug"
    - "docs(readme): update installation guide"
```

### Co-Author 추가

```yaml
commit:
  message: "feat: implement feature"
  co_authors:
    - "Name <email@example.com>"

  # 결과:
  # feat: implement feature
  #
  # Co-authored-by: Name <email@example.com>
```

## 브랜치 보호 규칙

```yaml
branch_protection:
  pattern: "feature/*"

  rules:
    require_pull_request: true
    required_reviewers: 1
    require_status_checks:
      - lint
      - test
      - build
    require_up_to_date: true
```

## 자동화 트리거

```yaml
automation:
  on_branch_create:
    - notify_slack: "새 feature 브랜치: {{branch_name}}"

  on_push:
    - run_ci: true

  on_pr_create:
    - auto_assign_reviewers: true
    - add_labels_by_files: true
    - run_pr_checks: true

  on_pr_merge:
    - delete_branch: true
    - notify_slack: "Feature 머지됨: {{pr_title}}"
```

## 체크리스트

### 시작 전

- [ ] develop 브랜치 최신화
- [ ] 티켓/이슈 확인
- [ ] 브랜치명 컨벤션 확인

### 완료 전

- [ ] 테스트 통과
- [ ] 코드 리뷰 완료
- [ ] 컨플릭트 해결
- [ ] 커밋 메시지 정리 (squash)
