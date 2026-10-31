#!/bin/bash
# ============================================================================
# tests/test-sync-from-live.sh — scripts/sync-from-live.sh 개인 제외 목록 테스트
# ----------------------------------------------------------------------------
# 실행: bash tests/test-sync-from-live.sh
#
# 계약:
#   - scripts/sync-exclude.txt (+ ~/.claude/.sync-exclude.local) 의 rule:/override:
#     항목은 라이브 → repo 동기화에서 빠진다. --no-exclude 는 제외를 무시한다.
#   - 라이브 = repo 스냅샷 + 개인 키뿐이면 skill-overrides.json 은 UNCHANGED (바이트 동일).
#   - --dry-run 은 repo 를 바꾸지 않는다.
#
# 격리: 샌드박스 fixture repo + HOME 오버라이드. 실제 $HOME·원본 repo 미접촉.
# 제약: bash 3.2 호환, 모든 경로 인용.
# ============================================================================
set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "${REPO_DIR}/tests/helpers.sh"

if ! command -v jq >/dev/null 2>&1; then
    echo "FAIL: 이 테스트는 jq 가 필요합니다" >&2
    exit 1
fi

init_sandbox
CASE_N=0

# 케이스마다 새 fixture: 동기화에 필요한 최소 트리만 복사한다(원본 repo 는 읽기만).
# 결과: FIX(repo), FHOME(가짜 HOME), LIVE(=FHOME/.claude)
new_case() {
    CASE_N=$((CASE_N + 1))
    FIX="${SANDBOX_ROOT}/c${CASE_N}/repo"
    FHOME="${SANDBOX_ROOT}/c${CASE_N}/home"
    LIVE="${FHOME}/.claude"
    mkdir -p "${FIX}/scripts" "${FIX}/global" "${LIVE}/rules"
    cp -p "${REPO_DIR}/scripts/sync-from-live.sh" "${REPO_DIR}/scripts/sync-exclude.txt" "${FIX}/scripts/"
    cp -R "${REPO_DIR}/global/rules" "${REPO_DIR}/global/settings-fragments" "${FIX}/global/"
    mkdir -p "${FIX}/global/agents" "${FIX}/global/skills"
    # 라이브 rules = repo rules (드리프트 0) 에서 시작
    cp -p "${FIX}/global/rules/"*.md "${LIVE}/rules/"
}

# 라이브 settings.json: repo 스냅샷 키 + 개인 키 4개(알파벳 위치에 끼워 넣음) + 무관한 최상위 키
write_live_settings_with_personal() {
    jq '{model: "opus", skillOverrides: (.skillOverrides + {
          "aside-browser": "off", "built-in-browser": "off",
          "chrome-browser": "off", "ego-browser": "on"} | to_entries | sort_by(.key) | from_entries)}' \
        "${FIX}/global/settings-fragments/skill-overrides.json" > "${LIVE}/settings.json"
}

run_sync() {
    HOME="$FHOME" bash "${FIX}/scripts/sync-from-live.sh" "$@" 2>&1
}

overrides_has() {
    jq -e --arg k "$1" '.skillOverrides | has($k)' "${FIX}/global/settings-fragments/skill-overrides.json" >/dev/null
}

# ── S1 제외 rule 은 복사 안 됨 + SKIP 출력 ──────────────────────────────
new_case
printf '# personal\n' > "${LIVE}/rules/pstack-models.md"
OUT="$(run_sync)"
if [ ! -e "${FIX}/global/rules/pstack-models.md" ]; then
    pass "S1 제외 rule(pstack-models.md) 은 repo 로 복사되지 않음"
else
    fail "S1 제외 rule 이 repo 로 복사됨"
fi
if printf '%s\n' "$OUT" | grep -qF 'SKIP(개인 제외): pstack-models.md'; then
    pass "S1 SKIP(개인 제외) 출력"
else
    fail "S1 SKIP 출력 없음: $(printf '%s\n' "$OUT" | grep pstack || true)"
fi

# ── S2 제외 override 키는 fragment 에 안 들어감, 나머지 키는 들어감 ─────
new_case
write_live_settings_with_personal
jq '.skillOverrides["new-skill"] = "off"' "${LIVE}/settings.json" > "${LIVE}/s.tmp" && mv "${LIVE}/s.tmp" "${LIVE}/settings.json"
OUT="$(run_sync)"
S2_OK=true
for k in aside-browser built-in-browser chrome-browser ego-browser; do
    if overrides_has "$k"; then S2_OK=false; fail "S2 제외 키 ${k} 가 fragment 에 들어감"; fi
