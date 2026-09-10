#!/bin/bash
# ============================================================================
# run-codex-review.sh — Claude author → **Codex reviewer** 어댑터
# ----------------------------------------------------------------------------
# 계약: docs/plans/2026-09-09-global-in-session-cross-review.md
#
# 사용:
#   run-codex-review.sh --author claude [--worktree DIR]
#                       [--scope working-tree|branch] [--base REF] [--task-id ID]
#
# 종료 코드: 0 PASS/P2P3_CLOSED · 10 CHANGES_REQUESTED · 20 BLOCKED_* · 2 usage
#
# read-only 격리는 Codex CLI 가 강제한다:
#   --sandbox read-only        모델이 실행하는 셸이 쓰기 불가
#   --output-schema            결과 JSON 스키마를 **CLI 가** 검사
#   --output-last-message      최종 메시지를 **CLI 가** 쓴다 (모델 write 권한 불필요).
#                              경로 대신 /dev/fd/4 를 넘겨 파이프로 받는다 — 아래 참조.
#   --ignore-user-config       ~/.codex/config.toml 을 읽지 않는다 → **MCP 서버가
#                              하나도 로드되지 않는다**. 사용자 설정에 MCP 서버가
#                              10개 넘게 있어도 reviewer 는 전부 없이 돈다.
#                              부작용: model/profile 설정도 함께 빠져 reviewer 는
#                              CLI 기본 모델로 돈다(리뷰 품질·비용에 영향). auth 는
#                              CODEX_HOME 을 계속 쓴다(`codex exec --help` 명시).
#   --ignore-rules             저장소·사용자 execpolicy .rules 를 로드하지 않는다.
#                              리뷰 대상 저장소가 reviewer 실행 정책을 바꾸지 못하게 한다.
#   --ephemeral                세션 파일을 디스크에 남기지 않는다 (보존 정책).
#
# 위 플래그는 전부 `codex exec --help`(codex-cli 0.153.4) 로 실측 확인한 것이다.
# 없는 플래그를 지어내지 않는다. **저자(author) 래퍼(codex-with-review.sh)에는
# 적용하지 않는다** — 격리 대상은 reviewer 이고, author 는 자기 평소 설정으로 돈다.
# ============================================================================
set -euo pipefail

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/review-state.sh"

# rs_review_main 이 부르는 provider 훅.
# $1 프롬프트 파일, $2 결과 JSON, $3 worktree, $4 스키마 파일
#
# `--output-last-message` 는 **CLI 가 경로로 파일을 연다** — Claude 쪽처럼 fd 를
# 넘길 수단이 없다. 그래서 두 가지로 막는다 (계획 §7.3.2):
#   (1) 쓰기 대상을 영속 경로가 아니라 **방금 mkdir 한 run 디렉토리** 안으로 둔다.
#       그 디렉토리는 난수 이름이라 리뷰 시작 전에 링크를 심어둘 수 없다.
#   (2) 그 내용은 결과 JSON 과 **동일**하다(Claude 봉투와 달리 메타데이터가 없다).
#       따라서 어차피 영속될 내용 외에 새는 것이 없고, run 디렉토리와 함께 사라진다.
# 영속 결과 파일은 Claude 어댑터와 동일하게 O_EXCL fd 9 로만 만든다.
cr_invoke_provider() {
    # $1 worktree. **프롬프트는 stdin, 결과는 stdout.** 결과는 파일이 되지 않는다(H1).
    local bin="${CROSS_REVIEW_CODEX_BIN:-codex}" rc=0
    # 관리 루트 안에 Codex 가 이름으로 여는 것이 하나도 없다:
    #   프롬프트 → stdin · 출력 스키마 → /dev/fd/5 · 최종 메시지 → /dev/fd/4(= stdout)
    # /dev 는 사용자가 바꿔칠 수 없으므로 조상 스왑으로 재지향되지 않는다.
    #
    # 주의(계획 §12): 이 조합은 **live smoke 미검증**이다. 열지 못하면 결과가 비어
    # BLOCKED_ERROR 로 끝난다(fail closed — 조용한 PASS 는 아니다).
    set +e
    CROSS_REVIEW_ROLE=reviewer "$bin" exec \
        --cd "$1" \
        --sandbox read-only \
        --ignore-user-config \
        --ignore-rules \
        --ephemeral \
        --output-schema /dev/fd/5 \
        --output-last-message /dev/fd/4 \
        --color never \
        - 4>&1 1>/dev/null 2>/dev/null 5< <(rs_write_schema)
    rc=$?
    set -e
    return "$rc"
}

rs_review_main codex "$@"
