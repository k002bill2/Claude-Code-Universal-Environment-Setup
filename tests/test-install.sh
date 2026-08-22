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
#   G. skillOverrides 안전망 → 유실 시 복원 / 살아 있으면 사용자 값 우선 / 멱등
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
# shasum 을 직접 부르고 오류를 삼키면 그 도구가 없는 환경에서 스냅샷이 비어
# 멱등 비교가 무조건 통과한다. 이식 가능한 해시 체인을 쓴다.
ti_file_hash() {
    local h=""
    if command -v shasum >/dev/null 2>&1; then h="$(shasum -a 256 "$1" 2>/dev/null | awk '{print $1}')"; fi
    if [ -z "$h" ] && command -v sha256sum >/dev/null 2>&1; then h="$(sha256sum "$1" 2>/dev/null | awk '{print $1}')"; fi
    if [ -z "$h" ] && command -v cksum >/dev/null 2>&1; then h="$(cksum "$1" 2>/dev/null | awk '{print $1 "-" $2}')"; fi
    [ -n "$h" ] || h="HASH-UNAVAILABLE"
    printf '%s' "$h"
}

snapshot() {
    # $1 = 루트 디렉토리. 정렬된 "해시  ./상대경로" 목록을 stdout 으로.
    ( cd "$1" 2>/dev/null || return 0
      find . -type f -print 2>/dev/null | LC_ALL=C sort | while IFS= read -r f; do
          [ -n "$f" ] || continue
          printf '%s  %s\n' "$(ti_file_hash "$f")" "$f"
      done )
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

# A1: ~/.claude/rules 7종 (2026-08 live 역동기화 기준)
for r in golden-principles interaction security verification coding-style date-calculation git-workflow; do
    if [ -f "${SANDBOX_HOME}/.claude/rules/${r}.md" ]; then
        pass "A1 ~/.claude/rules/${r}.md 존재"
    else
        fail "A1 ~/.claude/rules/${r}.md 없음"
    fi
done

# A2: ~/.claude/skills — 기대 개수는 소스에서 읽는다 (하드코딩 드리프트 방지)
#     (2026-08 정리: live 삭제 스킬 7종 + 심링크 소유 review 를 페이로드에서 제외)
EXPECTED_SKILLS="$(find "${REPO_DIR}/global/skills" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')"
SKILL_COUNT="$(find "${SANDBOX_HOME}/.claude/skills" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')"
if [ "$EXPECTED_SKILLS" -ge 1 ] && [ "$SKILL_COUNT" -ge "$EXPECTED_SKILLS" ]; then
    pass "A2 ~/.claude/skills ${SKILL_COUNT}개 (>=${EXPECTED_SKILLS})"
else
    fail "A2 ~/.claude/skills ${SKILL_COUNT}개 (<${EXPECTED_SKILLS})"
fi

# A2b: 글로벌 docs 설치 — 정규화된 하위 디렉토리 + install.sh 사본 부재
#   세 어서션은 한 묶음이다: 개수 검증 없이 "install.sh 사본 0개"만 보면
#   docs 설치가 아예 안 돌아도 통과하는 공허한 검증이 된다 (검증의 검증).
DOCS_ROOT="${SANDBOX_HOME}/.claude/docs/claude-code-setup"
SYS_DOC_COUNT="$(find "${DOCS_ROOT}/system-setup" -type f -name '*.md' 2>/dev/null | wc -l | tr -d ' ')"
if [ "$SYS_DOC_COUNT" -ge 17 ]; then
    pass "A2b ~/.claude/docs/claude-code-setup/system-setup ${SYS_DOC_COUNT}개 (>=17)"
else
    fail "A2b ~/.claude/docs/claude-code-setup/system-setup ${SYS_DOC_COUNT}개 (<17)"
fi
ADVISOR_DOC_COUNT="$(find "${DOCS_ROOT}/codex-advisor-worker-bundle" -type f -name '*.md' 2>/dev/null | wc -l | tr -d ' ')"
if [ "$ADVISOR_DOC_COUNT" -ge 3 ]; then
    pass "A2b ~/.claude/docs/claude-code-setup/codex-advisor-worker-bundle ${ADVISOR_DOC_COUNT}개 (>=3)"
else
    fail "A2b ~/.claude/docs/claude-code-setup/codex-advisor-worker-bundle ${ADVISOR_DOC_COUNT}개 (<3)"
fi
DOCS_INSTALLER_COPIES="$(find "$DOCS_ROOT" -type f -name 'install.sh' 2>/dev/null | wc -l | tr -d ' ')"
if [ "$DOCS_INSTALLER_COPIES" -eq 0 ]; then
    pass "A2b docs 설치 대상에 install.sh 사본 없음 (설치기 제외 계약)"
else
    fail "A2b docs 설치 대상에 install.sh 사본 ${DOCS_INSTALLER_COPIES}개: $(find "$DOCS_ROOT" -type f -name 'install.sh' | head -3 | tr '\n' ' ')"
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

# settings.json 안의 모든 command 문자열을 재귀로 수집 (중첩 경로 변화에 견고)
settings_commands() {
    jq -r '[.. | objects | .command? // empty] | .[]' "$1" 2>/dev/null
}

# A8: 실행형 훅 4종 — 파일 존재 + 실행권한 (배선과 무관하게 항상 설치)
for h in stop-self-check build-checker post-tool-failure service-health-check; do
    HOOK_FILE="${SANDBOX_PROJECT}/.claude/hooks/${h}.sh"
    if [ -f "$HOOK_FILE" ] && [ -x "$HOOK_FILE" ]; then
        pass "A8 .claude/hooks/${h}.sh 존재 + 실행권한"
    elif [ -f "$HOOK_FILE" ]; then
        fail "A8 .claude/hooks/${h}.sh 실행권한 없음"
    else
        fail "A8 .claude/hooks/${h}.sh 없음"
    fi
done
# 검증의 검증: system-setup 위임 훅과 이름이 겹치지 않고 공존하는지
if [ -f "${SANDBOX_PROJECT}/.claude/hooks/skill-activator.sh" ]; then
    pass "A8 system-setup 훅(skill-activator.sh) 공존 (이름 비충돌)"
else
    fail "A8 skill-activator.sh 없음 — 위임 훅이 사라짐(이름 충돌/덮어쓰기?)"
fi

# A9: 기본 설치(--full)의 settings.json 배선 불변 — 신규 훅 4종 미배선
if [ -f "$SETTINGS" ]; then
    CMDS_A="$(settings_commands "$SETTINGS")"
    for needle in stop-self-check build-checker post-tool-failure service-health-check; do
        if printf '%s\n' "$CMDS_A" | grep -q "$needle"; then
            fail "A9 --full 인데 settings.json 에 ${needle} 배선됨 (기본 배선 불변 위반)"
        else
            pass "A9 settings.json 에 ${needle} 미배선 (--full 기본 배선 불변)"
        fi
    done
    if jq -e '(.hooks // {}) | has("Stop") | not' "$SETTINGS" >/dev/null 2>&1; then
        pass "A9 settings.json 에 Stop 이벤트 부재 (--full)"
    else
        fail "A9 --full 인데 Stop 이벤트가 배선됨"
    fi
    # --full 은 verify-hooks "조각 파일"은 깔아야 한다 (파일 O / 배선 X 계약)
    if [ -f "${SANDBOX_PROJECT}/.claude/settings-fragments/verification-hooks.json" ]; then
        pass "A9 verification-hooks.json 조각 파일은 설치됨 (--full)"
    else
        fail "A9 verification-hooks.json 조각 파일 없음 (--full)"
    fi
else
    fail "A9 settings.json 없음 — 배선 부재 검증 헛돎"
fi

# A10: guardrails 영구 검증 (python3 게이트 — 미배선 회귀를 잡는다)
if command -v python3 >/dev/null 2>&1; then
    if [ -f "$SETTINGS" ]; then
        if jq -e 'any(.hooks.PreToolUse[]?; .matcher == "Bash")' "$SETTINGS" >/dev/null 2>&1; then
            pass "A10 guardrails PreToolUse matcher \"Bash\" 배선"
        else
            fail "A10 guardrails PreToolUse matcher \"Bash\" 미배선"
        fi
        if jq -e 'any(.hooks.PreToolUse[]?; .matcher == "Edit|Write")' "$SETTINGS" >/dev/null 2>&1; then
            pass "A10 guardrails PreToolUse matcher \"Edit|Write\" 배선"
        else
            fail "A10 guardrails PreToolUse matcher \"Edit|Write\" 미배선"
        fi
        if jq -e '[.hooks.PreToolUse[]?.hooks[]?.command] | map(select(startswith("python3"))) | length >= 2' \
             "$SETTINGS" >/dev/null 2>&1; then
            pass "A10 guardrails python3 훅 명령 2건 이상 존재"
        else
            fail "A10 guardrails python3 훅 명령이 2건 미만 (차단 훅 소실)"
        fi
    else
        fail "A10 settings.json 없음 — guardrails 검증 헛돎"
    fi
else
    echo "SKIP: A10 guardrails 검증 — python3 없음 (설치기가 병합을 스킵하는 환경)"
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
STALE_SKILL_DIR="${SANDBOX_HOME}/.claude/skills/cli-orchestration"
STALE_FILE="${STALE_SKILL_DIR}/stale-removed.md"
if [ -d "$STALE_SKILL_DIR" ]; then
    pass "E0 관리 스킬 디렉토리 존재: ~/.claude/skills/cli-orchestration/"

    # 소유권 모델 전환(2026-08-21): 관리 디렉토리는 더 이상 rm -rf 통째 교체가
    # 아니라 manifest 기반 파일 단위 동기화다. 따라서 "제거 대상 스테일"은
    # installer 가 설치한 뒤 아무도 안 건드린 파일(= manifest 기록 해시와 현재
    # 해시가 같은 파일)로 한정된다. 사용자가 직접 넣은 파일은 보존이 정답이므로
    # 아래 두 가지를 함께 심어 양쪽을 모두 검증한다.
    printf 'stale\n' > "$STALE_FILE"
    E_MANIFEST="${SANDBOX_HOME}/.claude/.manifest"
    printf 'skills/cli-orchestration/stale-removed.md\t%s\n' \
        "$(shasum -a 256 "$STALE_FILE" | awk '{print $1}')" >> "$E_MANIFEST"
    # 사용자가 직접 추가한 파일 — 제거되면 안 된다
    E_USER_FILE="${STALE_SKILL_DIR}/user-added.md"
    printf 'user added\n' > "$E_USER_FILE"

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
        pass "E1 소스 파일 재설치됨 (cli-orchestration/SKILL.md 존재)"
    else
        fail "E1 cli-orchestration/SKILL.md 없음 — 교체가 디렉토리를 비우기만 함"
    fi
    # 소유권 모델의 다른 한쪽: 사용자가 추가한 파일은 살아 있어야 한다
    if [ -f "$E_USER_FILE" ] && grep -q 'user added' "$E_USER_FILE"; then
        pass "E1 사용자 추가 파일 보존됨 (cli-orchestration/user-added.md)"
    else
        fail "E1 사용자 추가 파일이 삭제됨: ${E_USER_FILE}"
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
# Test F: 옵트인 훅 배선 (--with-verify-hooks / --with-pm2) + 각각 재실행 멱등
#   Test A 가 "--full 은 배선하지 않는다"를 지키는지 보는 음성 검증이라면,
#   여기서는 명시 플래그가 실제로 배선하는지 양성 검증한다. 새 샌드박스를 쓰므로
#   .bak 카운트는 대상 디렉토리를 인자로 받는 헬퍼로 센다(A~E 의 카운터는 고정 경로).
# ============================================================================
echo "=== Test F: opt-in hook wiring (verify-hooks / pm2) ==="

# find 의 -o 우선순위 함정 회피: 그룹 + 명시적 -print
count_baks_in() {
    find "$@" \( -name '*.bak' -o -name '*.bak.*' \) -print 2>/dev/null | wc -l | tr -d ' '
}
file_hash() {
    shasum -a 256 "$1" 2>/dev/null | awk '{print $1}'
}

# ── F1: --with-verify-hooks → Stop / PostToolUse 배선 ──────────────────
HOME_F1="${SANDBOX_ROOT}/home-f1"
PROJ_F1="${SANDBOX_ROOT}/proj-f1"
mkdir -p "$HOME_F1" "$PROJ_F1"
LOG_F1="${SANDBOX_ROOT}/run-f1.log"
HOME="$HOME_F1" bash "$INSTALL" --with-verify-hooks --project "$PROJ_F1" \
    > "$LOG_F1" 2>&1 < /dev/null
RC=$?
if [ "$RC" -eq 0 ]; then
    pass "F1 --with-verify-hooks exit 0"
else
    fail "F1 --with-verify-hooks exit ${RC} (log tail: $(tail -5 "$LOG_F1" | tr '\n' ' '))"
fi

SET_F1="${PROJ_F1}/.claude/settings.json"
if [ -f "$SET_F1" ] && jq empty "$SET_F1" >/dev/null 2>&1; then
    pass "F1 settings.json 유효 JSON"
    CMDS_F1="$(settings_commands "$SET_F1")"
    if printf '%s\n' "$CMDS_F1" | grep -q 'stop-self-check\.sh'; then
        pass "F1 Stop -> stop-self-check.sh 배선"
    else
        fail "F1 stop-self-check.sh 미배선"
    fi
    if printf '%s\n' "$CMDS_F1" | grep -q 'build-checker\.sh'; then
        pass "F1 PostToolUse -> build-checker.sh 배선"
    else
        fail "F1 build-checker.sh 미배선"
    fi
    if jq -e '(.hooks.Stop | length) > 0' "$SET_F1" >/dev/null 2>&1; then
        pass "F1 Stop 이벤트 배열 존재"
    else
        fail "F1 Stop 이벤트 배열 없음"
    fi
    if jq -e 'any(.hooks.PostToolUse[]?; .matcher == "Edit|Write")' "$SET_F1" >/dev/null 2>&1; then
        pass "F1 PostToolUse matcher \"Edit|Write\" 존재"
    else
        fail "F1 PostToolUse matcher \"Edit|Write\" 없음"
    fi
    # build-checker.sh 항목이 보존되는지 (조각 확장이 기존 배선을 지우지 않았는지)
    if printf '%s\n' "$CMDS_F1" | grep -q 'build-checker\.sh'; then
        pass "F1 verify-hooks 항목(build-checker.sh) 보존"
    else
        fail "F1 verify-hooks 항목(build-checker.sh) 소실"
    fi
    if printf '%s\n' "$CMDS_F1" | grep -q 'pm2-hooks\|service-health-check\.sh'; then
        fail "F1 --with-verify-hooks 인데 pm2 훅이 배선됨 (플래그 누수)"
    else
        pass "F1 pm2 훅 미배선 (플래그 분리 유지)"
    fi
else
    fail "F1 settings.json 없음 또는 파싱 불가: ${SET_F1}"
fi

HASH_F1_BEFORE="$(file_hash "$SET_F1")"
BAKS_F1_BEFORE="$(count_baks_in "$HOME_F1" "$PROJ_F1")"
LOG_F1B="${SANDBOX_ROOT}/run-f1b.log"
HOME="$HOME_F1" bash "$INSTALL" --with-verify-hooks --project "$PROJ_F1" \
    > "$LOG_F1B" 2>&1 < /dev/null
RC=$?
HASH_F1_AFTER="$(file_hash "$SET_F1")"
BAKS_F1_AFTER="$(count_baks_in "$HOME_F1" "$PROJ_F1")"
if [ "$RC" -eq 0 ]; then
    pass "F1 재실행 exit 0"
else
    fail "F1 재실행 exit ${RC} (log tail: $(tail -5 "$LOG_F1B" | tr '\n' ' '))"
fi
if [ -n "$HASH_F1_BEFORE" ] && [ "$HASH_F1_BEFORE" = "$HASH_F1_AFTER" ]; then
    pass "F1 재실행 settings.json 불변 (멱등)"
else
    fail "F1 재실행에 settings.json 변경됨 (before=${HASH_F1_BEFORE}, after=${HASH_F1_AFTER})"
fi
if [ "$BAKS_F1_AFTER" -eq "$BAKS_F1_BEFORE" ]; then
    pass "F1 재실행 신규 .bak 0개 (before=${BAKS_F1_BEFORE}, after=${BAKS_F1_AFTER})"
else
    fail "F1 재실행에 신규 .bak 생성됨 (before=${BAKS_F1_BEFORE}, after=${BAKS_F1_AFTER})"
fi

# ── F2: --with-pm2 → pm2-hooks 병합 ────────────────────────────────────
HOME_F2="${SANDBOX_ROOT}/home-f2"
PROJ_F2="${SANDBOX_ROOT}/proj-f2"
mkdir -p "$HOME_F2" "$PROJ_F2"
LOG_F2="${SANDBOX_ROOT}/run-f2.log"
HOME="$HOME_F2" bash "$INSTALL" --with-pm2 --project "$PROJ_F2" \
    > "$LOG_F2" 2>&1 < /dev/null
RC=$?
if [ "$RC" -eq 0 ]; then
    pass "F2 --with-pm2 exit 0"
else
    fail "F2 --with-pm2 exit ${RC} (log tail: $(tail -5 "$LOG_F2" | tr '\n' ' '))"
fi

SET_F2="${PROJ_F2}/.claude/settings.json"
if [ -f "$SET_F2" ] && jq empty "$SET_F2" >/dev/null 2>&1; then
    pass "F2 settings.json 유효 JSON"
    CMDS_F2="$(settings_commands "$SET_F2")"
    if printf '%s\n' "$CMDS_F2" | grep -q 'post-tool-failure\.sh'; then
        pass "F2 PostToolUseFailure -> post-tool-failure.sh 배선"
    else
        fail "F2 post-tool-failure.sh 미배선"
    fi
    if printf '%s\n' "$CMDS_F2" | grep -q 'service-health-check\.sh'; then
        pass "F2 Stop -> service-health-check.sh 배선"
    else
        fail "F2 service-health-check.sh 미배선"
    fi
    if jq -e '(.hooks.PostToolUseFailure | length) > 0' "$SET_F2" >/dev/null 2>&1; then
        pass "F2 PostToolUseFailure 이벤트 배열 존재"
    else
        fail "F2 PostToolUseFailure 이벤트 배열 없음"
    fi
    if printf '%s\n' "$CMDS_F2" | grep -q 'stop-self-check\.sh'; then
        fail "F2 --with-pm2 인데 verify-hooks 훅이 배선됨 (플래그 누수)"
    else
        pass "F2 verify-hooks 훅 미배선 (플래그 분리 유지)"
    fi
else
    fail "F2 settings.json 없음 또는 파싱 불가: ${SET_F2}"
fi

HASH_F2_BEFORE="$(file_hash "$SET_F2")"
BAKS_F2_BEFORE="$(count_baks_in "$HOME_F2" "$PROJ_F2")"
LOG_F2B="${SANDBOX_ROOT}/run-f2b.log"
HOME="$HOME_F2" bash "$INSTALL" --with-pm2 --project "$PROJ_F2" \
    > "$LOG_F2B" 2>&1 < /dev/null
RC=$?
HASH_F2_AFTER="$(file_hash "$SET_F2")"
BAKS_F2_AFTER="$(count_baks_in "$HOME_F2" "$PROJ_F2")"
if [ "$RC" -eq 0 ]; then
    pass "F2 재실행 exit 0"
else
    fail "F2 재실행 exit ${RC} (log tail: $(tail -5 "$LOG_F2B" | tr '\n' ' '))"
fi
if [ -n "$HASH_F2_BEFORE" ] && [ "$HASH_F2_BEFORE" = "$HASH_F2_AFTER" ]; then
    pass "F2 재실행 settings.json 불변 (멱등)"
else
    fail "F2 재실행에 settings.json 변경됨 (before=${HASH_F2_BEFORE}, after=${HASH_F2_AFTER})"
fi
if [ "$BAKS_F2_AFTER" -eq "$BAKS_F2_BEFORE" ]; then
    pass "F2 재실행 신규 .bak 0개 (before=${BAKS_F2_BEFORE}, after=${BAKS_F2_AFTER})"
else
    fail "F2 재실행에 신규 .bak 생성됨 (before=${BAKS_F2_BEFORE}, after=${BAKS_F2_AFTER})"
fi

echo ""
echo "=== Test G: skillOverrides 안전망 (글로벌 settings 조각) ==="

# 기대값은 조각 파일에서 읽는다 — 개수를 하드코딩하면 조각이 갱신될 때마다 드리프트한다.
FRAG_SO="${REPO_DIR}/global/settings-fragments/skill-overrides.json"
EXPECTED_SO="$(jq -r '.skillOverrides | length' "$FRAG_SO" 2>/dev/null)"

HOME_G="${SANDBOX_ROOT}/home-g"
mkdir -p "$HOME_G"
LOG_G="${SANDBOX_ROOT}/run-g.log"
HOME="$HOME_G" bash "$INSTALL" --global-only > "$LOG_G" 2>&1 < /dev/null
RC=$?
if [ "$RC" -eq 0 ]; then
    pass "G0 --global-only exit 0"
else
    fail "G0 --global-only exit ${RC} (log tail: $(tail -5 "$LOG_G" | tr '\n' ' '))"
fi

SET_G="${HOME_G}/.claude/settings.json"
ACTUAL_SO="$(jq -r '.skillOverrides | length' "$SET_G" 2>/dev/null || echo 0)"
if [ -n "$EXPECTED_SO" ] && [ "$ACTUAL_SO" = "$EXPECTED_SO" ]; then
    pass "G0 skillOverrides ${ACTUAL_SO}개 설치됨"
else
    fail "G0 skillOverrides 개수 불일치 (기대=${EXPECTED_SO}, 실제=${ACTUAL_SO})"
fi

# ── G1: 안전망 발화 — 키가 통째로 사라진 상태에서 복원되는가 ──────────────
# 설치 후 존재 확인(G0)만으로는 부족하다: 조각이 아예 동작하지 않아도 통과한다.
# 유실 상태를 직접 만들어, 안전망이 실제로 발화하는지를 본다.
jq 'del(.skillOverrides) | .model = "sentinel-model"' "$SET_G" > "${SET_G}.tmp" \
    && mv "${SET_G}.tmp" "$SET_G"
HOME="$HOME_G" bash "$INSTALL" --global-only > "$LOG_G" 2>&1 < /dev/null
RC=$?
RESTORED_SO="$(jq -r '.skillOverrides | length' "$SET_G" 2>/dev/null || echo 0)"
if [ "$RC" -eq 0 ] && [ "$RESTORED_SO" = "$EXPECTED_SO" ]; then
    pass "G1 유실 후 재실행에 skillOverrides ${RESTORED_SO}개 복원"
else
    fail "G1 복원 실패 (exit=${RC}, 복원=${RESTORED_SO}, 기대=${EXPECTED_SO})"
fi
if [ "$(jq -r '.model' "$SET_G" 2>/dev/null)" = "sentinel-model" ]; then
    pass "G1 복원이 다른 최상위 키(model)를 건드리지 않음"
else
    fail "G1 복원이 기존 model 키를 덮어씀"
fi

# ── G2: 사용자 편집 우선 — 조각이 살아 있는 값을 덮어쓰지 않는가 ──────────
jq '.skillOverrides = {"user-owned-skill":"off"}' "$SET_G" > "${SET_G}.tmp" \
    && mv "${SET_G}.tmp" "$SET_G"
HOME="$HOME_G" bash "$INSTALL" --global-only > "$LOG_G" 2>&1 < /dev/null
RC=$?
if [ "$RC" -eq 0 ] \
   && [ "$(jq -rc '.skillOverrides' "$SET_G" 2>/dev/null)" = '{"user-owned-skill":"off"}' ]; then
    pass "G2 기존 skillOverrides 값 우선 (사용자 편집 불변)"
else
    fail "G2 사용자 값이 덮어써짐: $(jq -rc '.skillOverrides' "$SET_G" 2>/dev/null)"
fi

# ── G3: 멱등 — 무변경 재실행에 신규 .bak 이 생기지 않는가 ─────────────────
BAKS_G_BEFORE="$(count_baks_in "$HOME_G")"
HOME="$HOME_G" bash "$INSTALL" --global-only > "$LOG_G" 2>&1 < /dev/null
RC=$?
BAKS_G_AFTER="$(count_baks_in "$HOME_G")"
if [ "$RC" -eq 0 ] && [ "$BAKS_G_AFTER" -eq "$BAKS_G_BEFORE" ]; then
    pass "G3 재실행 신규 .bak 0개 (before=${BAKS_G_BEFORE}, after=${BAKS_G_AFTER})"
else
    fail "G3 재실행에 신규 .bak 생성됨 (exit=${RC}, before=${BAKS_G_BEFORE}, after=${BAKS_G_AFTER})"
fi

# ============================================================================
# Test H: 글로벌 에이전트 배포 (global/agents → ~/.claude/agents)
#
# cli-orchestration 스킬이 cli-orchestrator/cli-worker 를 전제로 쓰는데 페이로드에
# 없어서, 설치만 하면 스킬이 존재하지 않는 에이전트를 가리켰다.
#
# 폭발 반경 주의: ~/.claude/agents/ 는 조언자 번들도 쓴다(architect/worker/analyzer/
# researcher). 번들은 manifest 에 기록하지 않으므로 스윕 대상이 아니지만, 그 불변식이
# 깨지면 재설치가 남의 에이전트를 지운다 — H3 가 그 경계를 지킨다.
# ============================================================================
echo "=== Test H: 글로벌 에이전트 배포 ==="
HOME_H="${SANDBOX_ROOT}/home-h"
mkdir -p "$HOME_H"
LOG_H="${SANDBOX_ROOT}/run-h.log"
HOME="$HOME_H" bash "$INSTALL" --global-only > "$LOG_H" 2>&1 < /dev/null
RC=$?
if [ "$RC" -eq 0 ]; then
    pass "H0 글로벌 설치 exit 0"
else
    fail "H0 글로벌 설치 exit ${RC} (log tail: $(tail -5 "$LOG_H" | tr '\n' ' '))"
fi

H_MISSING=""
for a in cli-orchestrator cli-worker; do
    [ -f "${HOME_H}/.claude/agents/${a}.md" ] || H_MISSING="${H_MISSING} ${a}"
done
if [ -z "$H_MISSING" ]; then
    pass "H1 페이로드 에이전트 설치됨 (cli-orchestrator, cli-worker)"
else
    fail "H1 설치되지 않은 에이전트:${H_MISSING}"
fi

# manifest 에 기록되어야 uninstall/스윕이 소유를 안다
H_UNTRACKED=""
for a in cli-orchestrator cli-worker; do
    grep -q "^agents/${a}\.md	" "${HOME_H}/.claude/.manifest" 2>/dev/null \
        || H_UNTRACKED="${H_UNTRACKED} ${a}"
done
if [ -z "$H_UNTRACKED" ]; then
    pass "H2 manifest 에 소유 기록됨"
else
    fail "H2 manifest 미기록 (uninstall 이 남긴다):${H_UNTRACKED}"
fi

# 남의 에이전트 불가침: 번들이 만든 것처럼 manifest 밖 파일을 두고 재설치해도 살아야 한다.
printf -- '---\nname: architect\n---\nuser owned\n' > "${HOME_H}/.claude/agents/architect.md"
HOME="$HOME_H" bash "$INSTALL" --global-only > "${SANDBOX_ROOT}/run-h2.log" 2>&1 < /dev/null
if [ -f "${HOME_H}/.claude/agents/architect.md" ]; then
    pass "H3 manifest 밖 에이전트는 재설치에도 보존 (번들 architect/worker 불가침)"
else
    fail "H3 재설치가 manifest 밖 에이전트를 삭제함 — 조언자 번들 산출물 파괴"
fi

# 헛돎 방지: 설치기가 실제로 이 파일들을 소유하는지 — uninstall 로 확인
HOME="$HOME_H" bash "$INSTALL" --uninstall --global-only \
    > "${SANDBOX_ROOT}/run-h3.log" 2>&1 < /dev/null
if [ ! -f "${HOME_H}/.claude/agents/cli-worker.md" ]; then
    pass "H4 uninstall 이 설치기 소유 에이전트를 제거"
else
    fail "H4 uninstall 후에도 cli-worker.md 잔존 — 소유 추적 실패"
fi
if [ -f "${HOME_H}/.claude/agents/architect.md" ]; then
    pass "H5 uninstall 이 manifest 밖 에이전트는 보존"
else
    fail "H5 uninstall 이 사용자/번들 에이전트를 삭제함"
fi

# H6: 페이로드에서 빠진 에이전트가 라이브에서도 사라지는가.
#
# manifest_source_candidates 에 agents/* 매핑을 넣은 **유일한 이유**가 이것이다.
# H1~H5 는 매핑이 죽어 있어도 전부 통과한다(설치·소유·불가침·제거만 본다) —
# 매핑이 없으면 sweep_removed_assets 가 후보를 못 찾아 `|| continue` 로 넘어가고,
# 스테일 에이전트가 영구히 남는다. 그 무동작을 관측 가능하게 만드는 검사다.
echo "=== Test H6: 업스트림에서 삭제된 에이전트 스윕 ==="
FIX_H="${SANDBOX_ROOT}/h6-fix"
HOME_H6="${SANDBOX_ROOT}/home-h6"
mkdir -p "$HOME_H6"
# 픽스처 복사를 인라인으로 둔다 — test-install.sh 는 helpers.sh 를 소싱하지 않고
# 자체 pass/fail 을 쓴다. 소싱하면 카운터 정의가 충돌한다.
mkdir -p "$FIX_H"
( cd "$REPO_DIR" && find . -name .git -prune -o -type d -print 2>/dev/null ) | \
    while IFS= read -r d; do mkdir -p "${FIX_H}/${d}"; done
( cd "$REPO_DIR" && find . -name .git -prune -o -type f -print 2>/dev/null ) | \
    while IFS= read -r f; do cp -p "${REPO_DIR}/${f}" "${FIX_H}/${f}"; done
HOME="$HOME_H6" bash "${FIX_H}/install.sh" --global-only \
    > "${SANDBOX_ROOT}/run-h6a.log" 2>&1 < /dev/null
H6_READY=false
if [ -f "${HOME_H6}/.claude/agents/cli-worker.md" ] && \
   [ -f "${HOME_H6}/.claude/agents/cli-orchestrator.md" ]; then
    pass "H6-0 두 에이전트 설치됨 (사보타주 전제 성립)"
    H6_READY=true
else
    fail "H6-0 사전 설치 실패 — H6 이 헛돈다"
fi
# 전제가 깨진 채로 아래를 돌리면 "설치된 적 없어서 없다"가 "스윕이 지웠다"로 둔갑한다.
# 실제로 관측한 오탐이다(helpers 미소싱으로 픽스처 복사가 no-op 이었을 때 H6-1 이 통과).
if ! $H6_READY; then
    fail "H6-1 전제 미성립으로 검증 불가 (H6-0 참조)"
    fail "H6-2 전제 미성립으로 검증 불가 (H6-0 참조)"
else
    # 업스트림에서 하나만 제거하고 재설치
    rm -f "${FIX_H}/global/agents/cli-worker.md"
    HOME="$HOME_H6" bash "${FIX_H}/install.sh" --global-only \
        > "${SANDBOX_ROOT}/run-h6b.log" 2>&1 < /dev/null
    RC_H6=$?
    # 재설치가 스윕만 하고 도중에 죽어도 파일은 사라진다 — exit code 를 함께 요구한다.
    if [ "$RC_H6" -ne 0 ]; then
        fail "H6-1 재설치가 exit ${RC_H6} (log tail: $(tail -3 "${SANDBOX_ROOT}/run-h6b.log" | tr '\n' ' '))"
    elif [ ! -f "${HOME_H6}/.claude/agents/cli-worker.md" ]; then
        pass "H6-1 업스트림에서 사라진 에이전트가 라이브에서도 제거됨 (exit 0)"
    else
        fail "H6-1 스테일 에이전트 잔존 — agents/* 스윕 매핑이 동작하지 않음"
    fi
    if [ -f "${HOME_H6}/.claude/agents/cli-orchestrator.md" ]; then
        pass "H6-2 남아 있는 에이전트는 보존 (과잉 삭제 없음)"
    else
        fail "H6-2 스윕이 여전히 배포 중인 에이전트까지 삭제함"
    fi
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
