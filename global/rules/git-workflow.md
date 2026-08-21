# Git Workflow

## Commit Message Format

```
<type>: <description>

<optional body>
```

Types: feat, fix, refactor, docs, test, chore, perf, ci

co-author 푸터(`Co-Authored-By` + `Claude-Session`)는 **자동 주입을 전제하지 말 것.**
주입되는 환경도 있고 안 되는 환경도 있다 (2026-07-25 Claude Code 세션에서 미주입 확인).

절차: 푸터 없이 커밋 → `git log -1 --format=%B` 로 확인 → 없으면 `--amend` 로 추가.
푸시 전 amend 이므로 "published commit amend 금지" 규칙에 저촉되지 않는다.

## Feature Implementation Workflow

계획 → TDD(SSOT: golden-principles.md) → 리뷰는 superpowers 스킬과 네이티브 `/review`를 사용. 완료 후 Conventional Commits 형식으로 커밋 & 푸시.

## PR 작성

PR 생성·요약·테스트 계획은 `commit-push-pr` 스킬에 위임. 새 브랜치는 `-u` 플래그로 push.
