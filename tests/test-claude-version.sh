#!/bin/bash
# ============================================================================
# tests/test-claude-version.sh — 최소 Claude Code 버전 경고 (경고 전용)
# 실행: bash tests/test-claude-version.sh
# 격리: HOME 은 mktemp 샌드박스, claude 는 PATH 앞의 가짜 스크립트.
# ============================================================================
set -uo pipefail
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/helpers.sh
. "${REPO_DIR}/tests/helpers.sh"
init_sandbox
install_net_shims "${SANDBOX_ROOT}/shims"
R="$REPO_DIR"
OUT="${SANDBOX_ROOT}/last.out"
WARN_RE='최소 2.1.293'

mkclaude() {  # $1=dir $2=출력 문자열
    mkdir -p "$1"
    printf '#!/bin/bash\necho "%s"\n' "$2" > "$1/claude"
    chmod +x "$1/claude"
}
run_with() {  # $1=name $2=claude 출력(빈값=claude 없음) 나머지=install 인자
    local n="$1" v="$2"; shift 2
    mkdir -p "${SANDBOX_ROOT}/$n-home" "${SANDBOX_ROOT}/$n-proj"
    local path="${SANDBOX_ROOT}/shims:$PATH"
    if [ -n "$v" ]; then
        mkclaude "${SANDBOX_ROOT}/$n-bin" "$v"
        path="${SANDBOX_ROOT}/$n-bin:${path}"
    fi
    HOME="${SANDBOX_ROOT}/$n-home" PATH="$path" bash "${R}/install.sh" \
        --project "${SANDBOX_ROOT}/$n-proj" "$@" > "$OUT" 2>&1 < /dev/null
}

# 미만 → 경고 + exit 0
run_with v1 "2.1.292 (Claude Code)" --components commands; RC=$?
[ "$RC" -eq 0 ] && pass "V1 2.1.292 exit 0" || fail "V1 exit ${RC}"
grep -q -- "$WARN_RE" "$OUT" && pass "V1 2.1.292 경고" || fail "V1 경고 없음"
grep -q 'claude update' "$OUT" && pass "V1 update 안내" || fail "V1 update 안내 없음"
[ -e "${SANDBOX_ROOT}/v1-proj/.claude/commands/check-health.md" ] && pass "V1 설치 계속" || fail "V1 산출물 없음"

# 이상 → 경고 없음
for v in 2.1.293 2.1.330 2.2.0 3.0.0; do
    n="ok-${v//./_}"
    run_with "$n" "$v (Claude Code)" --components commands; RC=$?
    [ "$RC" -eq 0 ] && pass "V2 $v exit 0" || fail "V2 $v exit ${RC}"
    grep -q -- "$WARN_RE" "$OUT" && fail "V2 $v 경고 오발" || pass "V2 $v 경고 없음"
done

# 정규식 회귀: 2자리 메이저 앞자리 손실 금지 → 경고 없음
for pair in "m10|10.0.0 (Claude Code)" "m12|claude 12.3.4"; do
    n="${pair%%|*}"; v="${pair#*|}"
    run_with "$n" "$v" --components commands; RC=$?
    [ "$RC" -eq 0 ] && pass "V7 '$v' exit 0" || fail "V7 '$v' exit ${RC}"
    grep -q -- "$WARN_RE" "$OUT" && fail "V7 '$v' 경고 오발" || pass "V7 '$v' 경고 없음"
done
# 접두사 v / 접미사 → 2.1.292 로 읽혀 경고
for pair in "pv|v2.1.292" "sb|2.1.292-beta.1 (Claude Code)"; do
    n="${pair%%|*}"; v="${pair#*|}"
    run_with "$n" "$v" --components commands; RC=$?
    [ "$RC" -eq 0 ] && pass "V8 '$v' exit 0" || fail "V8 '$v' exit ${RC}"
    grep -q -- "$WARN_RE" "$OUT" && pass "V8 '$v' 경고" || fail "V8 '$v' 경고 없음"
done

# 문자열 비교 회귀: 2.1.29 < 2.1.293
run_with v3 "2.1.29 (Claude Code)" --components commands; RC=$?
[ "$RC" -eq 0 ] && pass "V3 2.1.29 exit 0" || fail "V3 exit ${RC}"
grep -q -- "$WARN_RE" "$OUT" && pass "V3 2.1.29 경고" || fail "V3 경고 없음"

# claude 미존재 (PATH 에서 실제 claude 제외)
mkdir -p "${SANDBOX_ROOT}/v4-home" "${SANDBOX_ROOT}/v4-proj"
CLEAN_PATH="/usr/bin:/bin:${SANDBOX_ROOT}/shims"
for d in $(dirname "$(command -v jq 2>/dev/null || echo /usr/bin/jq)") $(dirname "$(command -v node 2>/dev/null || echo /usr/bin/node)"); do
    [ -x "$d/claude" ] || CLEAN_PATH="${CLEAN_PATH}:$d"
done
HOME="${SANDBOX_ROOT}/v4-home" PATH="$CLEAN_PATH" bash "${R}/install.sh" \
    --project "${SANDBOX_ROOT}/v4-proj" --components commands > "$OUT" 2>&1 < /dev/null; RC=$?
