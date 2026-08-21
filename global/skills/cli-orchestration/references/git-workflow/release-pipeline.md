# Release Pipeline

CLI 오케스트레이션을 통한 릴리스 자동화 가이드입니다.

## 개요

릴리스 파이프라인은 다음 단계를 자동화합니다:

1. **버전 관리**: Semantic Versioning 기반 버전 범프
2. **Changelog 생성**: 커밋에서 자동 생성
3. **태그 생성**: Git 태그 및 GitHub Release
4. **빌드 및 배포**: 프로덕션 배포
5. **알림**: 릴리스 노트 공유

## 버전 관리

### Semantic Versioning

```
MAJOR.MINOR.PATCH
  │     │     └─ 버그 수정 (하위 호환)
  │     └─ 기능 추가 (하위 호환)
  └─ 브레이킹 체인지 (하위 비호환)
```

### 버전 범프 규칙

```yaml
version_bump:
  rules:
    - commit_pattern: "^BREAKING CHANGE:"
      bump: "major"

    - commit_pattern: "^feat:"
      bump: "minor"

    - commit_pattern: "^fix:|^perf:|^refactor:"
      bump: "patch"
```

### 수동 버전 지정

```yaml
release:
  version: "2.0.0"        # 직접 지정
  # 또는
  bump: "minor"           # 자동 계산
  # 또는
  prerelease: "beta.1"    # 2.1.0-beta.1
```

## Changelog 자동 생성

### Conventional Commits 기반

```yaml
changelog:
  format: "conventional"

  sections:
    - type: "feat"
      title: "Features"
    - type: "fix"
      title: "Bug Fixes"
    - type: "perf"
      title: "Performance"
    - type: "refactor"
      title: "Refactoring"
    - type: "docs"
      title: "Documentation"
    - type: "test"
      title: "Tests"
    - type: "chore"
      title: "Chores"
```

### 생성된 Changelog 예시

```markdown
# [2.1.0](https://github.com/org/repo/compare/v2.0.0...v2.1.0) (2024-01-15)

### Features
* **auth:** 소셜 로그인 추가 ([#123](https://github.com/org/repo/pull/123))
* **checkout:** 새로운 결제 플로우 ([#125](https://github.com/org/repo/pull/125))

### Bug Fixes
* **cart:** 수량 업데이트 오류 수정 ([#124](https://github.com/org/repo/pull/124))

### Performance
* **api:** 응답 캐싱 개선 ([#126](https://github.com/org/repo/pull/126))
```

### 커스텀 템플릿

```yaml
changelog:
  template: |
    # Release {{version}} ({{date}})

    {{#each sections}}
    ## {{title}}
    {{#each commits}}
    - {{subject}} ({{shortHash}})
    {{/each}}
    {{/each}}

    **Contributors:** {{contributors}}
```

## 릴리스 워크플로우

### Git Flow 릴리스

```yaml
release_workflow:
  strategy: git-flow

  steps:
    # 1. 릴리스 브랜치 생성
    - create_branch:
        from: develop
        name: "release/{{version}}"

    # 2. 버전 범프
    - version_bump:
        files:
          - "package.json"
          - "package-lock.json"
        version: "{{version}}"

    # 3. Changelog 업데이트
    - update_changelog:
        file: "CHANGELOG.md"
        prepend: true

    # 4. 커밋
    - commit:
        message: "chore(release): {{version}}"

    # 5. 최종 검증
    - run_checks:
        commands:
          - "npm run lint"
          - "npm run test"
          - "npm run build"

    # 6. main에 머지
    - merge:
        from: "release/{{version}}"
        to: main
        strategy: merge

    # 7. 태그 생성
    - create_tag:
        name: "v{{version}}"
        message: "Release {{version}}"

    # 8. develop에 머지
    - merge:
        from: "release/{{version}}"
        to: develop
        strategy: merge

    # 9. 브랜치 삭제
    - delete_branch: "release/{{version}}"

    # 10. GitHub Release 생성
    - create_github_release:
        tag: "v{{version}}"
        title: "v{{version}}"
        body_from: changelog
        draft: false
        prerelease: false
```

### GitHub Flow 릴리스

