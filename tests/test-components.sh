#!/bin/bash
# ============================================================================
# tests/test-components.sh — --components <키,키,...> (R2 결정 1)
# ----------------------------------------------------------------------------
# 실행: bash tests/test-components.sh
# 격리: HOME 은 mktemp 샌드박스, npm/codex 는 exit 0 셔임. 실제 HOME 불변.
#       각 케이스는 샌드박스 HOME 의 전·후 스냅샷으로 의도치 않은 쓰기 0 을 확인한다.
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
R="$REPO_DIR"
OUT="${SANDBOX_ROOT}/last.out"

run_inst() {  # $1=home, 나머지=install.sh 인자 (stdin 은 /dev/null — 입력 대기 금지)
    local home="$1"; shift
    HOME="$home" bash "${R}/install.sh" "$@" > "$OUT" 2>&1 < /dev/null
}
newenv() { mkdir -p "${SANDBOX_ROOT}/$1-home" "${SANDBOX_ROOT}/$1-proj"; }
H() { printf '%s' "${SANDBOX_ROOT}/$1-home"; }
P() { printf '%s' "${SANDBOX_ROOT}/$1-proj"; }
snap() { snapshot_tree "$1" > "${SANDBOX_ROOT}/$2.snap"; }
same() { [ "$(snapshot_tree "$1")" = "$(cat "${SANDBOX_ROOT}/$2.snap")" ]; }
has() { [ -e "$1" ] && pass "$2" || fail "$2"; }
hasnt() { [ -e "$1" ] && fail "$2" || pass "$2"; }
out_has() { grep -q -- "$1" "$OUT" && pass "$2" || { fail "$2"; sed 's/^/    | /' "$OUT" | tail -20; }; }

# ── K1: --components 단독 = 정확히 그 목록 ──────────────────────────────
newenv k1
snap "$(H k1)" k1-home
run_inst "$(H k1)" --project "$(P k1)" --components hooks,commands; RC=$?
[ "$RC" -eq 0 ] && pass "K1 exit 0" || { fail "K1 exit ${RC}"; tail -20 "$OUT"; }
same "$(H k1)" k1-home && pass "K1 HOME 쓰기 0" || fail "K1 HOME 에 썼음"
has "$(P k1)/.claude/hooks/stop-self-check.sh" "K1 hooks 설치"
has "$(P k1)/.claude/commands/check-health.md" "K1 check-health.md 설치"
has "$(P k1)/.claude/commands/verify-app.md" "K1 verify-app.md 설치"
for x in .claude/commands/auto.md .claude/agents .claude/skills .claude/skill-rules.json \
         .claude/settings.json CLAUDE.md dev docs .mcp.json.example; do
    hasnt "$(P k1)/$x" "K1 없음: $x"
done
[ "$(cat "$(P k1)/.claude/.install-profile" 2>/dev/null)" = "components=commands,hooks" ] \
    && pass "K1 기록 = components=commands,hooks" \
    || fail "K1 기록 이상: $(cat "$(P k1)/.claude/.install-profile" 2>/dev/null)"
out_has '.claude 쓰기: 아니오' "K1 요약에 ~/.claude 쓰기: 아니오"

# ── K2: 기록 재사용 (플래그 없이 --project 만) ───────────────────────────
rm -f "$(P k1)/.claude/commands/check-health.md"
run_inst "$(H k1)" --project "$(P k1)"; RC=$?
[ "$RC" -eq 0 ] && pass "K2 재실행 exit 0" || fail "K2 재실행 exit ${RC}"
has "$(P k1)/.claude/commands/check-health.md" "K2 기록된 components 재사용(check-health 재설치)"
hasnt "$(P k1)/.claude/agents" "K2 core 로 넘어가지 않음(agents 없음)"
same "$(H k1)" k1-home && pass "K2 HOME 쓰기 0" || fail "K2 HOME 에 썼음"
out_has 'recorded' "K2 요약 출처 recorded"

# ── K3: --profile minimal + --components 합집합 ─────────────────────────
newenv k3
snap "$(H k3)" k3-home
run_inst "$(H k3)" --project "$(P k3)" --profile minimal --components hooks,commands-auto; RC=$?
[ "$RC" -eq 0 ] && pass "K3 exit 0" || { fail "K3 exit ${RC}"; tail -20 "$OUT"; }
same "$(H k3)" k3-home && pass "K3 HOME 쓰기 0" || fail "K3 HOME 에 썼음"
has "$(P k3)/CLAUDE.md" "K3 minimal CLAUDE.md"
grep -q 'Commands' "$(P k3)/CLAUDE.md" 2>/dev/null && pass "K3 CLAUDE.md = minimal 골격" || fail "K3 CLAUDE.md 가 minimal 골격이 아님"
has "$(P k3)/.claude/commands/verify-app.md" "K3 verify-app.md"
has "$(P k3)/.claude/commands/auto.md" "K3 commands-auto → auto.md"
has "$(P k3)/.claude/hooks/build-checker.sh" "K3 hooks"
hasnt "$(P k3)/.claude/agents" "K3 agents 없음"
[ "$(jq '[.permissions.allow[]?] | length' "$(P k3)/.claude/settings.json" 2>/dev/null)" = "0" ] \
    && pass "K3 allow 0 (permissions 미포함)" || fail "K3 allow 존재"
