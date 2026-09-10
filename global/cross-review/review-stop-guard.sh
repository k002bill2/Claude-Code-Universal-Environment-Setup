#!/bin/bash
# ============================================================================
# review-stop-guard.sh — Stop 이벤트 훅 (guard-only safety net)
# ----------------------------------------------------------------------------
# 계약: docs/plans/2026-09-09-global-in-session-cross-review.md §3
#
#   - **리뷰를 절대 실행하지 않는다.** provider 호출 0회.
#   - stop_hook_active / reviewer role 이면 no-op.
#   - 현재 diff 가 "검증된 diff" 와 다르면 BLOCKED_UNREVIEWED 를 상태에 기록하고
#     advisory 를 출력한다.
#   - **항상 exit 0.** 차단(decision: block)을 쓰지 않는다 — 확정 문서가 "차단"과
#     "세션 종료 거부"를 분리하라고 했고, Stop 훅이 세션을 되살리면 그 자체가 P0
#     재진입 경로다. fail-closed 는 exit code 가 아니라 **상태값**으로 산다.
#
# 제약: bash 3.2, 모든 경로 인용.
#
# jq/git 이 없으면 게이트가 **동작할 수 없다**. 예전에는 조용히 exit 0 했는데, 그러면
# opt-in 한 사용자가 "게이트가 있다" 고 믿는 채로 아무 advisory 도 받지 못한다.
# 세션을 막지는 않되(항상 exit 0), 무동작이라는 사실은 반드시 알린다.
# ============================================================================

if ! command -v jq >/dev/null 2>&1; then
    printf '[CROSS-REVIEW] 경고 — jq 가 없어 교차리뷰 게이트가 동작하지 않습니다(리뷰 결과 검증 불가). 설치: brew install jq\n' >&2
    exit 0
fi
command -v git >/dev/null 2>&1 || exit 0

# reviewer 자식 프로세스의 Stop 은 게이트의 관심사가 아니다 (gate 가 gate 를 부르지 않는다)
[ "${CROSS_REVIEW_ROLE:-}" = "reviewer" ] && exit 0

INPUT=""
[ -t 0 ] || INPUT="$(cat)"

if [ -n "$INPUT" ]; then
    if [ "$(printf '%s' "$INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null)" = "true" ]; then
        exit 0
    fi
fi

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -f "${SELF_DIR}/review-state.sh" ] || exit 0
. "${SELF_DIR}/review-state.sh"

ROOT="${CLAUDE_PROJECT_DIR:-}"
if [ -z "$ROOT" ] && [ -n "$INPUT" ]; then
    ROOT="$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)"
fi
[ -n "$ROOT" ] || ROOT="$PWD"
[ -d "$ROOT" ] || exit 0

rs_git "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0
WT="$(rs_git "$ROOT" rev-parse --show-toplevel 2>/dev/null)" || exit 0
[ -n "$WT" ] || exit 0
WT="$(rs_realpath "$WT")"

SCOPE="${CROSS_REVIEW_SCOPE:-working-tree}"
BASE="${CROSS_REVIEW_BASE:--}"

# 상태 기록은 safe-fs(python3)에 의존한다. 쓸 수 없으면 **조용히 사라지지 않는다** —
# 이 훅의 사용자 가시적 절반은 advisory 이고, 그것이 없어지면 미검토 종료가 아무 흔적도
# 남기지 않는다(fail-open). 그래서 기록 실패 시에도 advisory 는 반드시 출력한다.
STATE_OK=yes
if ! rs_fs_available; then
    STATE_OK=no
fi

warn_state_unavailable() {
    echo "  (경고: 링크 안전 파일 연산(python3 / safe-fs.py)을 쓸 수 없어 상태를 기록하지"
    echo "   못했습니다. advisory 만 출력합니다 — 교차리뷰 상태는 갱신되지 않았습니다.)"
}

# fail-closed 기록 후 종료(항상 exit 0 — 이 훅은 세션을 차단하지 않는다).
guard_block() {
    # $1 reason 슬러그, $2 사람이 읽는 메시지
    local t="${CROSS_REVIEW_TASK_ID:-}" wrote=no
    [ -n "$t" ] || t="$(rs_task_id "$WT" "$SCOPE" "$BASE")"
    if [ "$STATE_OK" = yes ] && rs_init_state "$WT" >/dev/null 2>&1 \
       && rs_state_set "$WT" "$t" "schema_version=1" "task_id=${t}" "worktree=${WT}" \
            "scope=${SCOPE}" "base_ref=${BASE}" "phase=BLOCKED_ERROR" "reason=$1" \
            >/dev/null 2>&1; then
        wrote=yes
    fi
    echo "[CROSS-REVIEW] BLOCKED — $2"
    echo "  worktree: ${WT}  scope: ${SCOPE}  base: ${BASE}"
    [ "$wrote" = yes ] || warn_state_unavailable
    echo "  (advisory: 이 훅은 세션을 차단하지 않습니다. 상태만 기록합니다.)"
    exit 0
}