```yaml
release_workflow:
  strategy: github-flow

  steps:
    # 1. 버전 범프 PR
    - create_branch:
        from: main
        name: "release/{{version}}"

    - version_bump:
        files: ["package.json"]
        version: "{{version}}"

    - update_changelog

    - commit:
        message: "chore(release): prepare {{version}}"

    - push

    - create_pr:
        base: main
        title: "Release {{version}}"
        labels: ["release"]

    # 2. PR 머지 대기
    - wait_for_merge

    # 3. 태그 및 릴리스
    - create_tag: "v{{version}}"
    - create_github_release
```

## GitHub Release

### 자동 생성

```yaml
github_release:
  tag: "v{{version}}"
  name: "v{{version}}"

  body:
    from: changelog  # CHANGELOG.md에서 추출
    # 또는
    generate: true   # 커밋에서 자동 생성

  assets:
    - path: "dist/*.zip"
      name: "app-{{version}}.zip"
    - path: "dist/*.tar.gz"
      name: "app-{{version}}.tar.gz"

  draft: false
  prerelease: false
```

### gh CLI 사용

```bash
gh release create v2.1.0 \
  --title "v2.1.0" \
  --notes-file RELEASE_NOTES.md \
  dist/*.zip dist/*.tar.gz
```

## 배포 연동

### 스테이징 → 프로덕션

```yaml
release_workflow:
  deploy:
    environments:
      - name: staging
        auto: true
        checks:
          - smoke_test

      - name: production
        auto: false           # 수동 승인
        wait_time: 3600000    # 1시간 대기
        checks:
          - smoke_test
          - performance_test
```

### 롤백 전략

```yaml
release_workflow:
  rollback:
    enabled: true

    triggers:
      - error_rate: "> 5%"
      - latency_p99: "> 2000ms"

    actions:
      - notify: ["slack", "pagerduty"]
      - revert_deployment
      - create_hotfix_branch
```

## Hotfix 릴리스

### 긴급 패치

```yaml
hotfix_workflow:
  steps:
    # 1. main에서 hotfix 브랜치
    - create_branch:
        from: main
        name: "hotfix/{{issue}}"

    # 2. 수정 작업
    - work

    # 3. 버전 패치
    - version_bump:
        bump: patch

    # 4. 빠른 검증
    - run_checks:
        commands:
          - "npm run test:affected"

    # 5. main 머지 및 태그
    - merge:
        to: main
        strategy: merge

    - create_tag: "v{{version}}"

    # 6. develop에도 머지
    - merge:
        to: develop
        strategy: merge

    # 7. 즉시 배포
    - deploy:
        environment: production
        skip_staging: true
```

## 알림 설정

### Slack 알림

```yaml
notifications:
  slack:
    channel: "#releases"

    on_release:
      message: |
        :rocket: *{{repo}} v{{version}} Released!*

        {{#each highlights}}
        • {{this}}
        {{/each}}

        <{{release_url}}|View Release>
```

### 이메일 알림

```yaml
notifications:
  email:
    recipients: ["team@example.com"]

    on_release:
      subject: "[Release] {{repo}} v{{version}}"
      template: "release-announcement"
```

## CLI 명령어

### 릴리스 준비

```bash
# 마이너 버전 릴리스
"v2.1.0 릴리스 준비해줘"

# 패치 버전 릴리스
"패치 릴리스 해줘"  # 자동으로 다음 패치 버전

# 프리릴리스
"v3.0.0-beta.1 릴리스 해줘"
```

### 릴리스 실행

```bash
# 전체 파이프라인
"release/2.1.0 브랜치로 릴리스 실행해줘"

# 개별 단계
"v2.1.0 태그 생성해줘"
"GitHub Release 만들어줘"
```

## 완전한 릴리스 예시

```yaml
release:
  name: "v2.1.0-release"
  version: "2.1.0"
  strategy: git-flow

  pre_checks:
    - branch: develop
    - clean_working_tree: true
    - no_pending_prs: true

  steps:
    # 준비
    - create_release_branch
    - version_bump
    - update_changelog
    - commit_changes

    # 검증
    - run_lint
    - run_typecheck
    - run_tests
    - run_build

    # 머지
    - merge_to_main
    - create_tag
    - merge_to_develop
    - delete_release_branch

    # 배포
    - deploy_staging
    - run_smoke_tests
    - wait_for_approval      # 수동 승인
    - deploy_production

    # 완료
    - create_github_release
    - notify_slack
    - send_release_email

  rollback:
    on_failure:
      - revert_tag
      - revert_deploy
      - notify_team
```
