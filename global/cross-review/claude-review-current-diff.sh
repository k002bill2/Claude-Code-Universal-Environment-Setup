#!/bin/bash
# ============================================================================
# claude-review-current-diff.sh — Codex author 가 완료 직전에 부르는 front-end
# ----------------------------------------------------------------------------
# Codex 세션(author)이 동기 tool step 으로 이것을 실행하면, 같은 worktree 의
# 동결된 diff 를 Claude reviewer 가 read-only 로 검토하고 결과가 stdout 으로
# 돌아온다. author 는 P0/P1 만 수정한 뒤 **같은 reviewer 로 1회만** 재실행한다.
#
# --author 는 codex 로 고정된다 — 이 front-end 는 Codex author 전용이다.
# 종료 코드는 run-claude-review.sh 와 동일하다.
# ============================================================================
set -euo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "${SELF_DIR}/run-claude-review.sh" --author codex "$@"