done
$S2_OK && pass "S2 제외 override 키 4개 모두 fragment 에 없음"
if overrides_has new-skill && overrides_has watch; then
    pass "S2 비제외 키(new-skill·기존 watch)는 fragment 에 들어감"
else
    fail "S2 비제외 키 누락"
fi
if printf '%s\n' "$OUT" | grep -qF '(개인 제외 4개)'; then
    pass "S2 출력에 (개인 제외 4개)"
else
    fail "S2 제외 개수 출력 없음: $(printf '%s\n' "$OUT" | grep skill-overrides || true)"
fi

# ── S3 라이브 = repo + 개인 키만 다름 → UNCHANGED, diff 0 ───────────────
new_case
printf '# personal\n' > "${LIVE}/rules/pstack-models.md"
write_live_settings_with_personal
BEFORE="$(snapshot_tree "$FIX")"
OUT="$(run_sync)"
AFTER="$(snapshot_tree "$FIX")"
if printf '%s\n' "$OUT" | grep -qF 'UNCHANGED: skill-overrides.json'; then
    pass "S3 skill-overrides.json UNCHANGED"
else
    fail "S3 UNCHANGED 아님: $(printf '%s\n' "$OUT" | grep skill-overrides || true)"
fi
if [ "$BEFORE" = "$AFTER" ] && ! printf '%s\n' "$OUT" | grep -q 'SYNCED'; then
    pass "S3 repo 트리 변화 0 (SYNCED 0건)"
else
    fail "S3 repo 가 바뀜: $(diff <(printf '%s\n' "$BEFORE") <(printf '%s\n' "$AFTER") | head -5)"
fi

# ── S4 ~/.claude/.sync-exclude.local 병합 ────────────────────────────────
new_case
printf '# mine\n' > "${LIVE}/rules/my-local.md"
jq '.skillOverrides["my-key"] = "off"' "${FIX}/global/settings-fragments/skill-overrides.json" > "${LIVE}/settings.json"
printf '# 로컬 전용\nrule:my-local.md\n  override:my-key  # 인라인 주석\n' > "${LIVE}/.sync-exclude.local"
OUT="$(run_sync)"
if [ ! -e "${FIX}/global/rules/my-local.md" ] && ! overrides_has my-key; then
    pass "S4 .sync-exclude.local 의 rule·override 항목도 제외(공백·주석 허용)"
else
    fail "S4 로컬 제외 목록이 병합되지 않음"
fi

# ── S5 --no-exclude 면 제외 무시 ─────────────────────────────────────────
new_case
printf '# personal\n' > "${LIVE}/rules/pstack-models.md"
write_live_settings_with_personal
OUT="$(run_sync --no-exclude)"
if [ -f "${FIX}/global/rules/pstack-models.md" ] && overrides_has ego-browser && overrides_has aside-browser; then
    pass "S5 --no-exclude: 제외 rule·키까지 동기화"
else
    fail "S5 --no-exclude 인데 제외가 적용됨"
fi

# ── S6 --dry-run 은 아무것도 쓰지 않음 ───────────────────────────────────
new_case
printf '# personal\n' > "${LIVE}/rules/pstack-models.md"
printf '# drift\n' >> "${LIVE}/rules/security.md"
write_live_settings_with_personal
jq '.skillOverrides["new-skill"] = "off"' "${LIVE}/settings.json" > "${LIVE}/s.tmp" && mv "${LIVE}/s.tmp" "${LIVE}/settings.json"
BEFORE="$(snapshot_tree "$FIX")"
LBEFORE="$(snapshot_tree "$LIVE")"
OUT="$(run_sync --dry-run)"
AFTER="$(snapshot_tree "$FIX")"
LAFTER="$(snapshot_tree "$LIVE")"
if [ "$BEFORE" = "$AFTER" ] && [ "$LBEFORE" = "$LAFTER" ]; then
    pass "S6 --dry-run: repo·라이브 모두 무변경"
else
    fail "S6 --dry-run 이 파일을 바꿈"
fi
if printf '%s\n' "$OUT" | grep -qF '[DRY RUN] Would sync: security.md' \
   && printf '%s\n' "$OUT" | grep -qF 'SKIP(개인 제외): pstack-models.md'; then
    pass "S6 --dry-run 은 드리프트 보고 + 제외 SKIP 출력"
else
    fail "S6 --dry-run 출력 이상"
fi

finish
