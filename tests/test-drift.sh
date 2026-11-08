#!/bin/bash
# ============================================================================
# tests/test-drift.sh — 글로벌 드리프트 사전 점검 (R2 결정 3)
# ----------------------------------------------------------------------------
# 실행: bash tests/test-drift.sh
#   D1 rules·skills 드리프트 → WARN, 비차단, 사용자 수정 보존
#   D2 라이브 없음(새 머신) → 드리프트 출력 없음
#   D3 advisor 블록 드리프트 → exit 1, 쓰기 0
#   D4 --force-global → 진행
#   D5 advisor 블록 동일 → 진행
# 격리: HOME 은 mktemp 샌드박스, npm/codex 는 exit 0 셔임. bash 3.2 호환.
# ============================================================================
set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/helpers.sh
. "${REPO_DIR}/tests/helpers.sh"

init_sandbox
install_net_shims "${SANDBOX_ROOT}/shims"
R="$REPO_DIR"
OUT="${SANDBOX_ROOT}/last.out"
ADV="${R}/docs/codex-advisor-worker-bundle/install.sh"
MS='<!-- codex-advisor-worker-bundle:start — 이 블록은 install.sh가 관리. 개인 내용은 블록 밖에 -->'
ME='<!-- codex-advisor-worker-bundle:end -->'

run_inst() { local home="$1"; shift; HOME="$home" bash "${R}/install.sh" "$@" > "$OUT" 2>&1 < /dev/null; }
newenv() { mkdir -p "${SANDBOX_ROOT}/$1-home" "${SANDBOX_ROOT}/$1-proj"; }
H() { printf '%s' "${SANDBOX_ROOT}/$1-home"; }
P() { printf '%s' "${SANDBOX_ROOT}/$1-proj"; }
snap() { snapshot_tree "$1" > "${SANDBOX_ROOT}/$2.snap"; }
same() { [ "$(snapshot_tree "$1")" = "$(cat "${SANDBOX_ROOT}/$2.snap")" ]; }

RULE="$(basename "$(ls "${R}/global/rules/"*.md | head -1)")"
SKILL="$(basename "$(ls -d "${R}/global/skills/"*/ | head -1)")"
SKILLF="$(cd "${R}/global/skills/${SKILL}" && find . -type f | head -1 | sed 's|^\./||')"

# ── D1: rules·skills 드리프트 → WARN, 비차단, 사용자 수정 보존 ──────────
newenv d1
run_inst "$(H d1)" --profile core --project "$(P d1)" || fail "D1 1차 설치 exit≠0"
printf '\n# 라이브 편집\n' >> "$(H d1)/.claude/rules/${RULE}"
printf '\n# 라이브 편집\n' >> "$(H d1)/.claude/skills/${SKILL}/${SKILLF}"
cp "$(H d1)/.claude/rules/${RULE}" "${SANDBOX_ROOT}/d1-rule.want"
run_inst "$(H d1)" --profile core --project "$(P d1)"; RC=$?
[ "$RC" -eq 0 ] && pass "D1 드리프트 있어도 exit 0 (비차단)" || { fail "D1 exit ${RC}"; tail -15 "$OUT"; }
grep -q "rules/${RULE}" "$OUT" && pass "D1 WARN 목록에 rules/${RULE}" || fail "D1 rules 드리프트 미보고"
grep -q "skills/${SKILL}/${SKILLF}" "$OUT" && pass "D1 WARN 목록에 skills 파일" || fail "D1 skills 드리프트 미보고"
grep -q 'sync-from-live.sh' "$OUT" && pass "D1 역동기화 안내" || fail "D1 안내 없음"
cmp -s "$(H d1)/.claude/rules/${RULE}" "${SANDBOX_ROOT}/d1-rule.want" \
    && pass "D1 사용자 수정 보존(USER-MODIFIED)" || fail "D1 사용자 수정이 덮어써짐"

# ── D2: 라이브 없음 → 드리프트 출력 없음 ────────────────────────────────
newenv d2
run_inst "$(H d2)" --profile core --project "$(P d2)"; RC=$?
[ "$RC" -eq 0 ] && pass "D2 exit 0" || fail "D2 exit ${RC}"
grep -q '글로벌 드리프트' "$OUT" && fail "D2 새 머신인데 드리프트 보고" || pass "D2 드리프트 보고 없음"
# 재설치(라이브 = 저장소)도 드리프트 없음
run_inst "$(H d2)" --profile core --project "$(P d2)"
grep -q '글로벌 드리프트' "$OUT" && fail "D2 동일 재설치에서 드리프트 보고" || pass "D2 동일 재설치 드리프트 없음"

# ── advisor 블록 픽스처 ─────────────────────────────────────────────────
o="$(grep -n "<<'CLAUDEMD'" "$ADV" | cut -d: -f1)"
t="$(grep -n '^CLAUDEMD$' "$ADV" | cut -d: -f1)"
write_live_md() {  # $1=home $2=추가 줄(빈 값이면 동일 블록)
    mkdir -p "$1/.claude"
    { echo "# 개인 내용"; echo "$MS"; sed -n "$((o + 1)),$((t - 1))p" "$ADV"
      [ -n "$2" ] && echo "$2"; echo "$ME"; } > "$1/.claude/CLAUDE.md"
}

# ── D3: advisor 블록 드리프트 → exit 1, 쓰기 0 ──────────────────────────
newenv d3
write_live_md "$(H d3)" "- 라이브에서만 추가한 줄"
snap "$(H d3)" d3-home; snap "$(P d3)" d3-proj
run_inst "$(H d3)" --profile core --with-advisor --project "$(P d3)"; RC=$?
[ "$RC" -eq 1 ] && pass "D3 advisor 블록 드리프트 exit 1" || { fail "D3 exit ${RC}"; tail -15 "$OUT"; }
grep -q -- '--force-global' "$OUT" && pass "D3 --force-global 안내" || fail "D3 안내 없음"
same "$(H d3)" d3-home && same "$(P d3)" d3-proj && pass "D3 쓰기 0" || fail "D3 썼음"
run_inst "$(H d3)" --profile full --project "$(P d3)"; RC=$?
[ "$RC" -eq 1 ] && pass "D3 --profile full 도 exit 1" || fail "D3 full exit ${RC}"
same "$(H d3)" d3-home && pass "D3 full 쓰기 0" || fail "D3 full 썼음"

# ── D4: --force-global → 진행 ──────────────────────────────────────────
run_inst "$(H d3)" --profile core --with-advisor --force-global --project "$(P d3)"; RC=$?
[ "$RC" -eq 0 ] && pass "D4 --force-global exit 0" || { fail "D4 exit ${RC}"; tail -15 "$OUT"; }
grep -q 'force-global 로 진행' "$OUT" && pass "D4 WARN 출력" || fail "D4 WARN 없음"

# ── D5: advisor 블록 동일 → 진행 / advisor 미선택이면 점검 안 함 ─────────
newenv d5
write_live_md "$(H d5)" ""
run_inst "$(H d5)" --profile core --with-advisor --project "$(P d5)"; RC=$?
[ "$RC" -eq 0 ] && pass "D5 블록 동일 exit 0" || { fail "D5 exit ${RC}"; tail -15 "$OUT"; }
newenv d6
write_live_md "$(H d6)" "- 라이브에서만 추가한 줄"
run_inst "$(H d6)" --profile core --project "$(P d6)"; RC=$?
[ "$RC" -eq 0 ] && pass "D6 advisor 미선택이면 블록 드리프트 무관(exit 0)" || fail "D6 exit ${RC}"

finish
