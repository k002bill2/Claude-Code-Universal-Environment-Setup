#!/bin/bash
# ============================================================================
# tests/test-install.sh — 통합 설치기 샌드박스 검증
# ----------------------------------------------------------------------------
# 실행: bash tests/test-install.sh
#
# 검증 항목:
#   A. --full --project 실설치 → exit 0 + 핵심 산출물 존재
#   B. 같은 명령 2회차 → exit 0 + 내용 diff 0 + 신규 .bak 0개 (멱등성)
#   C. --dry-run → 샌드박스 쓰기 0건
#   D. --global-only → 프로젝트 미변경
#   E. 관리 디렉토리 교체 의미론 → 스테일 파일 제거 + 그 후 다시 멱등
#
# 격리:
#   - HOME 을 mktemp 샌드박스로 오버라이드 (~/.claude, ~/.codex 격리)
#   - PATH 앞에 셔임: npm/codex 는 exit 0 스텁 (네트워크 차단),
#     jq/node/python3 는 실제 것 사용
#   - trap 으로 종료 시 샌드박스 전부 삭제 (잔여물 0 계약)
#
# 제약: macOS bash 3.2 호환 (연관배열 금지), 모든 경로 인용.
# ============================================================================
set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL="${REPO_DIR}/install.sh"

if [ ! -f "$INSTALL" ]; then
    echo "FAIL: install.sh 없음: ${INSTALL}" >&2
    exit 1
fi
if ! command -v jq >/dev/null 2>&1; then
    echo "FAIL: 이 테스트는 산출물 JSON 검증에 실제 jq 가 필요합니다" >&2
    exit 1
fi

