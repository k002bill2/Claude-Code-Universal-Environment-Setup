# Git Branch Strategies

CLI 오케스트레이션에서 지원하는 Git 브랜치 전략입니다.

## 지원 전략

| 전략 | 복잡도 | 적합한 프로젝트 |
|------|--------|----------------|
| Git Flow | 높음 | 릴리스 주기가 긴 대규모 프로젝트 |
| GitHub Flow | 낮음 | 지속적 배포, 웹 서비스 |
| Trunk-based | 낮음 | CI/CD 고도화 팀, 작은 PR |

---

## 1. Git Flow

Vincent Driessen의 브랜칭 모델로, 릴리스 관리가 중요한 프로젝트에 적합합니다.

### 브랜치 구조

```
main (production)
  │
  └── develop (통합 브랜치)
        │
        ├── feature/xxx (기능 개발)
        ├── release/x.x.x (릴리스 준비)
        └── hotfix/xxx (긴급 수정)
```

### 브랜치 역할

| 브랜치 | 용도 | 수명 |
|--------|------|------|
| `main` | 프로덕션 코드 | 영구 |
| `develop` | 개발 통합 | 영구 |
| `feature/*` | 기능 개발 | 임시 |
| `release/*` | 릴리스 준비 | 임시 |
| `hotfix/*` | 긴급 수정 | 임시 |

### 워크플로우

#### Feature 개발

```yaml
git_workflow:
  type: feature
  strategy: git-flow
  steps:
    - create_branch:
        from: develop
        name: "feature/user-auth"
    - work  # 개발 작업
    - commit
    - push
    - create_pr:
        base: develop
        title: "feat: 사용자 인증 구현"
```

#### Release 준비

```yaml
git_workflow:
  type: release
  strategy: git-flow
  version: "1.2.0"
  steps:
    - create_branch:
        from: develop
        name: "release/1.2.0"
    - version_bump: "1.2.0"
    - commit: "chore: bump version to 1.2.0"
    - test
    - merge:
        to: [main, develop]
    - tag: "v1.2.0"
    - delete_branch
```

#### Hotfix

```yaml
git_workflow:
  type: hotfix
  strategy: git-flow
  steps:
    - create_branch:
        from: main
        name: "hotfix/critical-bug"
    - work
    - commit: "fix: critical bug in payment"
    - test
    - merge:
        to: [main, develop]
    - tag_patch  # 패치 버전 자동 증가
    - delete_branch
```

---

## 2. GitHub Flow

단순하고 지속적 배포에 적합한 전략입니다.

### 브랜치 구조

```
main (항상 배포 가능)
  │
  └── feature/xxx (모든 작업)
```

### 원칙

1. `main`은 항상 배포 가능한 상태
2. 새 작업은 `main`에서 분기
3. 작업 완료 시 PR 생성
4. 리뷰 후 `main`에 머지
5. 머지 즉시 배포

### 워크플로우

```yaml
git_workflow:
  type: feature
  strategy: github-flow
  steps:
    - create_branch:
        from: main
        name: "add-dark-mode"
    - work
    - commit
    - push
    - create_pr:
        base: main
        title: "feat: 다크 모드 추가"
        auto_merge: true  # 리뷰 승인 후 자동 머지
    - deploy  # main 머지 시 자동 배포
```

### 명명 규칙

```yaml
branch_naming:
  pattern: "<type>/<description>"
  types:
    - feature    # 기능 추가
    - fix        # 버그 수정
    - docs       # 문서 수정
    - refactor   # 리팩토링
    - test       # 테스트 추가
  examples:
    - "feature/user-profile"
    - "fix/login-timeout"
    - "docs/api-reference"
```

---

## 3. Trunk-based Development

짧은 수명의 feature 브랜치와 빈번한 머지를 특징으로 합니다.

### 브랜치 구조

```
main (trunk)
  │
  └── short-lived-branch (< 1일)
```

### 원칙

1. 브랜치 수명 최대 1-2일
2. 작은 단위의 변경
3. Feature Flag로 미완성 기능 관리
4. 빈번한 머지 (하루 여러 번)

### 워크플로우

```yaml
git_workflow:
  type: trunk-based
  steps:
    - create_branch:
        from: main
        name: "quick-fix-123"
    - work
    - commit:
        message: "fix: resolve issue #123"
        sign_off: true
    - push
    - create_pr:
        base: main
        title: "fix: resolve issue #123"
        require_review: false  # 작은 변경은 self-merge
    - squash_merge
    - delete_branch
```

### Feature Flags 연동

```yaml
git_workflow:
  type: trunk-based
  feature_flag:
    provider: "launchdarkly"  # 또는 "unleash", "custom"
  steps:
    - create_feature_flag: "new-checkout-flow"
    - create_branch: "checkout-v2"
    - work
    - commit
    - push
    - create_pr:
        base: main
        description: |
          Feature flag: `new-checkout-flow`
          Rollout: 10% → 50% → 100%
```

---

## 전략 선택 가이드

### 결정 트리

```
릴리스 주기가 긴가? (월별 이상)
  └─ Yes → Git Flow
  └─ No ↓

CI/CD가 완전 자동화되어 있는가?
  └─ Yes → Trunk-based
  └─ No → GitHub Flow
```

### 비교표

| 특성 | Git Flow | GitHub Flow | Trunk-based |
|------|----------|-------------|-------------|
| 복잡도 | 높음 | 낮음 | 낮음 |
| 릴리스 주기 | 긴 주기 | 지속적 | 지속적 |
| 브랜치 수명 | 길 수 있음 | 중간 | 짧음 (< 1일) |
| 배포 빈도 | 릴리스마다 | PR 머지마다 | 커밋마다 |
| 롤백 | 릴리스 롤백 | 리버트 PR | Feature Flag |
| 팀 규모 | 대규모 | 중규모 | 소규모~중규모 |

---

## CLI 오케스트레이션 통합

### 전략 설정

```yaml
# .claude/cli-orchestration.yaml
git_workflow:
  default_strategy: github-flow

  branch_protection:
    main:
      require_review: true
      require_ci: true
    develop:
      require_review: false
      require_ci: true
```

### 명령어 예시

```bash
# Feature 브랜치 생성 및 PR
"feature/login 브랜치 만들고 작업 완료 후 PR 생성해줘"

# 릴리스 (Git Flow)
"v2.0.0 릴리스 준비해줘 (Git Flow)"

# 빠른 수정 (Trunk-based)
"이슈 #123 빠르게 수정하고 머지해줘"
```

### 자동화 트리거

```yaml
# PR 생성 시 자동 실행
on_pr_create:
  - lint
  - typecheck
  - test
  - build

# main 머지 시 자동 실행
on_merge_to_main:
  - deploy_staging
  - smoke_test
  - deploy_production
```
