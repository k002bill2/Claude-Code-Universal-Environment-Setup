# Git Release Flow Example

실제 릴리스 워크플로우 예시입니다.

## 시나리오

EliteDeck AI 프로젝트의 v2.1.0 마이너 릴리스:
- 새 기능 3개 추가
- 버그 수정 5개
- 성능 개선 2개

## 전체 워크플로우

```
[develop] ─── 기능 개발 완료
     │
     └── [release/2.1.0] 릴리스 브랜치 생성
              │
              ├── 버전 범프
              ├── Changelog 업데이트
              ├── 최종 테스트
              │
     ┌────────┴────────┐
     ↓                 ↓
  [main]           [develop]
     │                 │
     ├── 태그 생성     └── 다음 개발 시작
     ├── GitHub Release
     └── 프로덕션 배포
```

## Step 1: 릴리스 준비

### CLI 명령

```bash
"v2.1.0 릴리스 준비해줘"
```

### 실행 내용

```yaml
release_prep:
  steps:
    # 1. develop 브랜치 최신화
    - command: "git checkout develop && git pull origin develop"

    # 2. 릴리스 브랜치 생성
    - command: "git checkout -b release/2.1.0"

    # 3. 버전 범프
    - files:
        - path: "package.json"
          change: '"version": "2.0.5"' → '"version": "2.1.0"'
        - path: "package-lock.json"
          change: '"version": "2.0.5"' → '"version": "2.1.0"'

    # 4. Changelog 업데이트
    - generate_changelog:
        from: "v2.0.5"
        to: "HEAD"
```

### Changelog 생성 결과

```markdown
# Changelog

## [2.1.0](https://github.com/org/elitedeck/compare/v2.0.5...v2.1.0) (2024-01-15)

### Features

* **wizard:** 새로운 5단계 프레젠테이션 생성 마법사 ([#234](https://github.com/org/elitedeck/pull/234))
* **ai:** Genspark AI 리서치 통합 ([#238](https://github.com/org/elitedeck/pull/238))
* **export:** PDF 내보내기 지원 ([#241](https://github.com/org/elitedeck/pull/241))

### Bug Fixes

* **editor:** 드래그 앤 드롭 정렬 오류 수정 ([#235](https://github.com/org/elitedeck/pull/235))
* **brand:** 브랜드 색상 추출 정확도 개선 ([#237](https://github.com/org/elitedeck/pull/237))
* **canvas:** 텍스트 요소 리사이즈 버그 수정 ([#239](https://github.com/org/elitedeck/pull/239))
* **api:** 세션 타임아웃 처리 개선 ([#240](https://github.com/org/elitedeck/pull/240))
* **ui:** 다크 모드 색상 대비 수정 ([#242](https://github.com/org/elitedeck/pull/242))

### Performance Improvements

* **render:** 슬라이드 렌더링 속도 40% 향상 ([#236](https://github.com/org/elitedeck/pull/236))
* **bundle:** 청크 분할로 초기 로딩 30% 개선 ([#243](https://github.com/org/elitedeck/pull/243))
```

## Step 2: 최종 검증

### CLI 명령

```bash
"릴리스 검증 실행해줘"
```

### 검증 DAG

```yaml
dag:
  name: "release-verification"

  nodes:
    - id: lint
      command: "npm run lint"

    - id: typecheck
      command: "npm run typecheck"
      depends_on: [lint]

    - id: test-unit
      command: "npm run test:unit -- --coverage"
      depends_on: [lint]
      timeout: 600000

    - id: test-e2e
      command: "npm run test:e2e"
      depends_on: [typecheck, test-unit]
      condition: "typecheck.success AND test-unit.success"

    - id: build
      command: "npm run build"
      depends_on: [test-e2e]
      condition: "test-e2e.success"

    - id: bundle-check
      command: "npm run analyze:bundle"
      depends_on: [build]
```

### 검증 결과

```
Release Verification: v2.1.0
━━━━━━━━━━━━━━━━━━━━━━━━━━━━

[✓] Lint          - 0 errors, 2 warnings
[✓] TypeCheck     - 0 errors
[✓] Unit Tests    - 487/487 passed
[✓] E2E Tests     - 45/45 passed
[✓] Build         - Success (245KB gzipped)
[✓] Bundle Check  - Within limits

Coverage: 85.2% (target: 80%)
Bundle Size: 245KB (limit: 300KB)

✅ All checks passed. Ready for release.
```

## Step 3: 커밋 및 푸시

### CLI 명령

```bash
"릴리스 2.1.0 커밋하고 푸시해줘"
```

### 실행 내용

```yaml
release_commit:
  steps:
    - command: |
        git add package.json package-lock.json CHANGELOG.md
        git commit -m "chore(release): prepare 2.1.0

        - Bump version to 2.1.0
        - Update CHANGELOG.md

        Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"

    - command: "git push origin release/2.1.0"
```