FAIL_COUNT=0
PASS_COUNT=0
pass() { printf 'PASS: %s\n' "$1"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { printf 'FAIL: %s\n' "$1"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

# ── 샌드박스 + trap 정리 (잔여물 0 계약) ──────────────────────────────
SANDBOX_ROOT="$(mktemp -d)"
cleanup() { rm -rf "$SANDBOX_ROOT"; }
trap cleanup EXIT INT TERM

# ── 셔임: npm/codex 를 exit 0 스텁으로 (advisor 번들의 전역 설치 흡수) ──
SHIM_DIR="${SANDBOX_ROOT}/shims"
mkdir -p "$SHIM_DIR"
for cmd in npm codex; do
    printf '#!/bin/bash\nexit 0\n' > "${SHIM_DIR}/${cmd}"
    chmod +x "${SHIM_DIR}/${cmd}"
done
export PATH="${SHIM_DIR}:${PATH}"

SANDBOX_HOME="${SANDBOX_ROOT}/home"
SANDBOX_PROJECT="${SANDBOX_ROOT}/project"
mkdir -p "$SANDBOX_HOME" "$SANDBOX_PROJECT"

# ── 스냅샷: 파일 내용 해시 목록 (멱등성 = 내용 diff 0) ────────────────
snapshot() {
    # $1 = 루트 디렉토리. 정렬된 "해시  ./상대경로" 목록을 stdout 으로.
    ( cd "$1" && find . -type f -exec shasum -a 256 {} + 2>/dev/null | sort -k2 )
}

count_baks() {
    find "$SANDBOX_HOME" "$SANDBOX_PROJECT" -name '*.bak' -o -name '*.bak.*' 2>/dev/null | wc -l | tr -d ' '
}

# ============================================================================
# Test A: --full --project 실설치 → exit 0 + 핵심 산출물
# ============================================================================
echo "=== Test A: full install ==="
LOG1="${SANDBOX_ROOT}/run1.log"
HOME="$SANDBOX_HOME" bash "$INSTALL" --full --project "$SANDBOX_PROJECT" \
    > "$LOG1" 2>&1 < /dev/null
RC=$?
if [ "$RC" -eq 0 ]; then
    pass "A0 install.sh --full --project exit 0"
else
    fail "A0 install.sh --full --project exit ${RC} (log tail: $(tail -5 "$LOG1" | tr '\n' ' '))"
fi

# A1: ~/.claude/rules 4종
for r in golden-principles interaction security verification; do
    if [ -f "${SANDBOX_HOME}/.claude/rules/${r}.md" ]; then
        pass "A1 ~/.claude/rules/${r}.md 존재"
    else
        fail "A1 ~/.claude/rules/${r}.md 없음"
    fi
done

# A2: ~/.claude/skills 19개 이상
SKILL_COUNT="$(find "${SANDBOX_HOME}/.claude/skills" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')"
if [ "$SKILL_COUNT" -ge 19 ]; then
    pass "A2 ~/.claude/skills ${SKILL_COUNT}개 (>=19)"
else
    fail "A2 ~/.claude/skills ${SKILL_COUNT}개 (<19)"
fi

# A3: 프로젝트 .claude/agents — primary-coordinator.md 포함 6종 이상
AGENTS_DIR="${SANDBOX_PROJECT}/.claude/agents"
if [ -f "${AGENTS_DIR}/primary-coordinator.md" ]; then
    pass "A3 .claude/agents/primary-coordinator.md 존재"
else
    fail "A3 .claude/agents/primary-coordinator.md 없음"
fi
AGENT_COUNT="$(find "$AGENTS_DIR" -maxdepth 1 -name '*.md' 2>/dev/null | wc -l | tr -d ' ')"
if [ "$AGENT_COUNT" -ge 6 ]; then
    pass "A3 .claude/agents ${AGENT_COUNT}개 (>=6)"
else
    fail "A3 .claude/agents ${AGENT_COUNT}개 (<6)"
fi

# A4: system-setup 위임 산출물
if [ -f "${SANDBOX_PROJECT}/.claude/commands/dev-docs.md" ]; then
    pass "A4 .claude/commands/dev-docs.md 존재 (system-setup 위임)"
else
    fail "A4 .claude/commands/dev-docs.md 없음 (system-setup 위임 실패?)"
fi

# A5: settings.json — 유효 JSON + 훅 배선 + model 키 부재
SETTINGS="${SANDBOX_PROJECT}/.claude/settings.json"
if [ -f "$SETTINGS" ] && jq empty "$SETTINGS" >/dev/null 2>&1; then
    pass "A5 settings.json 유효 JSON"
    if jq -e '.hooks.UserPromptSubmit | length > 0' "$SETTINGS" >/dev/null 2>&1; then
        pass "A5 settings.json UserPromptSubmit 훅 배선"
    else
        fail "A5 settings.json UserPromptSubmit 훅 미배선"
    fi
    if jq -e '.hooks.PreCompact | length > 0' "$SETTINGS" >/dev/null 2>&1; then
        pass "A5 settings.json PreCompact 훅 배선"
    else
        fail "A5 settings.json PreCompact 훅 미배선"
    fi
    if jq -e 'has("model") | not' "$SETTINGS" >/dev/null 2>&1; then
        pass "A5 settings.json \"model\" 키 부재"
    else
        fail "A5 settings.json 에 \"model\" 키가 주입됨 (구조적 차단 실패)"
    fi
else
    fail "A5 settings.json 없음 또는 JSON 파싱 불가: ${SETTINGS}"
fi

# A6: 기타 프로젝트 산출물
if [ -f "${SANDBOX_PROJECT}/.mcp.json.example" ]; then
    pass "A6 .mcp.json.example 존재"
else
    fail "A6 .mcp.json.example 없음"
fi
if [ -f "${SANDBOX_PROJECT}/docs/Parallel_Agents_Safety_Protocol_v3_1_0.md" ]; then
    pass "A6 docs/Parallel_Agents_Safety_Protocol_v3_1_0.md 존재"
else
    fail "A6 docs/Parallel_Agents_Safety_Protocol_v3_1_0.md 없음"
fi
for d in "dev/active" "dev/completed"; do
    if [ -d "${SANDBOX_PROJECT}/${d}" ]; then
        pass "A6 ${d}/ 존재"
    else
        fail "A6 ${d}/ 없음"
    fi
done

# A7: advisor 위임 산출물 (--full 에 포함)
if [ -f "${SANDBOX_HOME}/.claude/agents/architect.md" ]; then
    pass "A7 ~/.claude/agents/architect.md 존재 (advisor 위임)"
else
    fail "A7 ~/.claude/agents/architect.md 없음 (advisor 위임 실패?)"
fi

# ============================================================================
# Test B: 멱등성 — 2회차 실행 → 내용 diff 0 + 신규 .bak 0개
# ============================================================================
echo "=== Test B: idempotency (2nd run) ==="
SNAP_HOME_1="${SANDBOX_ROOT}/snap-home-1.txt"
SNAP_PROJ_1="${SANDBOX_ROOT}/snap-proj-1.txt"
snapshot "$SANDBOX_HOME" > "$SNAP_HOME_1"
snapshot "$SANDBOX_PROJECT" > "$SNAP_PROJ_1"
BAKS_BEFORE="$(count_baks)"

LOG2="${SANDBOX_ROOT}/run2.log"
HOME="$SANDBOX_HOME" bash "$INSTALL" --full --project "$SANDBOX_PROJECT" \
    > "$LOG2" 2>&1 < /dev/null
RC=$?
if [ "$RC" -eq 0 ]; then
    pass "B0 2회차 실행 exit 0"
else
    fail "B0 2회차 실행 exit ${RC} (log tail: $(tail -5 "$LOG2" | tr '\n' ' '))"
fi

SNAP_HOME_2="${SANDBOX_ROOT}/snap-home-2.txt"
SNAP_PROJ_2="${SANDBOX_ROOT}/snap-proj-2.txt"
snapshot "$SANDBOX_HOME" > "$SNAP_HOME_2"
snapshot "$SANDBOX_PROJECT" > "$SNAP_PROJ_2"

if diff -u "$SNAP_HOME_1" "$SNAP_HOME_2" > "${SANDBOX_ROOT}/diff-home.txt" 2>&1; then
    pass "B1 HOME 스냅샷 내용 diff 0"
else
    fail "B1 HOME 스냅샷 변경됨: $(grep -c '^[+-][^+-]' "${SANDBOX_ROOT}/diff-home.txt" | tr -d ' ')줄 (예: $(grep '^[+-][^+-]' "${SANDBOX_ROOT}/diff-home.txt" | head -3 | tr '\n' ' '))"
fi
if diff -u "$SNAP_PROJ_1" "$SNAP_PROJ_2" > "${SANDBOX_ROOT}/diff-proj.txt" 2>&1; then
    pass "B1 PROJECT 스냅샷 내용 diff 0"
else
    fail "B1 PROJECT 스냅샷 변경됨: $(grep -c '^[+-][^+-]' "${SANDBOX_ROOT}/diff-proj.txt" | tr -d ' ')줄 (예: $(grep '^[+-][^+-]' "${SANDBOX_ROOT}/diff-proj.txt" | head -3 | tr '\n' ' '))"
fi

BAKS_AFTER="$(count_baks)"
if [ "$BAKS_AFTER" -eq "$BAKS_BEFORE" ]; then
    pass "B2 신규 .bak 0개 (before=${BAKS_BEFORE}, after=${BAKS_AFTER})"
else
    fail "B2 2회차에 신규 .bak 생성됨 (before=${BAKS_BEFORE}, after=${BAKS_AFTER})"
fi

# ============================================================================
# Test C: --dry-run → 샌드박스 쓰기 0건
# ============================================================================
echo "=== Test C: dry-run writes nothing ==="
HOME_C="${SANDBOX_ROOT}/home-c"
PROJ_C="${SANDBOX_ROOT}/proj-c"
mkdir -p "$HOME_C" "$PROJ_C"
LOG3="${SANDBOX_ROOT}/run3.log"
HOME="$HOME_C" bash "$INSTALL" --dry-run --full --project "$PROJ_C" \
    > "$LOG3" 2>&1 < /dev/null
RC=$?
if [ "$RC" -eq 0 ]; then
    pass "C0 --dry-run --full exit 0"
else
    fail "C0 --dry-run --full exit ${RC} (log tail: $(tail -5 "$LOG3" | tr '\n' ' '))"
fi
WRITES_HOME="$(find "$HOME_C" -mindepth 1 2>/dev/null | wc -l | tr -d ' ')"
WRITES_PROJ="$(find "$PROJ_C" -mindepth 1 2>/dev/null | wc -l | tr -d ' ')"
if [ "$WRITES_HOME" -eq 0 ]; then
    pass "C1 dry-run HOME 쓰기 0건"
else
    fail "C1 dry-run 이 HOME 에 ${WRITES_HOME}건 씀: $(find "$HOME_C" -mindepth 1 | head -3 | tr '\n' ' ')"
fi
if [ "$WRITES_PROJ" -eq 0 ]; then
    pass "C1 dry-run PROJECT 쓰기 0건"
else
    fail "C1 dry-run 이 PROJECT 에 ${WRITES_PROJ}건 씀: $(find "$PROJ_C" -mindepth 1 | head -3 | tr '\n' ' ')"
fi

# ============================================================================
# Test D: --global-only → 프로젝트 미변경 (--project 를 줘도 무시해야 함)
# ============================================================================
echo "=== Test D: global-only leaves project untouched ==="
HOME_D="${SANDBOX_ROOT}/home-d"
PROJ_D="${SANDBOX_ROOT}/proj-d"
mkdir -p "$HOME_D" "$PROJ_D"
LOG4="${SANDBOX_ROOT}/run4.log"
HOME="$HOME_D" bash "$INSTALL" --global-only --project "$PROJ_D" \
    > "$LOG4" 2>&1 < /dev/null
RC=$?
if [ "$RC" -eq 0 ]; then
    pass "D0 --global-only exit 0"
else
    fail "D0 --global-only exit ${RC} (log tail: $(tail -5 "$LOG4" | tr '\n' ' '))"
fi
WRITES_PROJ_D="$(find "$PROJ_D" -mindepth 1 2>/dev/null | wc -l | tr -d ' ')"
if [ "$WRITES_PROJ_D" -eq 0 ]; then
    pass "D1 --global-only PROJECT 미변경 (0건)"
else
    fail "D1 --global-only 가 PROJECT 에 ${WRITES_PROJ_D}건 씀: $(find "$PROJ_D" -mindepth 1 | head -3 | tr '\n' ' ')"
fi
# 검증의 검증: 글로벌은 실제로 설치되었어야 함 (테스트 자체가 헛돌지 않았는지)
if [ -d "${HOME_D}/.claude/rules" ]; then
    pass "D2 --global-only 글로벌 설치는 수행됨 (~/.claude/rules 존재)"
else
    fail "D2 --global-only 인데 글로벌도 미설치 (~/.claude/rules 없음 — 테스트 헛돎)"
fi

# ============================================================================
# Test E: 관리 디렉토리 교체 의미론 — 스테일 파일 제거 + 그 후 재멱등
#   (install_managed_dir 이 "복사만" 하면 소스에서 삭제된 파일이 잔존해
#    영구 diff + 매 실행 .bak 이 된다. 교체 의미론이면 1회 실행으로 정리된다.)
# ============================================================================
echo "=== Test E: managed dir replacement removes stale files ==="
STALE_SKILL_DIR="${SANDBOX_HOME}/.claude/skills/dev-docs"
STALE_FILE="${STALE_SKILL_DIR}/stale-removed.md"
if [ -d "$STALE_SKILL_DIR" ]; then
    pass "E0 관리 스킬 디렉토리 존재: ~/.claude/skills/dev-docs/"

    printf 'stale\n' > "$STALE_FILE"
    LOG5="${SANDBOX_ROOT}/run5.log"
    HOME="$SANDBOX_HOME" bash "$INSTALL" --full --project "$SANDBOX_PROJECT" \
        > "$LOG5" 2>&1 < /dev/null
    RC=$?
    if [ "$RC" -eq 0 ]; then
        pass "E1 스테일 심은 후 실행 exit 0"
    else
        fail "E1 스테일 심은 후 실행 exit ${RC} (log tail: $(tail -5 "$LOG5" | tr '\n' ' '))"
    fi
    if [ ! -e "$STALE_FILE" ]; then
        pass "E1 스테일 파일 제거됨 (stale-removed.md)"
    else
        fail "E1 스테일 파일이 잔존함: ${STALE_FILE}"
    fi
    # 검증의 검증: 디렉토리가 통째로 날아간 게 아니라 소스로 재구성되었는지
    if [ -f "${STALE_SKILL_DIR}/SKILL.md" ]; then
        pass "E1 소스 파일 재설치됨 (dev-docs/SKILL.md 존재)"
    else
        fail "E1 dev-docs/SKILL.md 없음 — 교체가 디렉토리를 비우기만 함"
    fi

    # E2: 스테일 정리 직후 상태를 기준으로 다시 멱등이어야 한다
    #     (Test B 의 스냅샷은 dev-docs.bak/ 때문에 재사용 불가 — 새로 뜬다)
    SNAP_HOME_3="${SANDBOX_ROOT}/snap-home-3.txt"
    SNAP_PROJ_3="${SANDBOX_ROOT}/snap-proj-3.txt"
    snapshot "$SANDBOX_HOME" > "$SNAP_HOME_3"
    snapshot "$SANDBOX_PROJECT" > "$SNAP_PROJ_3"
    BAKS_E_BEFORE="$(count_baks)"

    LOG6="${SANDBOX_ROOT}/run6.log"
    HOME="$SANDBOX_HOME" bash "$INSTALL" --full --project "$SANDBOX_PROJECT" \
        > "$LOG6" 2>&1 < /dev/null
    RC=$?
    if [ "$RC" -eq 0 ]; then
        pass "E2 후속 실행 exit 0"
    else
        fail "E2 후속 실행 exit ${RC} (log tail: $(tail -5 "$LOG6" | tr '\n' ' '))"
    fi

    SNAP_HOME_4="${SANDBOX_ROOT}/snap-home-4.txt"
    SNAP_PROJ_4="${SANDBOX_ROOT}/snap-proj-4.txt"
    snapshot "$SANDBOX_HOME" > "$SNAP_HOME_4"
    snapshot "$SANDBOX_PROJECT" > "$SNAP_PROJ_4"

    if diff -u "$SNAP_HOME_3" "$SNAP_HOME_4" > "${SANDBOX_ROOT}/diff-home-e.txt" 2>&1; then
        pass "E2 HOME 스냅샷 내용 diff 0 (스테일 정리 후 재멱등)"
    else
        fail "E2 HOME 스냅샷 변경됨: $(grep -c '^[+-][^+-]' "${SANDBOX_ROOT}/diff-home-e.txt" | tr -d ' ')줄 (예: $(grep '^[+-][^+-]' "${SANDBOX_ROOT}/diff-home-e.txt" | head -3 | tr '\n' ' '))"
    fi
    if diff -u "$SNAP_PROJ_3" "$SNAP_PROJ_4" > "${SANDBOX_ROOT}/diff-proj-e.txt" 2>&1; then
        pass "E2 PROJECT 스냅샷 내용 diff 0 (스테일 정리 후 재멱등)"
    else
        fail "E2 PROJECT 스냅샷 변경됨: $(grep -c '^[+-][^+-]' "${SANDBOX_ROOT}/diff-proj-e.txt" | tr -d ' ')줄 (예: $(grep '^[+-][^+-]' "${SANDBOX_ROOT}/diff-proj-e.txt" | head -3 | tr '\n' ' '))"
    fi

    BAKS_E_AFTER="$(count_baks)"
    if [ "$BAKS_E_AFTER" -eq "$BAKS_E_BEFORE" ]; then
        pass "E2 신규 .bak 0개 (before=${BAKS_E_BEFORE}, after=${BAKS_E_AFTER})"
    else
        fail "E2 후속 실행에 신규 .bak 생성됨 (before=${BAKS_E_BEFORE}, after=${BAKS_E_AFTER})"
    fi
else
    fail "E0 관리 스킬 디렉토리 없음 — 테스트 헛돎: ${STALE_SKILL_DIR}"
fi

# ============================================================================
# 결과 요약
# ============================================================================
echo ""
echo "=== RESULT: PASS ${PASS_COUNT} / FAIL ${FAIL_COUNT} ==="
if [ "$FAIL_COUNT" -gt 0 ]; then
    exit 1
fi
exit 0
