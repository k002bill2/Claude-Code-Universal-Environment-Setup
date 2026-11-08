#!/bin/bash
# ============================================================================
# tests/test-menu.sh — 첫 설치 TTY 메뉴 (R2 결정 2) + R1 이월 TTY full 재사용
# ----------------------------------------------------------------------------
# 실행: bash tests/test-menu.sh
# TTY 판정은 CCUES_FORCE_TTY=1 로 강제하고 입력은 stdin 파이프로 준다
# (tests/README.md). 타임아웃 케이스는 CCUES_MENU_TIMEOUT=1 로 줄인다.
# 격리: HOME 은 mktemp 샌드박스. 실제 HOME 불변. bash 3.2 호환.
# ============================================================================
set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/helpers.sh
. "${REPO_DIR}/tests/helpers.sh"

if ! command -v jq >/dev/null 2>&1; then
    echo "FAIL: 이 테스트는 실제 jq 가 필요합니다" >&2
    exit 1
fi

init_sandbox
install_net_shims "${SANDBOX_ROOT}/shims"
R="$REPO_DIR"
OUT="${SANDBOX_ROOT}/last.out"
MENU_TXT='첫 설치 — 설치 구성을 고르세요'

newenv() { mkdir -p "${SANDBOX_ROOT}/$1-home" "${SANDBOX_ROOT}/$1-proj"; }
H() { printf '%s' "${SANDBOX_ROOT}/$1-home"; }
P() { printf '%s' "${SANDBOX_ROOT}/$1-proj"; }
snap() { snapshot_tree "$1" > "${SANDBOX_ROOT}/$2.snap"; }
same() { [ "$(snapshot_tree "$1")" = "$(cat "${SANDBOX_ROOT}/$2.snap")" ]; }
rec_of() { cat "$(P "$1")/.claude/.install-profile" 2>/dev/null; }
menu_shown() { grep -q "$MENU_TXT" "$OUT"; }

# $1=입력 문자열(printf 형식), $2=tag, 나머지=install.sh 인자. TTY 강제.
run_tty() {
    local input="$1" tag="$2"; shift 2
    # shellcheck disable=SC2059
    printf "$input" | HOME="$(H "$tag")" CCUES_FORCE_TTY=1 CCUES_MENU_TIMEOUT=5 \
        bash "${R}/install.sh" "$@" > "$OUT" 2>&1
}

# ── M1: 빈 Enter = minimal ──────────────────────────────────────────────
newenv m1; snap "$(H m1)" m1-home
run_tty '\n' m1 --project "$(P m1)"; RC=$?
[ "$RC" -eq 0 ] && pass "M1 exit 0" || { fail "M1 exit ${RC}"; tail -15 "$OUT"; }
menu_shown && pass "M1 메뉴 표시" || fail "M1 메뉴 미표시"
[ "$(rec_of m1)" = "profile=minimal" ] && pass "M1 Enter → minimal 기록" || fail "M1 기록: $(rec_of m1)"
same "$(H m1)" m1-home && pass "M1 HOME 쓰기 0" || fail "M1 HOME 에 썼음"

# ── M2: 2 = full ────────────────────────────────────────────────────────
newenv m2
run_tty '2\n' m2 --project "$(P m2)"; RC=$?
[ "$RC" -eq 0 ] && pass "M2 exit 0" || { fail "M2 exit ${RC}"; tail -15 "$OUT"; }
[ "$(rec_of m2)" = "profile=full" ] && pass "M2 2 → full 기록" || fail "M2 기록: $(rec_of m2)"
[ -d "$(P m2)/docs/templates/pm2" ] && pass "M2 full 파생 옵션(pm2 템플릿)" || fail "M2 pm2 템플릿 없음"

# ── M3: 4 = core ────────────────────────────────────────────────────────
newenv m3
run_tty '4\n' m3 --project "$(P m3)"; RC=$?
[ "$(rec_of m3)" = "profile=core" ] && pass "M3 4 → core 기록" || fail "M3 기록: $(rec_of m3) rc=${RC}"

# ── M4: 3 + 키 이름 / 번호 ──────────────────────────────────────────────
newenv m4; snap "$(H m4)" m4-home
run_tty '3\nhooks,commands\n' m4 --project "$(P m4)"; RC=$?
[ "$RC" -eq 0 ] && pass "M4 exit 0" || { fail "M4 exit ${RC}"; tail -15 "$OUT"; }
[ "$(rec_of m4)" = "components=commands,hooks" ] && pass "M4 3+키 이름 기록" || fail "M4 기록: $(rec_of m4)"
same "$(H m4)" m4-home && pass "M4 HOME 쓰기 0" || fail "M4 HOME 에 썼음"
newenv m4n
run_tty '3\n10,5\n' m4n --project "$(P m4n)"; RC=$?
[ "$(rec_of m4n)" = "components=commands,hooks" ] && pass "M4n 3+번호 입력" || fail "M4n 기록: $(rec_of m4n) rc=${RC}"
newenv m4b; snap "$(P m4b)" m4b-proj
run_tty '3\nhooks,nope\n' m4b --project "$(P m4b)"; RC=$?
[ "$RC" -eq 1 ] && pass "M4b 3+알 수 없는 키 exit 1" || fail "M4b exit ${RC}"
same "$(P m4b)" m4b-proj && pass "M4b 쓰기 0" || fail "M4b 썼음"