## Step 4: PR 생성 및 머지

### CLI 명령

```bash
"release/2.1.0에서 main으로 PR 생성해줘"
```

### PR 내용

```markdown
## Release 2.1.0

### Summary
This release includes 3 new features, 5 bug fixes, and 2 performance improvements.

### Highlights
- **New Wizard**: 5-step presentation creation wizard
- **AI Research**: Genspark AI integration for deep research
- **PDF Export**: Export presentations to PDF format

### Breaking Changes
None

### Migration Guide
No migration required.

### Checklist
- [x] Version bumped
- [x] CHANGELOG updated
- [x] All tests passing
- [x] Bundle size within limits
- [x] Documentation updated

### Test Results
```
Unit Tests: 487/487 passed
E2E Tests: 45/45 passed
Coverage: 85.2%
```
```

### 머지 후 자동화

```yaml
on_merge:
  - checkout: main
  - pull: origin/main
  - merge: release/2.1.0 → develop
  - delete_branch: release/2.1.0
```

## Step 5: 태그 및 Release 생성

### CLI 명령

```bash
"v2.1.0 태그 생성하고 GitHub Release 만들어줘"
```

### 실행 내용

```yaml
release_tag:
  steps:
    # 1. 태그 생성
    - command: |
        git tag -a v2.1.0 -m "Release version 2.1.0"
        git push origin v2.1.0

    # 2. GitHub Release 생성
    - gh_release:
        tag: "v2.1.0"
        title: "v2.1.0 - New Wizard & AI Research"
        body_from: "CHANGELOG.md"
        draft: false
        prerelease: false
```

### GitHub Release 출력

```
🚀 Release v2.1.0 created successfully!

URL: https://github.com/org/elitedeck/releases/tag/v2.1.0

Assets:
- Source code (zip)
- Source code (tar.gz)
```

## Step 6: 프로덕션 배포

### CLI 명령

```bash
"v2.1.0 프로덕션 배포해줘"
```

### 배포 DAG

```yaml
dag:
  name: "production-deploy"

  nodes:
    - id: deploy-staging
      command: "npm run deploy:staging"

    - id: smoke-test
      command: "npm run test:smoke -- --env=staging"
      depends_on: [deploy-staging]
      timeout: 120000

    - id: approve-production
      command: "echo 'Waiting for approval...'"
      depends_on: [smoke-test]
      requires_approval: true

    - id: deploy-production
      command: "npm run deploy:production"
      depends_on: [approve-production]

    - id: verify-production
      command: "npm run test:smoke -- --env=production"
      depends_on: [deploy-production]

    - id: notify
      command: "npm run notify:release -- --version=2.1.0"
      depends_on: [verify-production]
```

### 배포 결과

```
Production Deployment: v2.1.0
━━━━━━━━━━━━━━━━━━━━━━━━━━━━

[✓] Staging Deploy    - https://staging.elitedeck.ai
[✓] Smoke Tests       - All passed
[⏸] Production Approval - Approved by @user
[✓] Production Deploy - https://elitedeck.ai
[✓] Verification      - All health checks passed
[✓] Notification      - Sent to #releases

🎉 v2.1.0 successfully deployed to production!
```

## Step 7: 릴리스 알림

### Slack 알림

```
🚀 *EliteDeck AI v2.1.0 Released!*

*Highlights:*
• New 5-step presentation wizard
• Genspark AI research integration
• PDF export support

*Performance:*
• 40% faster slide rendering
• 30% smaller initial bundle

<https://github.com/org/elitedeck/releases/tag/v2.1.0|View Release Notes>
<https://elitedeck.ai|Try it now>
```

## 전체 타임라인

| 단계 | 소요 시간 | 누적 |
|------|----------|------|
| 릴리스 준비 | 2분 | 2분 |
| 최종 검증 | 15분 | 17분 |
| 커밋 및 푸시 | 1분 | 18분 |
| PR 리뷰 및 머지 | 10분 | 28분 |
| 태그 및 Release | 1분 | 29분 |
| 스테이징 배포 | 3분 | 32분 |
| 프로덕션 승인 | 5분 | 37분 |
| 프로덕션 배포 | 3분 | 40분 |
| 알림 | 1분 | 41분 |

**총 소요 시간:** ~41분

## 롤백 시나리오

### 프로덕션 이슈 발생 시

```bash
"v2.0.5로 롤백해줘"
```

```yaml
rollback:
  steps:
    - revert_deploy:
        from: "v2.1.0"
        to: "v2.0.5"

    - notify:
        message: "v2.1.0 rolled back to v2.0.5"
        channel: "#alerts"

    - create_hotfix_branch:
        from: "v2.1.0"
        name: "hotfix/v2.1.1"
```
