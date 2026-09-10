#!/bin/bash
# ============================================================================
# codex-with-review.sh — Codex author 세션 래퍼
# ----------------------------------------------------------------------------
# Codex 를 author 로 띄우되, "완료 선언 전에 반드시 반대편(Claude) reviewer 를
# 동기 실행하라" 는 지시를 시스템 프롬프트로 주입한다.
#
# 이 래퍼는 **리뷰를 대신 실행하지 않는다.** 리뷰 실행 주체는 author 세션이다
# (계획 §3). 래퍼가 리뷰를 돌리면 결과가 author 컨텍스트로 돌아오지 않는다 —
# 그것이 이전 Hook/scheduler 설계가 실패한 지점이다.
#
# 사용: codex-with-review.sh [--worktree DIR] [-- <codex exec 에 넘길 인자...>]
# ============================================================================
set -euo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${SELF_DIR}/review-state.sh"

WORKTREE="$PWD"
while [ $# -gt 0 ]; do
    case "$1" in
        --worktree) WORKTREE="${2:-}"; shift 2 ;;
        --)         shift; break ;;
        -h|--help)
            printf 'usage: codex-with-review.sh [--worktree DIR] [-- <codex args>]\n'
            exit 0 ;;
        *)          break ;;
    esac
done
WORKTREE="$(rs_realpath "$WORKTREE")"

if [ "${CROSS_REVIEW_ROLE:-}" = "reviewer" ]; then
    printf '[CROSS-REVIEW] reviewer 컨텍스트에서 author 래퍼 실행 금지\n' >&2
    exit 2
fi

REVIEW_CMD="bash \"${SELF_DIR}/claude-review-current-diff.sh\" --worktree \"${WORKTREE}\""
INSTRUCTIONS="$(cat <<INSTR
CROSS-REVIEW GATE (mandatory)
Before you declare this task complete you MUST run, as a synchronous step:
  ${REVIEW_CMD}
Exit 0 = PASS or P2P3_CLOSED -> you may finish.
Exit 10 = CHANGES_REQUESTED -> fix ONLY the P0/P1 findings, then run the SAME
          command exactly once more. Do not start unrelated work.
Exit 20 = BLOCKED -> stop and report. Never treat a blocked review as a pass.
Never edit files while the reviewer is running. Never review your own work.
INSTR
)"

CODEX_BIN="${CROSS_REVIEW_CODEX_BIN:-codex}"
exec "$CODEX_BIN" exec --cd "$WORKTREE" -c "experimental_instructions=${INSTRUCTIONS}" "$@"
