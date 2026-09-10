#!/bin/bash
# ============================================================================
# run-claude-review.sh — Codex author → **Claude reviewer** 어댑터
# ----------------------------------------------------------------------------
# 계약: docs/plans/2026-09-09-global-in-session-cross-review.md
#
# 사용:
#   run-claude-review.sh --author codex [--worktree DIR]
#                        [--scope working-tree|branch] [--base REF] [--task-id ID]
#
# 종료 코드: 0 PASS/P2P3_CLOSED · 10 CHANGES_REQUESTED · 20 BLOCKED_* · 2 usage
#
# **Codex 쪽과 비대칭인 이유(의도된 설계):**
#   `--tools` 는 *도구 이름* 단위이지 경로 단위가 아니다. reviewer 에게 Write 를
#   주면 결과 파일만이 아니라 worktree 어디에나 쓸 수 있어 read-only 계약이 깨진다.
#   그래서 Claude reviewer 는 **파일을 쓰지 않는다** — `--output-format json` 의
#   `.result` 문자열을 이 래퍼가 받아 결과 파일을 쓰고, 파서가 엄격 검증한다.
#
# 사용한 플래그는 전부 설치된 CLI 의 `--help` 로 확인한 것이다. 존재하지 않는
# 플래그를 지어내지 않는다.
# ============================================================================
set -euo pipefail

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/review-state.sh"

# $1 worktree. **프롬프트는 stdin, 결과는 stdout 으로 나간다.**
#
# 관리 루트 안에 provider 가 이름으로 여는 것이 하나도 없고, **결과도 파일이 되지
# 않는다**: 예전에는 `<run>/result.json` 에 쓴 뒤 분류하고 지웠는데, 쓰기와 정리
# 사이에 SIGKILL 이 나면 provider 산문이 무기한 남았다(회수가 "다음 실행" 에 의존).
# 지금은 stdout 파이프로만 흘러 호출자의 셸 변수에 머문다 — 파일이 된 적이 없다.
#
# `--output-format json` 의 stdout 은 결과의 상위집합(세션 메타데이터·비용)이므로
# `jq` 로 `.result` 만 뽑는다. 캡처 상한은 호출자가 `head -c` 로 건다.
cr_invoke_provider() {
    local bin="${CROSS_REVIEW_CLAUDE_BIN:-claude}" prc=0 jrc=0
    local ps
    # provider 종료코드는 파이프라인 rc 가 아니라 PIPESTATUS[0] 이다.
    set +e
    # **대상 워크트리에서 실행한다.** `--add-dir` 은 접근 가능 경로를 더할 뿐
    # 상속된 작업 디렉토리를 바꾸지 않는다. 호출자가 다른 디렉토리에서 게이트를
    # 부르면 reviewer 가 그 무관한 디렉토리를 읽을 수 있다(Codex 경로는 `--cd` 로
    # 이미 고정돼 있었다). 서브셸로 감싸 호출자의 cwd 는 그대로 둔다.
    ( cd "$1" 2>/dev/null || exit 20
      CROSS_REVIEW_ROLE=reviewer "$bin" -p \
        --restricted \
        --tools "Read,Grep,Glob" \
        --strict-mcp-config \
        --permission-mode manual \
        --permission-prompts none \
        --no-session-persistence \
        --output-format json \
        --add-dir "$1" \
        2>/dev/null ) \
      | jq -r 'if type == "object" then (.result // "") else "" end' 2>/dev/null
    ps=("${PIPESTATUS[@]}")
    set -e
    prc="${ps[0]:-0}"; jrc="${ps[1]:-0}"
    [ "$prc" -eq 0 ] || return "$prc"
    [ "$jrc" -eq 0 ] || return "$jrc"
    return 0
}

rs_review_main claude "$@"