printf 'profile=minimal\ncomponents=commands-auto,hooks\n' > "${SANDBOX_ROOT}/k3.want"
[ "$(cat "$(P k3)/.claude/.install-profile" 2>/dev/null)" = "$(cat "${SANDBOX_ROOT}/k3.want")" ] \
    && pass "K3 기록 두 줄" || fail "K3 기록 이상: $(cat "$(P k3)/.claude/.install-profile" 2>/dev/null)"

# ── K4: 알 수 없는 키 → exit 1 + 키 목록, 쓰기 0 ─────────────────────────
newenv k4
snap "$(H k4)" k4-home; snap "$(P k4)" k4-proj
run_inst "$(H k4)" --project "$(P k4)" --components hooks,bogus; RC=$?
[ "$RC" -eq 1 ] && pass "K4 알 수 없는 키 exit 1" || fail "K4 exit ${RC}"
out_has 'bogus' "K4 오류에 키 이름"
out_has 'memory-seed' "K4 사용 가능한 키 목록 출력"
same "$(H k4)" k4-home && same "$(P k4)" k4-proj && pass "K4 쓰기 0" || fail "K4 썼음"
run_inst "$(H k4)" --project "$(P k4)" --components cross-review; RC=$?
[ "$RC" -eq 1 ] && pass "K4 cross-review 는 키가 아님(exit 1)" || fail "K4 cross-review exit ${RC}"
run_inst "$(H k4)" --project "$(P k4)" --components ""; RC=$?
[ "$RC" -eq 1 ] && pass "K4 빈 목록 exit 1" || fail "K4 빈 목록 exit ${RC}"

# ── K5: 자동 의존 verify-hooks → hooks (+INFO), settings 병합 ──────────
newenv k5
snap "$(H k5)" k5-home
run_inst "$(H k5)" --project "$(P k5)" --components verify-hooks; RC=$?
[ "$RC" -eq 0 ] && pass "K5 exit 0" || { fail "K5 exit ${RC}"; tail -20 "$OUT"; }
has "$(P k5)/.claude/hooks/stop-self-check.sh" "K5 hooks 자동 추가"
has "$(P k5)/.claude/settings-fragments/verification-hooks.json" "K5 조각 파일"
settings_commands "$(P k5)/.claude/settings.json" | grep -q 'stop-self-check' \
    && pass "K5 verify 훅 병합" || fail "K5 verify 훅 미병합"
out_has 'hooks' "K5 INFO 출력"
grep -q 'components=hooks,verify-hooks' "$(P k5)/.claude/.install-profile" 2>/dev/null \
    && pass "K5 기록에 자동 의존 포함" || fail "K5 기록 이상"
same "$(H k5)" k5-home && pass "K5 HOME 쓰기 0" || fail "K5 HOME 에 썼음"

# ── K6: skill-rules 단독 → system-setup 없음 WARN ───────────────────────
newenv k6
run_inst "$(H k6)" --project "$(P k6)" --components skill-rules; RC=$?
[ "$RC" -eq 0 ] && pass "K6 exit 0" || fail "K6 exit ${RC}"
has "$(P k6)/.claude/skill-rules.json" "K6 skill-rules.json"
grep -q 'WARN.*system-setup' "$OUT" && pass "K6 system-setup 없음 WARN" || fail "K6 WARN 없음"

# ── K7: minimal 기반 + 글로벌 쓰기 키 → exit 1, 쓰기 0 ─────────────────
for k in global memory-seed advisor; do
    newenv "k7$k"
    snap "$(H "k7$k")" "k7$k-home"; snap "$(P "k7$k")" "k7$k-proj"
    run_inst "$(H "k7$k")" --project "$(P "k7$k")" --profile minimal --components "$k"; RC=$?
    [ "$RC" -eq 1 ] && pass "K7 minimal+${k} exit 1" || fail "K7 minimal+${k} exit ${RC}"
    same "$(H "k7$k")" "k7$k-home" && same "$(P "k7$k")" "k7$k-proj" \
        && pass "K7 minimal+${k} 쓰기 0" || fail "K7 minimal+${k} 썼음"
