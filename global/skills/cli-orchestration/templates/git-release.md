# Git Release Template

릴리스 워크플로우 템플릿입니다.

## 템플릿 정의

```yaml
release:
  version: "{{version}}"
  strategy: "{{strategy | github-flow}}"

  versioning:
    scheme: "semver"
    bump: "{{bump_type}}"  # major, minor, patch

  steps:
    - prepare
    - version_bump
    - changelog
    - test
    - tag
    - release
    - deploy
```

## 사용 예시

### 1. 마이너 릴리스

```yaml
release:
  version: "2.1.0"
  strategy: github-flow

  steps:
    # 릴리스 브랜치 생성
    - create_branch:
        from: main
        name: "release/2.1.0"

    # 버전 범프
    - version_bump:
        files:
          - package.json
          - package-lock.json
        version: "2.1.0"

    # Changelog 업데이트
    - update_changelog:
        file: CHANGELOG.md
        version: "2.1.0"
        date: "{{today}}"

    # 커밋
    - commit:
        message: "chore(release): prepare 2.1.0"

    # 테스트
    - run_tests:
        commands:
          - npm run lint
          - npm run test
          - npm run build

    # 푸시 및 PR
    - push
    - create_pr:
        base: main
        title: "Release 2.1.0"
        labels: ["release"]

    # 머지 후
    - wait_for_merge

    # 태그 생성
    - create_tag:
        name: "v2.1.0"
        message: "Release version 2.1.0"

    # GitHub Release
    - create_github_release:
        tag: "v2.1.0"
        title: "v2.1.0"
        body_from: CHANGELOG.md
        draft: false

    # 배포
    - deploy:
        environment: production
```

### 2. 패치 릴리스 (Hotfix)

```yaml
release:
  type: hotfix
  strategy: git-flow

  steps:
    # main에서 hotfix 브랜치
    - create_branch:
        from: main
        name: "hotfix/{{issue_id}}"

    # 버그 수정
    - work:
        description: "긴급 버그 수정"

    # 패치 버전 범프
    - version_bump:
        bump: patch  # 2.1.0 → 2.1.1

    # 빠른 테스트
    - run_tests:
        only: affected

    # 커밋
    - commit:
        message: "fix: critical bug in payment"

    # main에 머지
    - merge:
        from: "hotfix/{{issue_id}}"
        to: main
        strategy: merge

    # 태그
    - create_tag:
        name: "v{{new_version}}"

    # develop에도 머지
    - merge:
        to: develop

    # 브랜치 삭제
    - delete_branch: "hotfix/{{issue_id}}"

    # 즉시 배포
    - deploy:
        environment: production
        skip_staging: true
```

### 3. 메이저 릴리스

```yaml
release:
  version: "3.0.0"
  type: major
  strategy: git-flow

  pre_release:
    # RC 빌드
    - create_branch:
        from: develop
        name: "release/3.0.0-rc.1"

    - version_bump:
        version: "3.0.0-rc.1"

    - deploy:
        environment: staging

    - test:
        suite: full
        include_manual: true

  release:
    - merge:
        from: "release/3.0.0-rc.1"
        to: main

    - version_bump:
        version: "3.0.0"

    - create_tag: "v3.0.0"

    - create_github_release:
        tag: "v3.0.0"
        title: "v3.0.0 - Major Release"
        prerelease: false
        highlights:
          - "Breaking changes"
          - "New features"
          - "Migration guide"

    - merge:
        from: main
        to: develop
```

## CLI 명령어

### 릴리스 준비

```bash
# 마이너 버전
"v2.1.0 릴리스 준비해줘"

# 패치 버전 (자동)
"패치 릴리스 해줘"

# 메이저 버전
"v3.0.0 메이저 릴리스 준비해줘"
```

### 릴리스 실행

```bash
# 전체 파이프라인
"릴리스 실행해줘"

# 특정 단계만
"태그만 생성해줘"
"GitHub Release 만들어줘"
```

### 롤백

```bash
# 이전 버전으로
"v2.0.0으로 롤백해줘"

# 직전 버전
"마지막 릴리스 롤백해줘"
```

## Changelog 템플릿

### 자동 생성 형식

```markdown
# Changelog

## [2.1.0](https://github.com/org/repo/compare/v2.0.0...v2.1.0) (2024-01-15)

### Features

* **auth:** add social login support ([#123](https://github.com/org/repo/pull/123))
* **checkout:** new payment flow ([#125](https://github.com/org/repo/pull/125))

### Bug Fixes

* **cart:** fix quantity update ([#124](https://github.com/org/repo/pull/124))

### Performance Improvements

* **api:** improve response caching ([#126](https://github.com/org/repo/pull/126))
```

### 커스텀 섹션

```yaml
changelog:
  sections:
    - type: "BREAKING CHANGE"
      title: "BREAKING CHANGES"
    - type: "feat"
      title: "Features"
    - type: "fix"
      title: "Bug Fixes"
    - type: "perf"
      title: "Performance"
    - type: "docs"
      title: "Documentation"
```

## 버전 관리

### Semantic Versioning

```yaml
versioning:
  current: "2.0.5"

  bump_rules:
    major:
      # BREAKING CHANGE가 있으면
      triggers: ["BREAKING CHANGE"]
      result: "3.0.0"

    minor:
      # feat 커밋이 있으면
      triggers: ["feat"]
      result: "2.1.0"

    patch:
      # fix, perf 커밋이 있으면
      triggers: ["fix", "perf"]
      result: "2.0.6"
```

### 자동 버전 결정

```bash
# 커밋 분석으로 자동 결정
"다음 릴리스 버전 뭐야?"

# 결과 예시:
# 커밋 분석 결과:
# - feat: 3개
# - fix: 2개
# - BREAKING CHANGE: 0개
# 추천 버전: 2.1.0 (minor)
```

## 배포 연동

### 스테이징 → 프로덕션

```yaml
deploy:
  strategy: blue-green

  staging:
    trigger: on_pr_merge
    auto: true
    health_check:
      url: "https://staging.example.com/health"
      timeout: 60000

  production:
    trigger: on_tag
    auto: false  # 수동 승인
    health_check:
      url: "https://example.com/health"
      timeout: 60000
    rollback:
      auto: true
      threshold:
        error_rate: 5%
```

## 알림 설정

```yaml
notifications:
  on_release:
    slack:
      channel: "#releases"
      message: |
        :rocket: *{{repo}} {{version}} Released!*
        {{changelog_highlights}}
        <{{release_url}}|View Release>

    email:
      to: ["team@example.com"]
      subject: "[Release] {{repo}} {{version}}"
```

## 체크리스트

### 릴리스 전

- [ ] 모든 기능 PR 머지됨
- [ ] 테스트 100% 통과
- [ ] CHANGELOG 업데이트됨
- [ ] 마이그레이션 가이드 작성 (메이저)

### 릴리스 후

- [ ] 태그 생성됨
- [ ] GitHub Release 발행됨
- [ ] 프로덕션 배포 완료
- [ ] 모니터링 확인
- [ ] 릴리스 노트 공유됨
