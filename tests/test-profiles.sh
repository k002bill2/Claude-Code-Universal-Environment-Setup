#!/bin/bash
# ============================================================================
# tests/test-profiles.sh — git push 제거 회귀 + --profile minimal|core|full
# ----------------------------------------------------------------------------
# 실행: bash tests/test-profiles.sh
#
#   P0  push allow 제거 업그레이드 회귀 (jq 경로 + node 폴백)
#   P1~ 프로필 (BRIEF 필수 케이스 1~10)
#
# 격리: HOME 은 mktemp 샌드박스, npm/codex 는 exit 0 셔임. 실제 HOME 불변.
# 제약: macOS bash 3.2 호환, 모든 경로 인용.
# ============================================================================
set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/helpers.sh
. "${REPO_DIR}/tests/helpers.sh"

if ! command -v jq >/dev/null 2>&1; then
    echo "FAIL: 이 테스트는 산출물 JSON 검증에 실제 jq 가 필요합니다" >&2
    exit 1
fi

init_sandbox
install_net_shims "${SANDBOX_ROOT}/shims"

PUSH='Bash(git push:*)'

# $1=repo $2=home, 나머지=install.sh 인자. 출력은 ${SANDBOX_ROOT}/last.out
run_inst() {
    local repo="$1" home="$2"; shift 2
    HOME="$home" bash "${repo}/install.sh" "$@" > "${SANDBOX_ROOT}/last.out" 2>&1
}

allow_has() {  # $1=settings $2=문자열
    jq -r '.permissions.allow[]?' "$1" 2>/dev/null | grep -qxF "$2"
}

# ── P0: push identity 업그레이드 제거 ───────────────────────────────────
# 구 fragment(push 포함)로 설치 → 신 fragment 로 재설치 → 설치기 소유 push 는 제거,
# 설치 전에 사용자가 넣어 둔 동일 문자열은 보존.
p0_case() {
    local tag="$1" runner="$2"
    local fx="${SANDBOX_ROOT}/p0-${tag}-repo" h="${SANDBOX_ROOT}/p0-${tag}-home"
    local pa="${SANDBOX_ROOT}/p0-${tag}-a" pb="${SANDBOX_ROOT}/p0-${tag}-b"
    local frag="${fx}/project/settings-fragments/cli-orchestration.json"
    make_fixture_repo "$fx"
    mkdir -p "$h" "$pa" "${pb}/.claude"
    cp "$frag" "${SANDBOX_ROOT}/p0-${tag}-new.json"
    jq '.permissions.allow += ["Bash(git push:*)"]' "${SANDBOX_ROOT}/p0-${tag}-new.json" > "$frag"
    # (b) 사용자가 설치 전에 같은 문자열을 넣어 둔 프로젝트
    printf '{"permissions":{"allow":["%s"]}}\n' "$PUSH" > "${pb}/.claude/settings.json"

    $runner run_inst "$fx" "$h" --project "$pa" || fail "P0[$tag] 구 fragment 설치 exit≠0"
    $runner run_inst "$fx" "$h" --project "$pb" || fail "P0[$tag] 구 fragment 설치(b) exit≠0"
    allow_has "${pa}/.claude/settings.json" "$PUSH" \
        && pass "P0[$tag] 구 fragment 설치 직후 push 존재(전제)" \
        || fail "P0[$tag] 구 fragment 설치에 push 없음(전제 깨짐)"

    cp "${SANDBOX_ROOT}/p0-${tag}-new.json" "$frag"
    $runner run_inst "$fx" "$h" --project "$pa" || fail "P0[$tag] 신 fragment 재설치 exit≠0"
    $runner run_inst "$fx" "$h" --project "$pb" || fail "P0[$tag] 신 fragment 재설치(b) exit≠0"
    allow_has "${pa}/.claude/settings.json" "$PUSH" \
        && fail "P0[$tag] (a) 업그레이드 후에도 설치기 소유 push allow 잔존" \
        || pass "P0[$tag] (a) 업그레이드가 설치기 소유 push allow 제거"
    allow_has "${pa}/.claude/settings.json" 'Bash(git pull:*)' \
        && pass "P0[$tag] 나머지 allow 유지" || fail "P0[$tag] 나머지 allow 소실"
    allow_has "${pb}/.claude/settings.json" "$PUSH" \
        && pass "P0[$tag] (b) 사용자가 먼저 넣은 push 문자열 보존" \
        || fail "P0[$tag] (b) 사용자 push 문자열이 지워짐"
}

direct() { "$@"; }
p0_case jq direct
if command -v node >/dev/null 2>&1; then
    p0_case node run_without_jq
else
    skip "P0[node] node 없음 — 폴백 경로 미검증"
fi

finish
