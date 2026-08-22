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

계획 → TDD(SSOT: golden-principles.md) → 리뷰 → 완료 후 Conventional Commits 형식으로 커밋 & 푸시.

리뷰 도구는 목적이 다르다:
- 구현 중 자기 점검: superpowers 스킬(`requesting-code-review` 등), `/code-review`, `/security-review`.
- **완료 게이트: Codex** (`/codex:review`). `~/.claude/CLAUDE.md` 의 '검증은 무조건' 절이 정본이며
  직접 구현이든 위임이든 생략하지 않는다 — 자기 결과를 자기가 승인하지 않는 것이 핵심이다.
- `/review` 는 네이티브 커맨드가 아니라 로컬 스킬(`~/.claude/skills/review/`, user-invocable-only)이다.

## PR 작성

PR 생성·요약·테스트 계획은 `commit-push-pr` 스킬에 위임. 새 브랜치는 `-u` 플래그로 push.