# scope=branch 인데 base 가 없으면 rs_freeze_diff 가 1 을 돌려준다. 예전에는 그것을
# `|| exit 0` 로 삼켜 **조용히 통과**시켰다 — 미검토 diff 로 끝나도 아무 기록이 없는
# fail-open 이다. 이제 명시적으로 차단 상태를 남긴다.
case "$SCOPE" in
    working-tree) BASE="-" ;;
    branch)
        if [ -z "$BASE" ] || [ "$BASE" = "-" ]; then
            guard_block branch_base_missing \
                "CROSS_REVIEW_SCOPE=branch 인데 CROSS_REVIEW_BASE 가 없습니다. 비교 기준 없이 통과시키지 않습니다."
        fi
        if ! rs_git "$WT" rev-parse --verify -q "${BASE}^{commit}" >/dev/null 2>&1; then
            guard_block branch_base_invalid \
                "CROSS_REVIEW_BASE=${BASE} 를 이 저장소에서 확인할 수 없습니다."
        fi
        ;;
    *)  guard_block scope_invalid \
            "CROSS_REVIEW_SCOPE=${SCOPE} 는 working-tree|branch 가 아닙니다." ;;
esac

TASK="${CROSS_REVIEW_TASK_ID:-}"
# task_id 는 (worktree, scope, base) 로 결정된다. 여기서 base 를 '-' 로 고정하면
# 게이트가 쓴 task 와 다른 디렉토리를 읽어, 정상 리뷰된 diff 에 UNREVIEWED 를 찍는다.
[ -n "$TASK" ] || TASK="$(rs_task_id "$WT" "$SCOPE" "$BASE")"

# **임시파일을 쓰지 않는다.** 예전에는 mktemp 로 만든 경로에 셸 리다이렉션으로 동결
# diff 를 썼다. mktemp 는 생성만 안전하게 하고 그 파일을 고정하지 못하므로, 같은 UID 의
# 다른 프로세스가 `>` 직전에 그것을 링크로 바꿔치기하면 동결 diff(소스 전문)가 링크
# 너머로 새고 링크 대상이 truncate 됐다. 이제 스트림에서 바로 해시한다.
CUR="$(rs_emit_diff "$WT" "$SCOPE" "$BASE" | rs_sha256_stdin)"
EMIT_RC="${PIPESTATUS[0]:-0}"
[ "$EMIT_RC" -eq 0 ] \
    || guard_block freeze_failed "diff 동결에 실패했습니다. 통과로 간주하지 않습니다."

# 변경이 없으면 게이트할 대상도 없다 (빈 입력의 sha 와 같으면 diff 가 비었다).
EMPTY_SHA="$(printf '' | rs_sha256_stdin)"
[ "$CUR" != "$EMPTY_SHA" ] || exit 0
[ -n "$CUR" ] || exit 0
REVIEWED="$(rs_state_get "$WT" "$TASK" reviewed_sha)"
PHASE="$(rs_state_get "$WT" "$TASK" phase)"

case "$PHASE" in
    PASS|P2P3_CLOSED)
        if [ -n "$REVIEWED" ] && [ "$REVIEWED" = "$CUR" ]; then
            exit 0    # 검증된 diff 그대로 종료 — 기록할 것이 없다
        fi
        ;;
esac

WROTE=no
if [ "$STATE_OK" = yes ] && rs_init_state "$WT" >/dev/null 2>&1 \
   && rs_state_set "$WT" "$TASK" "schema_version=1" "task_id=${TASK}" "worktree=${WT}" \
        "scope=${SCOPE}" "base_ref=${BASE}" "diff_sha256=${CUR}" \
        "phase=BLOCKED_UNREVIEWED" "reason=unreviewed_at_stop" >/dev/null 2>&1; then
    WROTE=yes
fi

echo "[CROSS-REVIEW] UNREVIEWED — 이 diff 는 교차리뷰를 통과하지 않았습니다 (BLOCKED)."
echo "  worktree: ${WT}"
echo "  현재 diff sha: ${CUR}"
echo "  마지막 검증 sha: ${REVIEWED:--} (phase=${PHASE:--})"
echo "  Claude author → bash \"${SELF_DIR}/run-codex-review.sh\" --author claude --worktree \"${WT}\""
echo "  Codex author  → bash \"${SELF_DIR}/claude-review-current-diff.sh\" --worktree \"${WT}\""
[ "$WROTE" = yes ] || warn_state_unavailable
echo "  (advisory: 이 훅은 세션을 차단하지 않습니다. 상태만 기록합니다.)"
exit 0