done
# 기록된 minimal 위에 --components 만 주면 명시가 기록을 대체한다(R1 규칙) — minimal 기반 아님
newenv k7r
mkdir -p "$(P k7r)/.claude"; printf 'profile=minimal\n' > "$(P k7r)/.claude/.install-profile"
run_inst "$(H k7r)" --project "$(P k7r)" --components memory-seed; RC=$?
[ "$RC" -eq 0 ] && pass "K7r 명시 components 는 기록 minimal 을 대체(exit 0)" || fail "K7r exit ${RC}"
find "$(H k7r)/.claude/projects" -name MEMORY.md 2>/dev/null | grep -q . \
    && pass "K7r memory-seed 설치(명시)" || fail "K7r memory-seed 없음"
out_has '.claude 쓰기: 예' "K7r 요약에 ~/.claude 쓰기: 예"

# ── K8: system-setup 단독 → settings 선생성, model 미주입 ───────────────
newenv k8
snap "$(H k8)" k8-home
run_inst "$(H k8)" --project "$(P k8)" --components system-setup; RC=$?
[ "$RC" -eq 0 ] && pass "K8 exit 0" || { fail "K8 exit ${RC}"; tail -20 "$OUT"; }
S8="$(P k8)/.claude/settings.json"
has "$S8" "K8 settings.json 존재"
[ "$(jq 'has("model")' "$S8" 2>/dev/null)" = "false" ] && pass "K8 model 키 미주입" || fail "K8 model 키 주입됨"
grep -q '선생성' "$OUT" && pass "K8 선생성 로그" || fail "K8 선생성 로그 없음"
same "$(H k8)" k8-home && pass "K8 HOME 쓰기 0" || fail "K8 HOME 에 썼음"
# 기존 settings 가 있으면 선생성하지 않는다(덮어쓰기 금지)
newenv k8b
mkdir -p "$(P k8b)/.claude"; printf '{"env":{"A":"1"}}\n' > "$(P k8b)/.claude/settings.json"
run_inst "$(H k8b)" --project "$(P k8b)" --components system-setup; RC=$?
[ "$(jq -r '.env.A' "$(P k8b)/.claude/settings.json" 2>/dev/null)" = "1" ] \
    && pass "K8b 기존 settings 보존" || fail "K8b 기존 settings 손상"

# ── K9: --components global 단독 → ~/.claude 쓰기 허용 + 표기 ───────────
newenv k9
run_inst "$(H k9)" --project "$(P k9)" --components global; RC=$?
[ "$RC" -eq 0 ] && pass "K9 exit 0" || { fail "K9 exit ${RC}"; tail -20 "$OUT"; }
ls "$(H k9)/.claude/rules/"*.md >/dev/null 2>&1 && pass "K9 rules 설치" || fail "K9 rules 없음"
out_has '.claude 쓰기: 예' "K9 요약에 ~/.claude 쓰기: 예"
hasnt "$(P k9)/.claude/settings.json" "K9 프로젝트 settings 없음"

# ── K10: --profile core + --components examples 합집합 ──────────────────
newenv k10
run_inst "$(H k10)" --project "$(P k10)" --profile core --components examples; RC=$?
[ "$RC" -eq 0 ] && pass "K10 exit 0" || { fail "K10 exit ${RC}"; tail -20 "$OUT"; }
has "$(P k10)/.claude/agents" "K10 core 자산(agents)"
ls "${R}/examples/agents/"*.md >/dev/null 2>&1 && {
    n="$(basename "$(ls "${R}/examples/agents/"*.md | head -1)")"
    has "$(P k10)/.claude/agents/${n}" "K10 examples 자산"
}
grep -q '^components=examples$' "$(P k10)/.claude/.install-profile" 2>/dev/null \
    && grep -q '^profile=core$' "$(P k10)/.claude/.install-profile" \
    && pass "K10 기록 두 줄" || fail "K10 기록 이상"

# ── K11: claude-md 단독 → minimal 템플릿 (core 템플릿 아님) ─────────────
newenv k11
run_inst "$(H k11)" --project "$(P k11)" --components claude-md; RC=$?
[ "$RC" -eq 0 ] && pass "K11 exit 0" || fail "K11 exit ${RC}"
if [ -f "$(P k11)/CLAUDE.md" ] && ! cmp -s "$(P k11)/CLAUDE.md" "${R}/CLAUDE.md.template"; then
    pass "K11 CLAUDE.md = minimal 골격"
else
    fail "K11 CLAUDE.md 가 없거나 core 템플릿"
fi

# ── K12 (Codex P2): global 없는 components + --with-cross-review → 쓰기 전 exit 1 ──
newenv k12
snap "$(H k12)" k12-home; snap "$(P k12)" k12-proj
run_inst "$(H k12)" --project "$(P k12)" --components commands --with-cross-review; RC=$?
[ "$RC" -eq 1 ] && pass "K12 cross-review 가 조용히 무시되지 않음(exit 1)" || fail "K12 exit ${RC}"
same "$(H k12)" k12-home && same "$(P k12)" k12-proj && pass "K12 쓰기 0" || fail "K12 썼음"

finish