if PATH="$CLEAN_PATH" command -v claude >/dev/null 2>&1; then
    skip "V4 claude 가 PATH 에 남아 있어 미존재 케이스 생략"
else
    [ "$RC" -eq 0 ] && pass "V4 claude 없음 exit 0" || fail "V4 exit ${RC}"
    grep -q '버전 점검 생략' "$OUT" && pass "V4 생략 메시지" || fail "V4 생략 메시지 없음"
fi

# 파싱 불가
run_with v5 "garbage" --components commands; RC=$?
[ "$RC" -eq 0 ] && pass "V5 garbage exit 0" || fail "V5 exit ${RC}"
grep -q '버전을 읽지 못' "$OUT" && pass "V5 WARN" || fail "V5 WARN 없음"

# --dry-run 에서도 경고
run_with v6 "2.1.292" --dry-run --components commands; RC=$?
[ "$RC" -eq 0 ] && pass "V6 dry-run exit 0" || fail "V6 exit ${RC}"
grep -q -- "$WARN_RE" "$OUT" && pass "V6 dry-run 경고" || fail "V6 경고 없음"

# L-1 토큰 선택 규칙
run_with t1 "built 2026.11.22 version 2.1.292" --components commands; RC=$?
[ "$RC" -eq 0 ] && pass "T1 exit 0" || fail "T1 exit ${RC}"
grep -q -- "$WARN_RE" "$OUT" && pass "T1 built…version 2.1.292 경고" || fail "T1 경고 없음"
mkclaude "${SANDBOX_ROOT}/t2-bin" "build 2026.11.22
2.1.330 (Claude Code)"
mkdir -p "${SANDBOX_ROOT}/t2-home" "${SANDBOX_ROOT}/t2-proj"
HOME="${SANDBOX_ROOT}/t2-home" PATH="${SANDBOX_ROOT}/t2-bin:${SANDBOX_ROOT}/shims:$PATH" bash "${R}/install.sh" \
    --project "${SANDBOX_ROOT}/t2-proj" --components commands > "$OUT" 2>&1 < /dev/null; RC=$?
[ "$RC" -eq 0 ] && pass "T2 exit 0" || fail "T2 exit ${RC}"
grep -q -- "$WARN_RE" "$OUT" && fail "T2 경고 오발" || pass "T2 (Claude Code) 우선 → 경고 없음"
run_with t3 "release 3.0.0 v2.1.292" --components commands; RC=$?
[ "$RC" -eq 0 ] && pass "T3 exit 0" || fail "T3 exit ${RC}"
grep -q -- "$WARN_RE" "$OUT" && pass "T3 v 접두사 2순위 경고" || fail "T3 경고 없음"

# L-2 타임아웃 (일반 경로 + CC_VERSION_FORCE_BASH_TIMEOUT=1 폴백 경로)
SLEEP_MARK="sleep 37"
for mode in native bash; do
    n="to-$mode"
    mkdir -p "${SANDBOX_ROOT}/$n-home" "${SANDBOX_ROOT}/$n-proj" "${SANDBOX_ROOT}/$n-bin"
    printf '#!/bin/bash\nsleep 37; echo 2.1.292\n' > "${SANDBOX_ROOT}/$n-bin/claude"
    chmod +x "${SANDBOX_ROOT}/$n-bin/claude"
    force=""; [ "$mode" = bash ] && force=1
    T0=$SECONDS
    CC_VERSION_FORCE_BASH_TIMEOUT="$force" CLAUDE_VERSION_TIMEOUT=1 HOME="${SANDBOX_ROOT}/$n-home" \
        PATH="${SANDBOX_ROOT}/$n-bin:${SANDBOX_ROOT}/shims:$PATH" bash "${R}/install.sh" \
        --project "${SANDBOX_ROOT}/$n-proj" --components commands > "$OUT" 2>&1 < /dev/null; RC=$?
    EL=$((SECONDS - T0))
    [ "$RC" -eq 0 ] && pass "TO($mode) exit 0" || fail "TO($mode) exit ${RC}"
    grep -q '응답 없음(1초)' "$OUT" && pass "TO($mode) 응답 없음 WARN" || fail "TO($mode) WARN 없음"
    grep -q -- "$WARN_RE" "$OUT" && fail "TO($mode) 버전 경고 오발" || pass "TO($mode) 버전 경고 없음"
    [ "$EL" -lt 10 ] && pass "TO($mode) ${EL}s < 10s" || fail "TO($mode) ${EL}s 초과"
    pgrep -f "$SLEEP_MARK" >/dev/null 2>&1 && fail "TO($mode) 잔존 프로세스" || pass "TO($mode) 잔존 프로세스 0"
done

# 정상 fake 는 타임아웃 경로를 타지 않음 (즉시 응답, 경고 없음)
run_with t4 "2.1.330 (Claude Code)" --components commands; RC=$?
[ "$RC" -eq 0 ] && pass "T4 exit 0" || fail "T4 exit ${RC}"
grep -q '응답 없음' "$OUT" && fail "T4 타임아웃 오발" || pass "T4 타임아웃 미발동"

finish