# ── M5: 잘못된 입력 2회 → exit 1, 1회 후 정답이면 진행 ───────────────────
newenv m5; snap "$(H m5)" m5-home; snap "$(P m5)" m5-proj
run_tty 'x\ny\n' m5 --project "$(P m5)"; RC=$?
[ "$RC" -eq 1 ] && pass "M5 잘못된 입력 2회 exit 1" || fail "M5 exit ${RC}"
same "$(H m5)" m5-home && same "$(P m5)" m5-proj && pass "M5 쓰기 0" || fail "M5 썼음"
newenv m5b
run_tty 'x\n1\n' m5b --project "$(P m5b)"; RC=$?
[ "$(rec_of m5b)" = "profile=minimal" ] && pass "M5b 1회 재질문 후 진행" || fail "M5b 기록: $(rec_of m5b) rc=${RC}"

# ── M6: EOF / 타임아웃 → exit 1 (조용히 core 금지) ──────────────────────
newenv m6; snap "$(H m6)" m6-home; snap "$(P m6)" m6-proj
run_tty '' m6 --project "$(P m6)"; RC=$?
[ "$RC" -eq 1 ] && pass "M6 EOF exit 1" || fail "M6 EOF exit ${RC}"
same "$(H m6)" m6-home && same "$(P m6)" m6-proj && pass "M6 EOF 쓰기 0" || fail "M6 EOF 썼음"
SECONDS=0
( sleep 4 ) | HOME="$(H m6)" CCUES_FORCE_TTY=1 CCUES_MENU_TIMEOUT=1 \
    bash "${R}/install.sh" --project "$(P m6)" > "$OUT" 2>&1; RC=$?
[ "$RC" -eq 1 ] && pass "M6 타임아웃 exit 1" || fail "M6 타임아웃 exit ${RC}"
grep -q '타임아웃' "$OUT" && pass "M6 타임아웃 메시지" || fail "M6 메시지 없음"
same "$(H m6)" m6-home && same "$(P m6)" m6-proj && pass "M6 타임아웃 쓰기 0" || fail "M6 타임아웃 썼음"

# ── M7: 메뉴 미표시 조건 (CI=1 / 기록 있음 / --yes / --non-interactive / 비TTY / --dry-run) ──
# 입력은 빈 stdin — 메뉴가 뜨면 EOF 로 exit 1 이 되므로 exit 0 이 곧 "입력 대기 없음" 증거다.
nomenu_case() {  # $1=tag $2=설명, 나머지=env 접두 포함 명령
    local tag="$1" desc="$2"; shift 2
    "$@" > "$OUT" 2>&1 < /dev/null; RC=$?
    [ "$RC" -eq 0 ] && pass "M7 ${desc}: exit 0" || { fail "M7 ${desc}: exit ${RC}"; tail -10 "$OUT"; }
    menu_shown && fail "M7 ${desc}: 메뉴 표시됨" || pass "M7 ${desc}: 메뉴 미표시"
}
newenv m7a
nomenu_case m7a "CI=1" env HOME="$(H m7a)" CI=1 CCUES_FORCE_TTY=1 bash "${R}/install.sh" --project "$(P m7a)"
grep -q '프로필 미지정' "$OUT" && pass "M7 CI=1 → core+경고(R1 규칙)" || fail "M7 CI=1 경고 없음"
newenv m7b; mkdir -p "$(P m7b)/.claude"; printf 'profile=minimal\n' > "$(P m7b)/.claude/.install-profile"
nomenu_case m7b "기록 있음" env HOME="$(H m7b)" CCUES_FORCE_TTY=1 bash "${R}/install.sh" --project "$(P m7b)"
newenv m7c
nomenu_case m7c "--yes" env HOME="$(H m7c)" CCUES_FORCE_TTY=1 bash "${R}/install.sh" --project "$(P m7c)" --yes
newenv m7d
nomenu_case m7d "--non-interactive" env HOME="$(H m7d)" CCUES_FORCE_TTY=1 bash "${R}/install.sh" --project "$(P m7d)" --non-interactive
newenv m7e
nomenu_case m7e "비TTY" env HOME="$(H m7e)" bash "${R}/install.sh" --project "$(P m7e)"
newenv m7f
nomenu_case m7f "--dry-run" env HOME="$(H m7f)" CCUES_FORCE_TTY=1 bash "${R}/install.sh" --project "$(P m7f)" --dry-run

# ── T1 (R1 이월): TTY 경로에서 기록된 full 재사용 → FULL 파생 옵션 적용 ──
# 플래그 없이 실행 → TTY 프로젝트 경로 프롬프트 → 기록(full) 을 이제야 읽는 분기.
newenv t1; mkdir -p "$(P t1)/.claude"; printf 'profile=full\n' > "$(P t1)/.claude/.install-profile"
printf '%s\n' "$(P t1)" | HOME="$(H t1)" CCUES_FORCE_TTY=1 bash "${R}/install.sh" > "$OUT" 2>&1; RC=$?
[ "$RC" -eq 0 ] && pass "T1 exit 0" || { fail "T1 exit ${RC}"; tail -15 "$OUT"; }
[ -d "$(P t1)/docs/templates/pm2" ] && pass "T1 기록 full → pm2 템플릿(FULL 파생)" || fail "T1 pm2 템플릿 없음"
[ -e "$(P t1)/.claude/settings-fragments/verification-hooks.json" ] \
    && pass "T1 기록 full → verify 조각 파일" || fail "T1 verify 조각 파일 없음"
ls "$(P t1)/.claude/agents/"api-architect.md >/dev/null 2>&1 \
    && pass "T1 기록 full → examples" || fail "T1 examples 없음"

finish
