#!/bin/bash
set -uo pipefail
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "${REPO_DIR}/tests/helpers.sh"
init_sandbox

# L1: 사용자 파일 보존 (CLAUDE.md)
echo "=== L1: user file preserved through reinstall ==="
HOME="${SANDBOX_ROOT}/home" bash "${REPO_DIR}/install.sh" --full --project "${SANDBOX_ROOT}/proj1" >/dev/null 2>&1
CLAUDE="${SANDBOX_ROOT}/proj1/CLAUDE.md"
printf 'USER EDIT\n' >> "$CLAUDE"
HOME="${SANDBOX_ROOT}/home" bash "${REPO_DIR}/install.sh" --full --project "${SANDBOX_ROOT}/proj1" >/dev/null 2>&1
if grep -q 'USER EDIT' "$CLAUDE"; then
    pass "L1 user edit preserved"
else
    fail "L1 user edit lost"
fi

# L2: 멱등성 (같은 설치 2회 → .bak 증가 없음)
echo "=== L2: idempotent — no new .bak on 2nd run ==="
BAKS_1="$(count_baks_in "${SANDBOX_ROOT}/home" "${SANDBOX_ROOT}/proj1")"
HOME="${SANDBOX_ROOT}/home" bash "${REPO_DIR}/install.sh" --full --project "${SANDBOX_ROOT}/proj1" >/dev/null 2>&1
BAKS_2="$(count_baks_in "${SANDBOX_ROOT}/home" "${SANDBOX_ROOT}/proj1")"
if [ "$BAKS_2" -eq "$BAKS_1" ]; then
    pass "L2 no new .bak (${BAKS_1} → ${BAKS_2})"
else
    fail "L2 new .bak created (${BAKS_1} → ${BAKS_2})"
fi

# L3: user-modified 파일 보존 (manifest hash != current hash)
echo "=== L3: user-modified file preserved ==="
HOME="${SANDBOX_ROOT}/home3" bash "${REPO_DIR}/install.sh" --global-only >/dev/null 2>&1
RULE_FILE="${SANDBOX_ROOT}/home3/.claude/rules/golden-principles.md"
ORIG_CONTENT="$(cat "$RULE_FILE")"
printf '\nUSER EDIT AT END\n' >> "$RULE_FILE"
HOME="${SANDBOX_ROOT}/home3" bash "${REPO_DIR}/install.sh" --global-only >/dev/null 2>&1
if grep -q 'USER EDIT AT END' "$RULE_FILE"; then
    pass "L3 user-modified rule preserved"
else
    fail "L3 user-modified rule overwritten"
fi

# L4: manifest 없는 보수적 migration (첫 실행 시 manifest 생성)
echo "=== L4: conservative migration (no manifest yet) ==="
HOME="${SANDBOX_ROOT}/home4" bash "${REPO_DIR}/install.sh" --global-only >/dev/null 2>&1
MANIFEST="${SANDBOX_ROOT}/home4/.claude/.manifest"
if [ -f "$MANIFEST" ]; then
    pass "L4 manifest created on first install"
else
    fail "L4 manifest not created"
fi
# 그 다음 파일 수정 → 재설치 → 보존 확인
RULE_FILE="${SANDBOX_ROOT}/home4/.claude/rules/golden-principles.md"
printf '\nL4 USER EDIT\n' >> "$RULE_FILE"
HOME="${SANDBOX_ROOT}/home4" bash "${REPO_DIR}/install.sh" --global-only >/dev/null 2>&1
if grep -q 'L4 USER EDIT' "$RULE_FILE"; then
    pass "L4 user edit after migration preserved"
else
    fail "L4 user edit after migration lost"
fi

# L5: managed-dir 사용자 파일 보존 (디렉터리 단위)
echo "=== L5: managed-dir user files preserved ==="
HOME="${SANDBOX_ROOT}/home5" bash "${REPO_DIR}/install.sh" --global-only >/dev/null 2>&1
SKILLS_DIR="${SANDBOX_ROOT}/home5/.claude/skills"
if [ -d "$SKILLS_DIR" ]; then
    # 사용자 파일 추가
    mkdir -p "$SKILLS_DIR/custom-skill"
    printf 'user content\n' > "$SKILLS_DIR/custom-skill/user.md"
    HOME="${SANDBOX_ROOT}/home5" bash "${REPO_DIR}/install.sh" --global-only >/dev/null 2>&1
    if [ -f "$SKILLS_DIR/custom-skill/user.md" ] && grep -q 'user content' "$SKILLS_DIR/custom-skill/user.md"; then
        pass "L5 managed-dir user files preserved"
    else
        fail "L5 managed-dir user files lost"
    fi
else
    skip "L5 skills dir not created"
fi

# L6: managed-dir stale 정리 — installer 소유·미변경 파일만 제거한다.
#
# install_managed_dir 은 스킬 1개당 1회 호출되므로 관할(prefix)은
# "skills/<skill-name>/" 이다. 따라서 stale 파일은 "실제로 관리되는 디렉터리
# 안"에 있어야 하고, manifest 해시는 그 파일의 실제 해시여야 한다(가짜 해시는
# 정의상 '사용자 수정' 으로 분류되어 보존이 정답이 된다).
echo "=== L6: managed-dir stale owned removed / user files preserved ==="
HOME="${SANDBOX_ROOT}/home6" bash "${REPO_DIR}/install.sh" --global-only >/dev/null 2>&1
SKILLS_DIR="${SANDBOX_ROOT}/home6/.claude/skills"
MANIFEST6="${SANDBOX_ROOT}/home6/.claude/.manifest"
OWNED_SKILL="${SKILLS_DIR}/cli-orchestration/SKILL.md"

# 검증의 검증: 관리 디렉터리가 실제로 채워졌는지 먼저 확인한다.
# (디렉터리가 비어 있으면 아래 보존/삭제 주장이 전부 헛돈다)
if [ -f "$OWNED_SKILL" ] && [ -f "$MANIFEST6" ]; then
    pass "L6-0 관리 스킬 디렉터리가 실제로 설치됨 (cli-orchestration/SKILL.md)"

    STALE6="${SKILLS_DIR}/cli-orchestration/stale-file.md"
    USERADD6="${SKILLS_DIR}/cli-orchestration/my-notes.md"
    USERMOD6="${SKILLS_DIR}/cli-orchestration/SKILL.md"

    # (1) installer 소유 stale: 실제 해시로 manifest 에 기록 → 제거 대상
    printf 'owned stale content\n' > "$STALE6"
    printf 'skills/cli-orchestration/stale-file.md\t%s\n' "$(file_hash "$STALE6")" >> "$MANIFEST6"
    # (2) 사용자가 추가한 파일 (manifest 미기록) → 보존 대상
    printf 'my own notes\n' > "$USERADD6"
    # (3) installer 소유였으나 사용자가 수정한 파일 → 보존 대상
    printf '\nL6 USER EDIT\n' >> "$USERMOD6"

    HOME="${SANDBOX_ROOT}/home6" bash "${REPO_DIR}/install.sh" --global-only >/dev/null 2>&1

    if [ ! -e "$STALE6" ]; then
        pass "L6-1 stale owned 파일 제거됨 (cli-orchestration/stale-file.md)"
    else
        fail "L6-1 stale owned 파일이 잔존함: ${STALE6}"
    fi
    if [ -f "$USERADD6" ] && grep -q 'my own notes' "$USERADD6"; then
        pass "L6-2 사용자 추가 파일 보존됨 (cli-orchestration/my-notes.md)"
    else
        fail "L6-2 사용자 추가 파일이 삭제됨: ${USERADD6}"
    fi
    if grep -q 'L6 USER EDIT' "$USERMOD6"; then
        pass "L6-3 사용자 수정 파일 보존됨 (cli-orchestration/SKILL.md)"
    else
        fail "L6-3 사용자 수정 파일이 덮어써짐: ${USERMOD6}"
    fi
    if ! grep -q 'skills/cli-orchestration/stale-file.md' "$MANIFEST6"; then
        pass "L6-4 manifest 에서 stale 항목 제거됨"
    else
        fail "L6-4 manifest 에 stale 항목이 남음"
    fi
else
    fail "L6-0 관리 스킬 디렉터리 미설치 — 테스트 헛돎 (${OWNED_SKILL})"
fi

# L7: --uninstall — installer 소유 파일/훅만 제거하고 사용자 것은 전부 보존한다.
#
# 계약:
#   - 파일: manifest 기록 해시 == 현재 해시인 것만 제거 (사용자 수정/추가는 보존)
#   - settings.json: installer 가 소유한 hooks/permissions identity 만 제거
#     (사용자 훅·사용자 allow·알 수 없는 최상위 키는 불변)
#   - 빈 디렉토리만 정리, 재실행 멱등
echo "=== L7: --uninstall removes owned, preserves user ==="
HOME7="${SANDBOX_ROOT}/home7"
PROJ7="${SANDBOX_ROOT}/proj7"
HOME="$HOME7" bash "${REPO_DIR}/install.sh" --full --project "$PROJ7" >/dev/null 2>&1

# 주의: `install.sh --help | grep -q` 로 쓰면 안 된다. grep -q 는 첫 매치에서 즉시
# 종료하므로 생산자가 SIGPIPE 로 죽고, `set -o pipefail` 이 그걸 파이프라인 실패로
# 바꾼다 — 도움말이 길어질수록 잘 터지는 경합이다(실측으로 밟았다). 먼저 받아 둔다.
HELP_OUT="$(bash "${REPO_DIR}/install.sh" --help 2>&1)"
if printf '%s\n' "$HELP_OUT" | grep -q '\-\-uninstall'; then
    pass "L7-0 --uninstall 플래그가 도움말에 존재"
else
    fail "L7-0 --uninstall 플래그 없음"
fi

OWNED_RULE="${HOME7}/.claude/rules/golden-principles.md"
OWNED_SKILL7="${HOME7}/.claude/skills/cli-orchestration/SKILL.md"
OWNED_AGENT="$(find "${PROJ7}/.claude/agents" -name '*.md' -type f 2>/dev/null | head -1)"
SET7="${PROJ7}/.claude/settings.json"

if [ -f "$OWNED_RULE" ] && [ -f "$OWNED_SKILL7" ] && [ -n "$OWNED_AGENT" ] && [ -f "$SET7" ]; then
    pass "L7-1 설치 산출물 존재 (제거 대상이 실재함 — 테스트 헛돎 방지)"

    # 사용자 자산 심기
    USER_ADD7="${HOME7}/.claude/skills/cli-orchestration/keep-me.md"
    printf 'keep me\n' > "$USER_ADD7"
    USER_MOD7="${HOME7}/.claude/rules/security.md"
    printf '\nL7 USER EDIT\n' >> "$USER_MOD7"
    # 사용자 훅 + 사용자 allow + 사용자 최상위 키를 settings.json 에 추가
    jq '.hooks.PreToolUse += [{"matcher":"Bash","hooks":[{"type":"command","command":"echo USER_HOOK_L7"}]}]
        | .permissions.allow += ["Bash(user-rule-l7 *)"]
        | .myOwnKey = "keep-this"' "$SET7" > "${SET7}.tmp" && mv "${SET7}.tmp" "$SET7"
    INSTALLER_HOOK_BEFORE="$(settings_commands "$SET7" | grep -c 'cli-orchestrator\|guardrail\|python3' || true)"
    # 검사할 allow 규칙은 조각 파일에서 읽는다. 하드코딩하면 조각이 개정될 때
    # "존재한 적 없는 문자열의 부재"를 검사하게 되어 무조건 통과한다(실제로 그랬다).
    OWNED_ALLOW="$(jq -r '.permissions.allow[0]' \
        "${REPO_DIR}/project/settings-fragments/cli-orchestration.json" 2>/dev/null)"
    if [ -n "$OWNED_ALLOW" ] && [ "$OWNED_ALLOW" != "null" ] && \
       jq -e --arg r "$OWNED_ALLOW" '(.permissions.allow // []) | index($r)' "$SET7" >/dev/null 2>&1; then
        pass "L7-1b 제거 대상 allow 규칙이 제거 전에 실재함: ${OWNED_ALLOW} (테스트 헛돎 방지)"
    else
        fail "L7-1b 조각의 allow 규칙이 설치되지 않음 (읽은 값='${OWNED_ALLOW}') — 아래 제거 검증이 헛돔"
    fi

    # --uninstall --dry-run 은 아무것도 지우면 안 된다 (README 가 문서화한 계약)
    SNAP7_D1="${SANDBOX_ROOT}/snap7d1.txt"; SNAP7_D2="${SANDBOX_ROOT}/snap7d2.txt"
    snapshot_tree "$HOME7" > "$SNAP7_D1"
    HOME="$HOME7" bash "${REPO_DIR}/install.sh" --uninstall --dry-run --project "$PROJ7" \
        > "${SANDBOX_ROOT}/uninstall-dry.log" 2>&1
    RC7D=$?
    snapshot_tree "$HOME7" > "$SNAP7_D2"
    if [ "$RC7D" -eq 0 ] && diff -q "$SNAP7_D1" "$SNAP7_D2" >/dev/null 2>&1; then
        pass "L7-D --uninstall --dry-run 은 쓰기 0건 (exit 0, 스냅샷 불변)"
    else
        fail "L7-D --uninstall --dry-run 이 파일을 건드림 (exit ${RC7D}, diff: $(diff "$SNAP7_D1" "$SNAP7_D2" | head -2 | tr '\n' ' '))"
    fi
    if grep -q 'DRY RUN' "${SANDBOX_ROOT}/uninstall-dry.log"; then
        pass "L7-D2 --uninstall --dry-run 이 제거 예정 항목을 출력함 (헛돎 방지)"
    else
        fail "L7-D2 --uninstall --dry-run 출력에 '[DRY RUN] Would remove' 없음"
    fi

    HOME="$HOME7" bash "${REPO_DIR}/install.sh" --uninstall --project "$PROJ7" \
        > "${SANDBOX_ROOT}/uninstall1.log" 2>&1
    RC7=$?
    if [ "$RC7" -eq 0 ]; then
        pass "L7-2 --uninstall exit 0"
    else
        fail "L7-2 --uninstall exit ${RC7} (log: $(tail -3 "${SANDBOX_ROOT}/uninstall1.log" | tr '\n' ' '))"
    fi

    if [ ! -e "$OWNED_RULE" ] && [ ! -e "$OWNED_SKILL7" ] && [ ! -e "$OWNED_AGENT" ]; then
        pass "L7-3 installer 소유·미변경 파일 제거됨 (rules/ skills/ agents/)"
    else
        fail "L7-3 installer 소유 파일 잔존: $(ls "$OWNED_RULE" "$OWNED_SKILL7" "$OWNED_AGENT" 2>/dev/null | tr '\n' ' ')"
    fi
    if [ -f "$USER_ADD7" ] && grep -q 'keep me' "$USER_ADD7"; then
        pass "L7-4 사용자 추가 파일 보존됨"
    else
        fail "L7-4 사용자 추가 파일이 삭제됨: ${USER_ADD7}"
    fi
    if [ -f "$USER_MOD7" ] && grep -q 'L7 USER EDIT' "$USER_MOD7"; then
        pass "L7-5 사용자 수정 파일 보존됨"
    else
        fail "L7-5 사용자 수정 파일이 삭제/덮어써짐: ${USER_MOD7}"
    fi
    if [ -f "${PROJ7}/CLAUDE.md" ]; then
        pass "L7-6 사용자 소유 파일(CLAUDE.md) 보존됨"
    else
        fail "L7-6 사용자 소유 파일(CLAUDE.md) 삭제됨"
    fi

    # settings.json 검증
    if [ -f "$SET7" ] && jq empty "$SET7" >/dev/null 2>&1; then
        pass "L7-7 settings.json 이 유효 JSON 으로 남아 있음"
        CMDS7="$(settings_commands "$SET7")"
        if printf '%s\n' "$CMDS7" | grep -q 'USER_HOOK_L7'; then
            pass "L7-8 사용자 훅 보존됨"
        else
            fail "L7-8 사용자 훅이 제거됨"
        fi
        if [ "$(jq -r '.myOwnKey // "MISSING"' "$SET7")" = "keep-this" ]; then
            pass "L7-9 알 수 없는 최상위 키 보존됨"
        else
            fail "L7-9 알 수 없는 최상위 키가 유실됨"
        fi
        INSTALLER_HOOK_AFTER="$(settings_commands "$SET7" | grep -c 'cli-orchestrator\|guardrail\|python3' || true)"
        if [ "$INSTALLER_HOOK_BEFORE" -gt 0 ] && [ "$INSTALLER_HOOK_AFTER" -eq 0 ]; then
            pass "L7-10 installer 소유 훅 제거됨 (${INSTALLER_HOOK_BEFORE} → ${INSTALLER_HOOK_AFTER})"
        else
            fail "L7-10 installer 소유 훅 제거 실패 (${INSTALLER_HOOK_BEFORE} → ${INSTALLER_HOOK_AFTER})"
        fi
        if jq -e --arg r "$OWNED_ALLOW" '(.permissions.allow // []) | index($r)' "$SET7" >/dev/null 2>&1; then
            fail "L7-11 installer 소유 permissions.allow 항목이 잔존: ${OWNED_ALLOW}"
        else
            pass "L7-11 installer 소유 permissions.allow 제거됨 (${OWNED_ALLOW})"
        fi
        # 제거의 반대편: 사용자가 직접 넣은 allow 는 살아 있어야 한다
        if jq -e '(.permissions.allow // []) | index("Bash(user-rule-l7 *)")' "$SET7" >/dev/null 2>&1; then
            pass "L7-11b 사용자 allow 규칙 보존됨"
        else
            fail "L7-11b 사용자 allow 규칙이 함께 제거됨: $(jq -rc '.permissions.allow' "$SET7")"
        fi
    else
        fail "L7-7 settings.json 이 없거나 파싱 불가"
    fi

    # 멱등성: 두 번째 --uninstall 은 아무것도 바꾸지 않는다
    SNAP7_A="${SANDBOX_ROOT}/snap7a.txt"; SNAP7_B="${SANDBOX_ROOT}/snap7b.txt"
    snapshot_tree "$HOME7" > "$SNAP7_A"
    HOME="$HOME7" bash "${REPO_DIR}/install.sh" --uninstall --project "$PROJ7" \
        > "${SANDBOX_ROOT}/uninstall2.log" 2>&1
    RC7B=$?
    snapshot_tree "$HOME7" > "$SNAP7_B"
    if [ "$RC7B" -eq 0 ] && diff -q "$SNAP7_A" "$SNAP7_B" >/dev/null 2>&1; then
        pass "L7-12 --uninstall 재실행 멱등 (exit 0, HOME 스냅샷 불변)"
    else
        fail "L7-12 --uninstall 재실행이 멱등하지 않음 (exit ${RC7B}, diff: $(diff "$SNAP7_A" "$SNAP7_B" | head -3 | tr '\n' ' '))"
    fi
else
    fail "L7-1 설치 산출물 부재 — 테스트 헛돎"
fi


# L8: 원자적 롤백 — 설치 도중 실패/시그널이 나면 이번 실행이 바꾼 모든 것을
#     정확히 이전 상태로 되돌리고 부분 설치를 남기지 않는다.
#
# 거짓 양성(mutation 전에 죽어서 "복원됨"처럼 보이는 것) 방지 설계:
#   사보타주 스크립트는 죽기 직전에 "그 시점의 목적지 파일"을 증거로 복사해
#   둔다. 그 사본에 UPSTREAM 변경이 들어 있어야만(= 실제 변형이 이미 일어난
#   뒤에 실패했음이 증명되어야만) 복원 주장을 검사한다.
echo "=== L8: atomic rollback (forced failure / SIGINT) ==="
# 케이스마다 fixture 리포를 새로 뜬다. 공유하면 앞 케이스가 심은 "업스트림
# 변경"이 뒤 케이스의 기준 설치에 이미 들어가 버려, 아무것도 안 바뀌었는데
# "복원됨"으로 통과하는 거짓 양성이 생긴다(실측으로 확인하고 분리했다).
FIX=""
SABOTAGE=""

l8_setup_baseline() {
    # $1 = HOME, $2 = PROJECT — 정상 설치로 기준 상태를 만든다
    HOME="$1" bash "${FIX}/install.sh" --project "$2" >/dev/null 2>&1
}

l8_apply_upstream_change() {
    # 재설치가 "반드시 무언가를 바꾸도록" 소스를 변경한다:
    #   (a) 기존 관리 파일 내용 변경 → dst 덮어쓰기 + .bak 생성
    #   (b) 새 관리 파일 추가       → dst 신규 생성
    printf '\nL8 UPSTREAM CHANGE\n' >> "${FIX}/global/rules/golden-principles.md"
    printf 'brand new rule\n' > "${FIX}/global/rules/zz-l8-new-rule.md"
    # 프로젝트 쪽도 반드시 바뀌게 한다 — 안 그러면 "PROJECT 복원됨" 주장이
    # 아무것도 안 바뀐 상태를 비교하는 헛 검증이 된다.
    printf 'brand new agent\n' > "${FIX}/project/agents/zz-l8-new-agent.md"
    local pa
    pa="$(find "${FIX}/project/agents" -name '*.md' -type f ! -name 'zz-l8-*' | head -1)"
    [ -n "$pa" ] && printf '\nL8 UPSTREAM AGENT CHANGE\n' >> "$pa"
}

l8_write_sabotage() {
    # $1 = 증거 파일 경로, $2 = 실패 방식(exit|signal), $3 = 설치기 PID 파일
    cat > "$SABOTAGE" <<SABEOF
#!/bin/bash
# L8 사보타주: 이 시점의 목적지 파일을 증거로 남긴 뒤 설치를 실패시킨다.
cp "\$HOME/.claude/rules/golden-principles.md" "$1" 2>/dev/null || true
cp "\$HOME/.claude/rules/zz-l8-new-rule.md" "$1.new" 2>/dev/null || true
SABEOF
    if [ "$2" = "signal" ]; then
        # $PPID 로 쏘지 않는다. 위임 체인이 한 단계라도 달라지면 그 PID 가
        # **테스트 스위트 자신**이 될 수 있고, 그러면 스위트가 중간에 죽어
        # 뒤 케이스(L9 이후)의 결과가 아예 나오지 않는다.
        # 테스트가 설치기 자식 PID 를 파일에 적어 두고, 사보타주는 그 PID 에만 쏜다.
        cat >> "$SABOTAGE" <<SIGEOF
_t=0
while [ ! -s "$3" ] && [ "\$_t" -lt 50 ]; do sleep 0.1; _t=\$((_t + 1)); done
_target="\$(cat "$3" 2>/dev/null)"
case "\$_target" in
  ''|*[!0-9]*) echo "sabotage: installer pid 파일 없음/이상: \$_target" >&2; exit 1 ;;
esac
kill -INT "\$_target"
# 실제 Ctrl-C 는 포그라운드 그룹 전체에 간다. 자신도 INT 로 죽어야 부모 bash 가
# 대기 중 받은 SIGINT 를 폐기하지 않고 트랩을 실행한다(비대화형 bash 규칙).
kill -INT \$\$
sleep 5
exit 0
SIGEOF
    else
        printf 'exit 1\n' >> "$SABOTAGE"
    fi
}

l8_case() {
    # $1 = 케이스명, $2 = 실패 방식(exit|signal), $3 = 라벨 접두
    local name="$1" mode="$2" tag="$3"
    local H="${SANDBOX_ROOT}/${name}-home"
    local P="${SANDBOX_ROOT}/${name}-proj"
    local EV="${SANDBOX_ROOT}/${name}-evidence.txt"

    FIX="${SANDBOX_ROOT}/${name}-fix"
    make_fixture_repo "$FIX"
    SABOTAGE="${FIX}/docs/Claude code system setup/install.sh"

    l8_setup_baseline "$H" "$P"
    if [ ! -f "${H}/.claude/rules/golden-principles.md" ]; then
        fail "${tag}-0 기준 설치 실패 — 테스트 헛돎"
        return 0
    fi
    local SNAP_H="${SANDBOX_ROOT}/${name}-h-before.txt"
    local SNAP_P="${SANDBOX_ROOT}/${name}-p-before.txt"
    snapshot_tree "$H" > "$SNAP_H"
    snapshot_tree "$P" > "$SNAP_P"

    l8_apply_upstream_change
    local PIDF="${SANDBOX_ROOT}/${name}-installer.pid"
    rm -f "$PIDF"
    l8_write_sabotage "$EV" "$mode" "$PIDF"

    local RC
    if [ "$mode" = "signal" ]; then
        # 포그라운드로 돌린다 — 백그라운드 실행은 SIGINT 를 SIG_IGN 으로 상속시켜
        # 설치기가 신호를 무시해 버린다(실측). 런처가 자기 PID 를 기록한 뒤
        # exec 로 설치기가 되므로, 그 PID 는 정확히 설치기 프로세스다.
        # 스위트 자신의 PID 는 어디에도 쓰이지 않는다.
        local LAUNCH="${SANDBOX_ROOT}/${name}-launch.sh"
        cat > "$LAUNCH" <<LAUNCHEOF
#!/bin/bash
printf '%s' "\$\$" > "$PIDF"
exec bash "${FIX}/install.sh" --project "$P"
LAUNCHEOF
        HOME="$H" bash "$LAUNCH" > "${SANDBOX_ROOT}/${name}.log" 2>&1
        RC=$?
    else
        HOME="$H" bash "${FIX}/install.sh" --project "$P" \
            > "${SANDBOX_ROOT}/${name}.log" 2>&1
        RC=$?
    fi

    # (1) 실패로 끝났는가
    if [ "$RC" -ne 0 ]; then
        pass "${tag}-1 설치가 실패로 종료됨 (exit ${RC})"
    else
        fail "${tag}-1 설치가 exit 0 으로 끝남 — 사보타주가 동작하지 않음"
    fi
    # (2) 실패 "이전에" 진짜 변형이 있었는가 (거짓 양성 차단)
    if [ -f "$EV" ] && grep -q 'L8 UPSTREAM CHANGE' "$EV"; then
        pass "${tag}-2 실패 시점에 이미 실제 변형이 적용돼 있었음 (기존 파일 갱신)"
    else
        fail "${tag}-2 변형 증거 없음 — mutation 전에 죽었으므로 복원 주장이 무의미"
    fi
    if [ -f "${EV}.new" ] && grep -q 'brand new rule' "${EV}.new"; then
        pass "${tag}-3 실패 시점에 신규 파일도 생성돼 있었음"
    else
        fail "${tag}-3 신규 파일 생성 증거 없음"
    fi
    # (3) 정확한 원상 복구
    local SNAP_H2="${SANDBOX_ROOT}/${name}-h-after.txt"
    local SNAP_P2="${SANDBOX_ROOT}/${name}-p-after.txt"
    snapshot_tree "$H" > "$SNAP_H2"
    snapshot_tree "$P" > "$SNAP_P2"
    if diff -u "$SNAP_H" "$SNAP_H2" > "${SANDBOX_ROOT}/${name}-h.diff" 2>&1; then
        pass "${tag}-4 HOME 이 실행 전 상태로 정확히 복원됨"
    else
        fail "${tag}-4 HOME 복원 불일치: $(grep -c '^[+-][^+-]' "${SANDBOX_ROOT}/${name}-h.diff" | tr -d ' ')줄 (예: $(grep '^[+-][^+-]' "${SANDBOX_ROOT}/${name}-h.diff" | head -2 | tr '\n' ' '))"
    fi
    if diff -u "$SNAP_P" "$SNAP_P2" > "${SANDBOX_ROOT}/${name}-p.diff" 2>&1; then
        pass "${tag}-5 PROJECT 가 실행 전 상태로 정확히 복원됨"
    else
        fail "${tag}-5 PROJECT 복원 불일치: $(grep -c '^[+-][^+-]' "${SANDBOX_ROOT}/${name}-p.diff" | tr -d ' ')줄 (예: $(grep '^[+-][^+-]' "${SANDBOX_ROOT}/${name}-p.diff" | head -2 | tr '\n' ' '))"
    fi
    # (4) 부분 설치 잔여물 0 — 신규 파일이 남아 있으면 안 된다
    if [ ! -e "${H}/.claude/rules/zz-l8-new-rule.md" ] && \
       [ ! -e "${P}/.claude/agents/zz-l8-new-agent.md" ]; then
        pass "${tag}-6 이번 실행이 만든 신규 파일이 남지 않음 (글로벌+프로젝트)"
    else
        fail "${tag}-6 부분 설치 잔여: $(ls "${H}/.claude/rules/zz-l8-new-rule.md" "${P}/.claude/agents/zz-l8-new-agent.md" 2>/dev/null | tr '\n' ' ')"
    fi
}

l8_case "l8fail"  "exit"   "L8A"
l8_case "l8sig"   "signal" "L8B"

# 시그널 주입이 스위트 자신을 죽이지 않았음을 명시적으로 고정한다.
# (죽으면 이 줄에 영영 도달하지 못하므로 "결과 없음" 과 "통과" 가 구분된다.)
pass "L8S-SURVIVED 시그널 케이스 이후에도 스위트가 계속 실행됨"


# L9: 대용량 저널 롤백.
#
# L8 은 파일 1~2개만 바꾸고 실패하므로 저널이 짧다. 저널이 길 때(수십~수백 건)
# 복원 루프가 끝까지 도는지는 별개 문제다 — install.sh 는 `set -euo pipefail` 이고
# 그 설정은 트랩 안에서도 살아 있어서, 복원 루프 중간의 한 번의 non-zero 가
# 트랩을 중단시키면 "절반만 롤백된" 트리가 남는다(롤백 없음보다 나쁘다).
# 그래서 모든 관리 파일을 한꺼번에 바꿔 저널을 최대로 키운 뒤 실패시킨다.
echo "=== L9: rollback with a large journal ==="
FIX9="${SANDBOX_ROOT}/l9-fix"
H9="${SANDBOX_ROOT}/l9-home"
P9="${SANDBOX_ROOT}/l9-proj"
make_fixture_repo "$FIX9"
HOME="$H9" bash "${FIX9}/install.sh" --full --project "$P9" >/dev/null 2>&1

S9A="${SANDBOX_ROOT}/l9-a.txt"; S9B="${SANDBOX_ROOT}/l9-b.txt"
S9PA="${SANDBOX_ROOT}/l9-pa.txt"; S9PB="${SANDBOX_ROOT}/l9-pb.txt"
snapshot_tree "$H9" > "$S9A"
snapshot_tree "$P9" > "$S9PA"

# 관리 대상 .md 를 전부 바꿔 "모든 관리 파일이 갱신되는" 상황을 만든다
CHANGED9=0
while IFS= read -r f; do
    printf '\nL9 BULK CHANGE\n' >> "$f"
    CHANGED9=$((CHANGED9 + 1))
done < <(find "${FIX9}/global/rules" "${FIX9}/global/skills" \
              "${FIX9}/project/agents" "${FIX9}/project/commands" \
              "${FIX9}/project/skills" -type f -name '*.md' 2>/dev/null)
# 위임 단계에서 실패시킨다 — 그 시점엔 위 변경이 전부 적용된 뒤다
printf '#!/bin/bash\nexit 1\n' > "${FIX9}/docs/Claude code system setup/install.sh"

HOME="$H9" bash "${FIX9}/install.sh" --full --project "$P9" \
    > "${SANDBOX_ROOT}/l9.log" 2>&1
RC9=$?
snapshot_tree "$H9" > "$S9B"
snapshot_tree "$P9" > "$S9PB"

if [ "$CHANGED9" -ge 20 ]; then
    pass "L9-0 대량 변경 준비됨 (소스 ${CHANGED9}개 파일 수정 — 테스트 헛돎 방지)"
else
    fail "L9-0 변경된 소스가 ${CHANGED9}개뿐 — 저널이 크지 않아 검증이 무의미"
fi
if [ "$RC9" -ne 0 ]; then
    pass "L9-1 설치가 실패로 종료됨 (exit ${RC9})"
else
    fail "L9-1 강제 실패인데 exit 0"
fi
# 저널 크기를 로그에서 직접 읽는다 — "많이 되돌렸다"를 주장이 아니라 수치로
JOURNAL_N="$(sed -n 's/.*ROLLBACK 완료: \([0-9][0-9]*\)건.*/\1/p' "${SANDBOX_ROOT}/l9.log" | tail -1)"
if [ -n "$JOURNAL_N" ] && [ "$JOURNAL_N" -ge 20 ]; then
    pass "L9-2 롤백이 대용량 저널을 처리함 (${JOURNAL_N}건 복원)"
else
    fail "L9-2 저널이 작거나 롤백 로그 없음 (N='${JOURNAL_N}')"
fi
if diff -u "$S9A" "$S9B" > "${SANDBOX_ROOT}/l9-h.diff" 2>&1; then
    pass "L9-3 대용량 롤백 후 HOME 이 바이트 단위로 정확히 복원됨"
else
    fail "L9-3 HOME 부분 복원됨: $(grep -c '^[+-][^+-]' "${SANDBOX_ROOT}/l9-h.diff" | tr -d ' ')줄 (예: $(grep '^[+-][^+-]' "${SANDBOX_ROOT}/l9-h.diff" | head -2 | tr '\n' ' '))"
fi
if diff -u "$S9PA" "$S9PB" > "${SANDBOX_ROOT}/l9-p.diff" 2>&1; then
    pass "L9-4 대용량 롤백 후 PROJECT 가 바이트 단위로 정확히 복원됨"
else
    fail "L9-4 PROJECT 부분 복원됨: $(grep -c '^[+-][^+-]' "${SANDBOX_ROOT}/l9-p.diff" | tr -d ' ')줄 (예: $(grep '^[+-][^+-]' "${SANDBOX_ROOT}/l9-p.diff" | head -2 | tr '\n' ' '))"
fi


# L10: 경로에 glob 메타문자([ ] * ?)가 있어도 소유권 추적이 깨지지 않아야 한다.
#
# `${var#$pattern}` 의 우변은 **패턴**이다. HOME 이나 리포 경로에 대괄호가 있으면
# 접두 제거가 실패해 manifest 에 절대경로가 기록되고(→ uninstall 이 아무것도 못
# 지움), 리포 경로에 있으면 파일이 한 개도 설치되지 않은 채 exit 0 이 된다.
echo "=== L10: glob metacharacters in HOME / repo path ==="
H10="${SANDBOX_ROOT}/home[1]"
P10="${SANDBOX_ROOT}/proj[p]"
FIX10="${SANDBOX_ROOT}/fix[x]"
make_fixture_repo "$FIX10"

HOME="$H10" bash "${FIX10}/install.sh" --full --project "$P10" \
    > "${SANDBOX_ROOT}/l10-install.log" 2>&1
RC10=$?
MF10="${H10}/.claude/.manifest"

if [ "$RC10" -eq 0 ]; then
    pass "L10-1 대괄호 경로에서 install exit 0"
else
    fail "L10-1 대괄호 경로 install exit ${RC10} (log: $(tail -3 "${SANDBOX_ROOT}/l10-install.log" | tr '\n' ' '))"
fi

L10_SKILLS="$(find "${H10}/.claude/skills" -type f 2>/dev/null | wc -l | tr -d ' ')"
if [ "$L10_SKILLS" -gt 0 ]; then
    pass "L10-2 대괄호 리포 경로에서도 글로벌 스킬이 설치됨 (${L10_SKILLS}개)"
else
    fail "L10-2 스킬이 0개 설치됨 — 접두 제거 실패로 전부 스킵됨"
fi

if [ -f "$MF10" ]; then
    L10_ABS="$(grep -c '^/' "$MF10" 2>/dev/null | tr -d ' ')"
    L10_TOTAL="$(wc -l < "$MF10" | tr -d ' ')"
    if [ "$L10_ABS" -eq 0 ]; then
        pass "L10-3 manifest 에 절대경로 항목 0개 (총 ${L10_TOTAL}개 전부 상대경로)"
    else
        fail "L10-3 manifest ${L10_TOTAL}개 중 ${L10_ABS}개가 절대경로: $(head -1 "$MF10")"
    fi
    # 스킬도 실제로 소유 등록되어야 한다 (등록이 지워지면 uninstall 이 못 지운다)
    if grep -q '^skills/' "$MF10"; then
        pass "L10-4 스킬 파일이 manifest 에 소유 등록됨"
    else
        fail "L10-4 스킬이 manifest 에 없음 — stale 정리가 자기 기록을 지웠다"
    fi
else
    fail "L10-3 manifest 없음"
fi

# 재실행 멱등
L10_BAK_A="$(count_baks_in "$H10" "$P10")"
L10_SNAP_A="${SANDBOX_ROOT}/l10-a.txt"; L10_SNAP_B="${SANDBOX_ROOT}/l10-b.txt"
snapshot_tree "$H10" > "$L10_SNAP_A"
HOME="$H10" bash "${FIX10}/install.sh" --full --project "$P10" >/dev/null 2>&1
snapshot_tree "$H10" > "$L10_SNAP_B"
L10_BAK_B="$(count_baks_in "$H10" "$P10")"
if [ "$L10_BAK_A" -eq "$L10_BAK_B" ] && diff -q "$L10_SNAP_A" "$L10_SNAP_B" >/dev/null 2>&1; then
    pass "L10-5 대괄호 경로 재설치 멱등 (.bak ${L10_BAK_A} → ${L10_BAK_B}, 스냅샷 불변)"
else
    fail "L10-5 대괄호 경로 재설치가 멱등하지 않음 (.bak ${L10_BAK_A} → ${L10_BAK_B})"
fi

# uninstall 이 실제로 소유 파일을 지우는지
L10_USER="${H10}/.claude/skills/cli-orchestration/user-keep.md"
printf 'user keeps this\n' > "$L10_USER"
L10_OWNED="${H10}/.claude/rules/golden-principles.md"
HOME="$H10" bash "${FIX10}/install.sh" --uninstall --project "$P10" \
    > "${SANDBOX_ROOT}/l10-uninstall.log" 2>&1
RC10U=$?
if [ "$RC10U" -eq 0 ] && [ ! -e "$L10_OWNED" ]; then
    pass "L10-6 대괄호 경로에서 uninstall 이 소유 파일을 제거함"
else
    fail "L10-6 uninstall 이 소유 파일을 못 지움 (exit ${RC10U}, 잔존=$([ -e "$L10_OWNED" ] && echo yes || echo no))"
fi
if [ -f "$L10_USER" ]; then
    pass "L10-7 대괄호 경로에서 사용자 파일 보존됨"
else
    fail "L10-7 사용자 파일이 삭제됨"
fi

# L11: 통째로 제거된 자산의 stale 정리.
#
# 디렉토리 단위 stale 정리는 "지금 열거되는 디렉토리 안"만 훑는다. 스킬 디렉토리
# 하나가 업스트림에서 통째로 사라지거나 rules 파일이 삭제되면 그 디렉토리/파일은
# 애초에 방문되지 않아 목적지와 manifest 양쪽에 영원히 남는다.
# README/install.sh 는 "installer 소유 stale 은 삭제된다"고 약속하므로 회귀다.
echo "=== L11: wholly removed upstream assets are swept ==="
FIX11="${SANDBOX_ROOT}/l11-fix"
H11="${SANDBOX_ROOT}/l11-home"
P11="${SANDBOX_ROOT}/l11-proj"
make_fixture_repo "$FIX11"
HOME="$H11" bash "${FIX11}/install.sh" --full --project "$P11" >/dev/null 2>&1

SKILL11="${H11}/.claude/skills/external-memory/SKILL.md"
RULE11="${H11}/.claude/rules/golden-principles.md"
AGENT11_SRC="$(find "${FIX11}/project/agents" -name '*.md' -type f | head -1)"
AGENT11="${P11}/.claude/agents/$(basename "$AGENT11_SRC")"
MF11="${H11}/.claude/.manifest"
MF11P="${P11}/.manifest"

if [ -f "$SKILL11" ] && [ -f "$RULE11" ] && [ -f "$AGENT11" ]; then
    pass "L11-0 제거 대상 자산이 실재함 (테스트 헛돎 방지)"

    # 사용자가 수정한 파일을, 통째로 사라질 스킬 디렉토리 안에 심는다 → 보존되어야 함
    USERMOD11="${H11}/.claude/skills/external-memory/SKILL.md"
    USERADD11="${H11}/.claude/skills/external-memory/my-note.md"
    printf 'my own note\n' > "$USERADD11"
    # installer 가 설치했던 파일을 사용자가 **수정**한 경우도 함께 고정한다.
    # 수정하지 않고 두면 "사용자 추가 파일" 한 가지만 검증돼, 스윕이 사용자 편집본을
    # 지우는 회귀가 그대로 통과한다.
    printf '\nUSER EDIT MARKER\n' >> "$USERMOD11"

    # 업스트림에서 통째 제거
    rm -rf "${FIX11}/global/skills/external-memory"
    rm -f  "${FIX11}/global/rules/golden-principles.md"
    rm -f  "$AGENT11_SRC"

    HOME="$H11" bash "${FIX11}/install.sh" --full --project "$P11" \
        > "${SANDBOX_ROOT}/l11.log" 2>&1
    RC11=$?
    if [ "$RC11" -eq 0 ]; then
        pass "L11-1 제거 후 재설치 exit 0"
    else
        fail "L11-1 재설치 exit ${RC11} (log: $(tail -3 "${SANDBOX_ROOT}/l11.log" | tr '\n' ' '))"
    fi
    # SKILL11 == USERMOD11 이다. 사용자가 수정했으므로 업스트림에서 사라졌더라도
    # 보존이 정답이다(소유권 모델). 삭제 검증은 아래 RULE11/AGENT11 이 담당한다.
    if [ -f "$USERMOD11" ] && grep -q 'USER EDIT MARKER' "$USERMOD11"; then
        pass "L11-2 통째 제거된 스킬 안의 '사용자 수정' 파일은 보존됨"
    else
        fail "L11-2 스윕이 사용자 수정 파일을 삭제함: ${USERMOD11}"
    fi
    if [ ! -e "$RULE11" ]; then
        pass "L11-3 제거된 rules 파일이 삭제됨 (golden-principles.md)"
    else
        fail "L11-3 제거된 rules 파일이 잔존: ${RULE11}"
    fi
    if [ ! -e "$AGENT11" ]; then
        pass "L11-4 제거된 프로젝트 에이전트가 삭제됨"
    else
        fail "L11-4 제거된 프로젝트 에이전트가 잔존: ${AGENT11}"
    fi
    # 실제로 **삭제된** 자산의 기록만 사라져야 한다. 사용자가 수정해 보존한 파일의
    # 기록은 남는 것이 정답이다 — 지우면 다음 실행에서 소유권 불명이 되어 판정이
    # 흔들리고 재실행 멱등이 깨진다(install.sh 의 stale 정리 주석과 같은 계약).
    if ! grep -q 'rules/golden-principles.md' "$MF11" 2>/dev/null && \
       ! grep -q 'skills/external-memory/my-note.md' "$MF11" 2>/dev/null; then
        pass "L11-5 manifest 에서 실제 삭제된 자산 항목이 사라짐"
        if grep -q 'skills/external-memory/SKILL.md' "$MF11" 2>/dev/null; then
            pass "L11-5b 보존된 사용자 수정본의 소유 기록은 유지 (재실행 멱등)"
        else
            fail "L11-5b 보존했는데 기록만 지워 소유권 불명이 됨"
        fi
    else
        fail "L11-5 manifest 에 삭제된 자산 항목이 남음: $(grep -e 'rules/golden-principles.md' -e 'skills/external-memory/my-note.md' "$MF11" | head -2 | tr '\n' ' ')"
    fi
    if [ -f "$USERADD11" ] && grep -q 'my own note' "$USERADD11"; then
        pass "L11-6 사용자 추가 파일은 스윕되지 않음 (디렉토리도 유지)"
    else
        fail "L11-6 사용자 추가 파일이 삭제됨: ${USERADD11}"
    fi
    # 아직 소스에 있는 자산은 건드리면 안 된다
    if [ -f "${H11}/.claude/skills/cli-orchestration/SKILL.md" ] && \
       [ -f "${H11}/.claude/rules/security.md" ]; then
        pass "L11-7 소스에 남아 있는 자산은 그대로 유지됨"
    else
        fail "L11-7 스윕이 살아 있는 자산까지 삭제함"
    fi
    # 스윕 후 재실행 멱등
    L11_A="${SANDBOX_ROOT}/l11-a.txt"; L11_B="${SANDBOX_ROOT}/l11-b.txt"
    snapshot_tree "$H11" > "$L11_A"
    HOME="$H11" bash "${FIX11}/install.sh" --full --project "$P11" >/dev/null 2>&1
    snapshot_tree "$H11" > "$L11_B"
    if diff -q "$L11_A" "$L11_B" >/dev/null 2>&1; then
        pass "L11-8 스윕 후 재실행 멱등"
    else
        fail "L11-8 스윕 후 재실행이 멱등하지 않음: $(diff "$L11_A" "$L11_B" | head -2 | tr '\n' ' ')"
    fi

    # --global-only 경로에서도 글로벌 스윕이 동작해야 한다 (프로젝트 manifest 는
    # 없고 PROJECT_DIR 도 비어 있는 상태 — 빈 루트로 스윕이 불리면 안 된다).
    H11G="${SANDBOX_ROOT}/l11g-home"
    FIX11G="${SANDBOX_ROOT}/l11g-fix"
    make_fixture_repo "$FIX11G"
    HOME="$H11G" bash "${FIX11G}/install.sh" --global-only >/dev/null 2>&1
    G_RULE="${H11G}/.claude/rules/golden-principles.md"
    if [ -f "$G_RULE" ]; then
        rm -rf "${FIX11G}/global/skills/external-memory"
        rm -f  "${FIX11G}/global/rules/golden-principles.md"
        HOME="$H11G" bash "${FIX11G}/install.sh" --global-only \
            > "${SANDBOX_ROOT}/l11g.log" 2>&1
        RC11G=$?
        if [ "$RC11G" -eq 0 ] && [ ! -e "$G_RULE" ] && \
           [ ! -e "${H11G}/.claude/skills/external-memory/SKILL.md" ]; then
            pass "L11-10 --global-only 에서도 업스트림 제거 자산이 스윕됨"
        else
            fail "L11-10 --global-only 스윕 실패 (exit ${RC11G}, rule 잔존=$([ -e "$G_RULE" ] && echo yes || echo no))"
        fi
    else
        fail "L11-10 --global-only 기준 설치 실패 — 테스트 헛돎"
    fi

    # 스윕 기준이 "이번 실행에서 건드렸는가" 가 아니라 "소스가 남아 있는가" 인 이유:
    # 옵트인 자산(examples)은 이번에 요청하지 않아도 업스트림에 그대로 있으므로
    # 지워지면 안 된다. --full(=examples 포함) 다음 --with-examples 없는 재실행.
    EX11="$(find "${P11}/.claude/skills" -maxdepth 1 -type d 2>/dev/null | tail -1)"
    EX11_AGENT="$(find "${FIX11}/examples/agents" -name '*.md' -type f 2>/dev/null | head -1)"
    if [ -n "$EX11_AGENT" ]; then
        EX11_DST="${P11}/.claude/agents/$(basename "$EX11_AGENT")"
        if [ -f "$EX11_DST" ]; then
            HOME="$H11" bash "${FIX11}/install.sh" --project "$P11" >/dev/null 2>&1
            if [ -f "$EX11_DST" ]; then
                pass "L11-9 옵트인(examples) 자산은 미요청 재실행에도 보존됨"
            else
                fail "L11-9 examples 자산이 스윕됨: ${EX11_DST}"
            fi
        else
            fail "L11-9 examples 에이전트가 애초에 설치되지 않음 — 테스트 헛돎"
        fi
    else
        skip "L11-9 examples/agents 소스 없음"
    fi
else
    fail "L11-0 제거 대상 자산 부재 — 테스트 헛돎"
fi

# L12: 레거시 .claude/MODELS.md 정리.
#
# 이전 버전의 docs 설치기는 .claude/MODELS.md 를 설치했다. 지금은 설치하지
# 않지만, 이미 깔린 사본은 아무도 지우지 않아 남는다 — 그 내용이 stale 한
# 모델 ID·CLI 버전을 SSOT 라고 주장하기 때문에 그냥 두면 오히려 해롭다.
# 정책: 과거에 배포된 내용과 해시가 일치하면(= 사용자가 손대지 않았으면) 제거,
#       다르면(= 사용자가 편집했으면) 보존하고 안내만 한다.
echo "=== L12: legacy .claude/MODELS.md cleanup ==="
DOCS_INSTALLER="${REPO_DIR}/docs/Claude code system setup/install.sh"
LEGACY_BODY='# MODELS.md — 모델/CLI 단일 진실 소스(SSOT)

> 이 파일이 이 프로젝트의 모델 ID·CLI 버전 SSOT 입니다.
> 다른 문서·설정은 값을 중복 기재하지 말고 **이 파일을 참조**하세요.

| 역할 | 모델 | API ID |
|------|------|--------|
| 플래그십 (복잡 추론, 1M 변형 존재) | Opus 4.8 | `claude-opus-4-8` |
| 최상위 추론 / 장기 에이전트 | Fable 5 | `claude-fable-5` |
| 코딩 / 에이전트 메인 (1M) | Sonnet 5 | `claude-sonnet-5` |
| 경량 / 빠른 반복 (200K) | Haiku 4.5 | `claude-haiku-4-5-20251001` |

- Claude Code CLI: `v2.1.210`'

# (a) 손대지 않은 레거시 파일 → 제거되어야 한다
H12A="${SANDBOX_ROOT}/l12a-home"
P12A="${SANDBOX_ROOT}/l12a-proj"
mkdir -p "${P12A}/.claude"
printf '%s\n' "$LEGACY_BODY" > "${P12A}/.claude/MODELS.md"
HOME="$H12A" bash "$DOCS_INSTALLER" "$P12A" > "${SANDBOX_ROOT}/l12a.log" 2>&1
RC12A=$?
if [ "$RC12A" -eq 0 ]; then
    pass "L12-0 docs 설치기 exit 0"
else
    fail "L12-0 docs 설치기 exit ${RC12A} (log: $(tail -3 "${SANDBOX_ROOT}/l12a.log" | tr '\n' ' '))"
fi
if [ ! -e "${P12A}/.claude/MODELS.md" ]; then
    pass "L12-1 손대지 않은 레거시 MODELS.md 가 제거됨"
else
    fail "L12-1 레거시 MODELS.md 가 잔존: ${P12A}/.claude/MODELS.md"
fi

# (b) 사용자가 편집한 파일 → 보존되어야 한다 + 안내가 나와야 한다
H12B="${SANDBOX_ROOT}/l12b-home"
P12B="${SANDBOX_ROOT}/l12b-proj"
mkdir -p "${P12B}/.claude"
printf '%s\n\nMY OWN NOTES\n' "$LEGACY_BODY" > "${P12B}/.claude/MODELS.md"
HOME="$H12B" bash "$DOCS_INSTALLER" "$P12B" > "${SANDBOX_ROOT}/l12b.log" 2>&1
if [ -f "${P12B}/.claude/MODELS.md" ] && grep -q 'MY OWN NOTES' "${P12B}/.claude/MODELS.md"; then
    pass "L12-2 사용자가 편집한 MODELS.md 는 보존됨"
else
    fail "L12-2 사용자가 편집한 MODELS.md 가 삭제됨"
fi
# 안내는 "보존한 경우에만" 나와야 한다. 일반 안내문에도 MODELS.md 라는 낱말이
# 있으므로 전용 표지(LEGACY-MODELS-KEPT)로 구분한다 — 아니면 항상 통과한다.
if grep -q 'LEGACY-MODELS-KEPT' "${SANDBOX_ROOT}/l12b.log"; then
    pass "L12-3 보존 시 전용 수동삭제 안내가 출력됨"
else
    fail "L12-3 보존했는데 전용 안내가 없음 (사용자가 stale 파일을 모른 채 남김)"
fi
if ! grep -q 'LEGACY-MODELS-KEPT' "${SANDBOX_ROOT}/l12a.log"; then
    pass "L12-3b 자동 제거한 경우에는 보존 안내가 나오지 않음"
else
    fail "L12-3b 제거했는데 보존 안내가 출력됨 (안내가 무조건 나오는 중)"
fi

# (c) 애초에 없으면 아무 일도 없어야 한다 (멱등)
H12C="${SANDBOX_ROOT}/l12c-home"
P12C="${SANDBOX_ROOT}/l12c-proj"
HOME="$H12C" bash "$DOCS_INSTALLER" "$P12C" > "${SANDBOX_ROOT}/l12c.log" 2>&1
RC12C=$?
if [ "$RC12C" -eq 0 ] && [ ! -e "${P12C}/.claude/MODELS.md" ] && \
   ! grep -q 'LEGACY-MODELS-KEPT' "${SANDBOX_ROOT}/l12c.log"; then
    pass "L12-4 MODELS.md 가 없으면 새로 만들지도, 안내하지도, 실패하지도 않음"
else
    fail "L12-4 MODELS.md 부재 시 동작 이상 (exit ${RC12C})"
fi

# ============================================================================
# L13: 구버전(.settings-manifest 없음) 업그레이드 이주
#
# 구버전 설치기가 써 놓은 settings.json 에는 광범위 권한(Bash(npm *) 등)과 옛 guard
# 훅이 들어 있다. 새 설치기는 소유 기록이 없으면 그것들을 "우리 것이었다"고 판단할
# 근거가 없어 영원히 남긴다 — MERGE_LEGACY_REMOVALS 가 그 근거다.
# 주의: manifest 파일은 첫 조각 병합에서 생성되므로, 2번째 조각(cli-orchestration —
#       광범위 권한의 출처)이 이주에서 누락되지 않는지가 이 테스트의 핵심이다.
# ============================================================================
echo "=== L13: legacy upgrade (.settings-manifest 부재) ==="
H13="${SANDBOX_ROOT}/l13-home"
P13="${SANDBOX_ROOT}/l13-proj"
mkdir -p "$H13" "${P13}/.claude"

# 구버전 상태를 base 정체성 목록으로부터 재구성한다(하드코딩 금지 — 드리프트 방지).
python3 - "${REPO_DIR}/lib/legacy-identities.tsv" "${P13}/.claude/settings.json" <<'PY13'
import io, json, sys
src, dst = sys.argv[1], sys.argv[2]
WANT = ("guardrails.json", "cli-orchestration.json", "verification-hooks.json")
settings = {"hooks": {}, "permissions": {"allow": []}}
for line in io.open(src, encoding="utf-8"):
    line = line.rstrip("\n")
    if not line or line.startswith("#"):
        continue
    f = line.split("\t")
    if f[0] not in WANT:
        continue
    if f[1] == "hook":
        ev, mt, cmd = f[2], f[3], "\t".join(f[4:])
        arr = settings["hooks"].setdefault(ev, [])
        slot = None
        for e in arr:
            if e.get("matcher", "") == mt:
                slot = e
                break
        if slot is None:
            slot = {"matcher": mt, "hooks": []}
            arr.append(slot)
        slot["hooks"].append({"type": "command", "command": cmd})
    elif f[1] == "perm":
        settings["permissions"]["allow"].append(f[3])
# 사용자가 직접 넣은 항목 — 절대 사라지면 안 된다
settings["hooks"].setdefault("Stop", []).append(
    {"matcher": "", "hooks": [{"type": "command", "command": "user-legacy-cmd"}]})
settings["permissions"]["allow"].append("Bash(user-legacy-rule)")
settings["myUserKey"] = "keep-me"
io.open(dst, "w", encoding="utf-8").write(json.dumps(settings, indent=2, ensure_ascii=False) + "\n")
PY13

S13="${P13}/.claude/settings.json"
if [ ! -f "${P13}/.claude/.settings-manifest" ] && jq empty "$S13" 2>/dev/null; then
    pass "L13-0 구버전 fixture 준비 (.settings-manifest 없음)"
else
    fail "L13-0 fixture 준비 실패"
fi

HOME="$H13" bash "${REPO_DIR}/install.sh" --with-verify-hooks --project "$P13" \
    > "${SANDBOX_ROOT}/l13-1.log" 2>&1 < /dev/null
RC13=$?
if [ "$RC13" -eq 0 ]; then
    pass "L13-1 legacy 업그레이드 설치 exit 0"
else
    fail "L13-1 exit ${RC13}: $(tail -3 "${SANDBOX_ROOT}/l13-1.log" | tr '\n' ' ')"
fi

ALLOW13="$(jq -rc '.permissions.allow // []' "$S13")"
BROAD_LEFT=0
for r in 'Bash(npm *)' 'Bash(git *)' 'Bash(docker *)'; do
    case "$ALLOW13" in *"$r"*) BROAD_LEFT=$((BROAD_LEFT + 1)) ;; esac
done
if [ "$BROAD_LEFT" -eq 0 ]; then
    pass "L13-2 구버전 광범위 권한 3종 제거 (cli-orchestration = 2번째 조각)"
else
    fail "L13-2 광범위 권한 ${BROAD_LEFT}건 잔존: ${ALLOW13}"
fi

CMDS13="$(settings_commands "$S13")"
if printf '%s\n' "$CMDS13" | grep -q "bad=\['rm -rf /'"; then
    fail "L13-3 옛 guardrails 훅(부분문자열 매칭 버전) 잔존"
else
    pass "L13-3 옛 guardrails 훅 제거"
fi
if printf '%s\n' "$CMDS13" | grep -qE 'npx tsc --noEmit|npm run lint:fix'; then
    fail "L13-4 폐기된 Write(*.tsx) 훅 잔존"
else
    pass "L13-4 폐기된 Write(*.tsx) 훅 제거"
fi
if printf '%s\n' "$CMDS13" | grep -q 'GUARD_BASH'; then
    pass "L13-5 새 guardrails 훅 배선됨"
else
    fail "L13-5 새 guardrails 훅 미배선"
fi

# 사용자 것은 전부 보존
if printf '%s\n' "$CMDS13" | grep -q '^user-legacy-cmd$'; then
    pass "L13-6 사용자 hook 보존"
else
    fail "L13-6 사용자 hook 이 이주에 휩쓸려 삭제됨"
fi
case "$ALLOW13" in
    *'Bash(user-legacy-rule)'*) pass "L13-7 사용자 allow 보존" ;;
    *) fail "L13-7 사용자 allow 소실: ${ALLOW13}" ;;
esac
if [ "$(jq -r '.myUserKey // empty' "$S13")" = "keep-me" ]; then
    pass "L13-8 사용자 최상위 키 보존"
else
    fail "L13-8 사용자 최상위 키 소실"
fi

# 재실행 멱등
H13B="$(file_hash "$S13")"
HOME="$H13" bash "${REPO_DIR}/install.sh" --with-verify-hooks --project "$P13" \
    > "${SANDBOX_ROOT}/l13-2.log" 2>&1 < /dev/null
if [ "$H13B" = "$(file_hash "$S13")" ]; then
    pass "L13-9 이주 후 재실행 멱등 (settings.json 불변)"
else
    fail "L13-9 재실행에 settings.json 변경됨 (이주가 매번 반복됨)"
fi

# uninstall: 우리 것만 사라지고 사용자 것은 남는다
HOME="$H13" bash "${REPO_DIR}/install.sh" --uninstall --project "$P13" \
    > "${SANDBOX_ROOT}/l13-3.log" 2>&1 < /dev/null
CMDS13U="$(settings_commands "$S13")"
ALLOW13U="$(jq -rc '.permissions.allow // []' "$S13")"
if printf '%s\n' "$CMDS13U" | grep -q '^user-legacy-cmd$'; then
    pass "L13-10 uninstall 후 사용자 hook 보존"
else
    fail "L13-10 uninstall 이 사용자 hook 삭제"
fi
case "$ALLOW13U" in
    *'Bash(user-legacy-rule)'*) pass "L13-11 uninstall 후 사용자 allow 보존" ;;
    *) fail "L13-11 uninstall 이 사용자 allow 삭제: ${ALLOW13U}" ;;
esac
if printf '%s\n' "$CMDS13U" | grep -q 'GUARD_BASH'; then
    fail "L13-12 uninstall 이 installer 훅을 제거하지 못함"
else
    pass "L13-12 uninstall 이 installer 훅 제거"
fi

# ============================================================================
# L14: dev/ .gitkeep 은 installer 산출물 — manifest 에 기록되어 uninstall 로 사라져야
#      한다. 사용자가 먼저 만들어 둔 .gitkeep 은 건드리지 않는다(skip-if-exists).
# ============================================================================
echo "=== L14: dev/*/.gitkeep 소유권 ==="
H14="${SANDBOX_ROOT}/l14-home"
P14="${SANDBOX_ROOT}/l14-proj"
mkdir -p "$H14" "${P14}/dev/completed"
# 사용자가 먼저 만든 .gitkeep (내용 있음) — 보존 대상
printf 'user placeholder\n' > "${P14}/dev/completed/.gitkeep"

HOME="$H14" bash "${REPO_DIR}/install.sh" --project "$P14" \
    > "${SANDBOX_ROOT}/l14-1.log" 2>&1 < /dev/null
M14F="${P14}/.manifest"
if [ -f "${P14}/dev/active/.gitkeep" ]; then
    pass "L14-1 dev/active/.gitkeep 설치됨"
else
    fail "L14-1 dev/active/.gitkeep 미설치"
fi
if grep -q '^dev/active/\.gitkeep	' "$M14F" 2>/dev/null; then
    pass "L14-2 dev/active/.gitkeep 이 manifest 에 기록됨"
else
    fail "L14-2 manifest 에 기록 없음: $(grep -c . "$M14F" 2>/dev/null)줄"
fi
if grep -q '^dev/completed/\.gitkeep	' "$M14F" 2>/dev/null; then
    fail "L14-3 사용자가 먼저 만든 .gitkeep 을 소유로 기록함"
else
    pass "L14-3 사용자 선점 .gitkeep 은 비소유"
fi

HOME="$H14" bash "${REPO_DIR}/install.sh" --uninstall --project "$P14" \
    > "${SANDBOX_ROOT}/l14-2.log" 2>&1 < /dev/null
if [ ! -e "${P14}/dev/active/.gitkeep" ]; then
    pass "L14-4 uninstall 이 installer 소유 .gitkeep 제거"
else
    fail "L14-4 installer 소유 .gitkeep 잔존"
fi
if [ -f "${P14}/dev/completed/.gitkeep" ] && grep -q 'user placeholder' "${P14}/dev/completed/.gitkeep"; then
    pass "L14-5 사용자 .gitkeep 은 uninstall 후에도 보존"
else
    fail "L14-5 uninstall 이 사용자 .gitkeep 을 삭제"
fi
if [ ! -d "${P14}/dev/active" ]; then
    pass "L14-6 비게 된 dev/active 디렉토리 정리"
else
    fail "L14-6 빈 dev/active 디렉토리 잔존"
fi

# ============================================================================
# L15: 구버전 이주가 "현재도 배포 중인 identity" 까지 주장하면 안 된다
#
# base 와 현재 조각이 공유하는 identity(예: cli-orchestration 의 SubagentStop 훅)는
# 사용자가 독립적으로 직접 만들었을 수도 있다. 이주 목록에 넣어 소유로 주장하면
# --uninstall 이 사용자 항목을 지운다. 구분할 수 없으면 주장하지 않는다.
# ============================================================================
echo "=== L15: 이주 과잉 주장 금지 (공유 identity 보존) ==="
H15="${SANDBOX_ROOT}/l15-home"
P15="${SANDBOX_ROOT}/l15-proj"
mkdir -p "$H15" "${P15}/.claude"
cat > "${P15}/.claude/settings.json" <<'EOF'
{
  "hooks": {
    "SubagentStop": [
      { "matcher": "", "hooks": [ { "type": "command", "command": "echo 'Agent completed: $AGENT_NAME'" } ] }
    ]
  },
  "permissions": { "allow": ["Bash(npm *)", "Bash(git *)", "Bash(docker *)"] }
}
EOF
HOME="$H15" bash "${REPO_DIR}/install.sh" --project "$P15" \
    > "${SANDBOX_ROOT}/l15-1.log" 2>&1 < /dev/null
S15="${P15}/.claude/settings.json"
ALLOW15="$(jq -rc '.permissions.allow // []' "$S15")"
case "$ALLOW15" in
    *'Bash(npm *)'*|*'Bash(git *)'*) fail "L15-1 폐기된 광범위 권한 잔존: ${ALLOW15}" ;;
    *) pass "L15-1 폐기된 광범위 권한은 이주로 제거" ;;
esac
HOME="$H15" bash "${REPO_DIR}/install.sh" --uninstall --project "$P15" \
    > "${SANDBOX_ROOT}/l15-2.log" 2>&1 < /dev/null
if settings_commands "$S15" | grep -q "Agent completed"; then
    pass "L15-2 공유 identity(사용자 것일 수 있음)는 uninstall 후에도 보존"
else
    fail "L15-2 uninstall 이 공유 identity 를 삭제함 — 이주 목록 과잉 주장"
fi

# ============================================================================
# L16: 구버전 업그레이드에서 이미 있던 빈 .gitkeep 인수(adopt)
#
# base 438aaf9 설치기가 만든 dev/active/.gitkeep 은 이미 존재한다. 새 설치기가
# "새로 만들 때만" 기록하면 그 파일은 영원히 소유권 불명으로 남아 uninstall 이
# 자기 산출물을 남긴다. 내용이 비어 있으면(= installer 산출물과 바이트 동일)
# 잃을 사용자 데이터가 없으므로 안전하게 인수한다. 내용이 있으면 사용자 것이다.
# ============================================================================
echo "=== L16: 기존 빈 .gitkeep 인수 ==="
H16="${SANDBOX_ROOT}/l16-home"
P16="${SANDBOX_ROOT}/l16-proj"
mkdir -p "$H16" "${P16}/dev/active" "${P16}/dev/completed" "${P16}/dev/mine"
: > "${P16}/dev/active/.gitkeep"        # 구버전 설치기 산출물 (빈 파일)
: > "${P16}/dev/completed/.gitkeep"     # 구버전 설치기 산출물 (빈 파일)
printf 'user notes\n' > "${P16}/dev/mine/.gitkeep"   # 사용자 내용 — 건드리면 안 됨

HOME="$H16" bash "${REPO_DIR}/install.sh" --project "$P16" \
    > "${SANDBOX_ROOT}/l16-1.log" 2>&1 < /dev/null
M16="${P16}/.manifest"
if grep -q '^dev/active/\.gitkeep	' "$M16" 2>/dev/null && \
   grep -q '^dev/completed/\.gitkeep	' "$M16" 2>/dev/null; then
    pass "L16-1 기존 빈 .gitkeep 2종을 소유로 인수"
else
    fail "L16-1 기존 .gitkeep 이 소유권 불명으로 남음 (uninstall 이 산출물을 남긴다)"
fi
if grep -q 'dev/mine/\.gitkeep' "$M16" 2>/dev/null; then
    fail "L16-2 내용 있는 사용자 .gitkeep 을 인수함"
else
    pass "L16-2 내용 있는 사용자 .gitkeep 은 비소유"
fi
# 인수는 파일을 바꾸지 않는다 + 재실행 멱등
H16A="$(file_hash "$M16")"
HOME="$H16" bash "${REPO_DIR}/install.sh" --project "$P16" \
    > "${SANDBOX_ROOT}/l16-2.log" 2>&1 < /dev/null
if [ "$H16A" = "$(file_hash "$M16")" ]; then
    pass "L16-3 인수 후 재실행 멱등 (manifest 불변)"
else
    fail "L16-3 재실행마다 manifest 가 바뀜"
fi

HOME="$H16" bash "${REPO_DIR}/install.sh" --uninstall --project "$P16" \
    > "${SANDBOX_ROOT}/l16-3.log" 2>&1 < /dev/null
if [ ! -e "${P16}/dev/active/.gitkeep" ] && [ ! -e "${P16}/dev/completed/.gitkeep" ]; then
    pass "L16-4 uninstall 이 인수한 .gitkeep 2종 제거"
else
    fail "L16-4 인수한 .gitkeep 이 uninstall 후에도 잔존"
fi
if [ -f "${P16}/dev/mine/.gitkeep" ] && grep -q 'user notes' "${P16}/dev/mine/.gitkeep"; then
    pass "L16-5 사용자 .gitkeep 내용 보존"
else
    fail "L16-5 사용자 .gitkeep 이 삭제/훼손됨"
fi

# ============================================================================
# L17: 이주는 "구버전 설치라는 증거" 가 있을 때만 — 손으로 쓴 settings 는 보존
#
# .settings-manifest 부재만으로 legacy 로 단정하면, 직접 관리하는 settings.json 에
# 우연히 Bash(npm *) 한 줄이 있다는 이유로 그것을 지운다. 구버전 설치기는 조각의
# identity 를 **한꺼번에** 썼으므로, 이주 목록이 통째로 들어 있을 때만 이주한다.
# ============================================================================
echo "=== L17: 이주 대조(corroboration) — 부분 일치는 사용자 것 ==="
H17="${SANDBOX_ROOT}/l17-home"; P17="${SANDBOX_ROOT}/l17-proj"
mkdir -p "$H17" "${P17}/.claude"
cat > "${P17}/.claude/settings.json" <<'EOF'
{ "permissions": { "allow": ["Bash(npm *)"] } }
EOF
HOME="$H17" bash "${REPO_DIR}/install.sh" --project "$P17" \
    > "${SANDBOX_ROOT}/l17-1.log" 2>&1 < /dev/null
ALLOW17="$(jq -rc '.permissions.allow // []' "${P17}/.claude/settings.json")"
case "$ALLOW17" in
    *'Bash(npm *)'*) pass "L17-1 부분 일치(사용자가 직접 쓴 것)는 보존" ;;
    *) fail "L17-1 손으로 쓴 Bash(npm *) 를 이주로 삭제함: ${ALLOW17}" ;;
esac

# ============================================================================
# L18: 조각 하나가 스킵되면(python3 부재 등) 그 조각의 이주 기회가 영구히 사라진다
#
# 첫 실행에서 guardrails 가 스킵돼도 cli-orchestration 이 .settings-manifest 를
# 만든다. 다음 실행에서 "manifest 가 있으니 이주 끝났다"고 보면 옛 guardrails 훅이
# 영원히 남는다. 판정은 파일 단위가 아니라 **조각 단위** 여야 한다.
# ============================================================================
echo "=== L18: 조각 단위 이주 판정 ==="
H18="${SANDBOX_ROOT}/l18-home"; P18="${SANDBOX_ROOT}/l18-proj"
mkdir -p "$H18" "${P18}/.claude"
python3 - "${REPO_DIR}/lib/legacy-identities.tsv" "${P18}/.claude/settings.json" <<'PY18'
import io, json, sys
src, dst = sys.argv[1], sys.argv[2]
settings = {"hooks": {}, "permissions": {"allow": []}}
for line in io.open(src, encoding="utf-8"):
    line = line.rstrip("\n")
    if not line or line.startswith("#"):
        continue
    f = line.split("\t")
    if f[0] != "guardrails.json":
        continue
    ev, mt, cmd = f[2], f[3], "\t".join(f[4:])
    arr = settings["hooks"].setdefault(ev, [])
    slot = None
    for e in arr:
        if e.get("matcher", "") == mt:
            slot = e; break
    if slot is None:
        slot = {"matcher": mt, "hooks": []}; arr.append(slot)
    slot["hooks"].append({"type": "command", "command": cmd})
io.open(dst, "w", encoding="utf-8").write(json.dumps(settings, indent=2, ensure_ascii=False) + "\n")
PY18
# 이전 실행에서 cli-orchestration 만 병합에 성공한 상태를 재현한다
printf 'cli-orchestration.json\tperm\tallow\tBash(git status)\n' > "${P18}/.claude/.settings-manifest"
HOME="$H18" bash "${REPO_DIR}/install.sh" --project "$P18" \
    > "${SANDBOX_ROOT}/l18-1.log" 2>&1 < /dev/null
if settings_commands "${P18}/.claude/settings.json" | grep -q "bad=\['rm -rf /'"; then
    fail "L18-1 스킵됐던 guardrails 조각의 옛 훅이 영구 잔존 (조각 단위 판정 부재)"
else
    pass "L18-1 다른 조각이 manifest 를 만든 뒤에도 guardrails 이주 성립"
fi

# ============================================================================
# L19: 보존된 사용자 훅에 chmod 를 걸지 않는다
# ============================================================================
echo "=== L19: 사용자 수정 훅의 권한 불변 ==="
H19="${SANDBOX_ROOT}/l19-home"; P19="${SANDBOX_ROOT}/l19-proj"
mkdir -p "$H19" "$P19"
HOME="$H19" bash "${REPO_DIR}/install.sh" --project "$P19" >/dev/null 2>&1 < /dev/null
HOOK19="${P19}/.claude/hooks/stop-self-check.sh"
if [ -f "$HOOK19" ]; then
    printf '\n# USER EDIT\n' >> "$HOOK19"
    chmod -x "$HOOK19"
    HOME="$H19" bash "${REPO_DIR}/install.sh" --project "$P19" >/dev/null 2>&1 < /dev/null
    if [ -x "$HOOK19" ]; then
        fail "L19-1 보존 대상 사용자 훅에 chmod +x 가 적용됨 (파일 보존 정책 위반)"
    else
        pass "L19-1 사용자 수정 훅의 실행 권한 불변"
    fi
    if grep -q 'USER EDIT' "$HOOK19"; then
        pass "L19-2 사용자 수정 내용 보존"
    else
        fail "L19-2 사용자 수정 내용 소실"
    fi
else
    fail "L19 훅 파일 없음: ${HOOK19}"
fi

# ============================================================================
# L20: 레거시 MODELS.md 를 지우면 CLAUDE.md 의 참조가 끊긴 지시로 남는다
#
# CLAUDE.md 는 사용자 소유(skip-if-exists)라 갱신되지 않는다. 구버전이 만든
# CLAUDE.md 는 `.claude/MODELS.md` 를 "모델 SSOT" 로 가리키는데, 그 파일을 지우면
# 존재하지 않는 파일을 정본이라고 말하는 지시만 남는다. 조용히 지우지 말고 알린다.
# ============================================================================
echo "=== L20: MODELS.md 제거 시 끊긴 참조 안내 ==="
H20A="${SANDBOX_ROOT}/l20a-home"; P20A="${SANDBOX_ROOT}/l20a-proj"
mkdir -p "${P20A}/.claude"
printf '%s\n' "$LEGACY_BODY" > "${P20A}/.claude/MODELS.md"
printf '# My Project\n\n## Reference\n\n- 모델/CLI SSOT: `.claude/MODELS.md`\n' > "${P20A}/CLAUDE.md"
HOME="$H20A" bash "$DOCS_INSTALLER" "$P20A" > "${SANDBOX_ROOT}/l20a.log" 2>&1
if [ ! -e "${P20A}/.claude/MODELS.md" ]; then
    pass "L20-1 레거시 MODELS.md 제거"
else
    fail "L20-1 레거시 MODELS.md 잔존"
fi
if grep -q 'DANGLING-MODELS-REF' "${SANDBOX_ROOT}/l20a.log"; then
    pass "L20-2 CLAUDE.md 의 끊긴 참조를 안내"
else
    fail "L20-2 끊긴 참조 안내 없음 — 존재하지 않는 파일을 SSOT 로 가리키는 지시가 남는다"
fi
if grep -q 'MODELS\.md' "${P20A}/CLAUDE.md"; then
    pass "L20-3 사용자 소유 CLAUDE.md 는 그대로 보존 (자동 수정 안 함)"
else
    fail "L20-3 CLAUDE.md 를 임의로 수정함"
fi

# 참조가 없으면 안내도 없어야 한다 (항상 발화하는 안내는 신호가 아니다)
H20B="${SANDBOX_ROOT}/l20b-home"; P20B="${SANDBOX_ROOT}/l20b-proj"
mkdir -p "${P20B}/.claude"
printf '%s\n' "$LEGACY_BODY" > "${P20B}/.claude/MODELS.md"
printf '# My Project\n\n내용에 그 참조는 없다.\n' > "${P20B}/CLAUDE.md"
HOME="$H20B" bash "$DOCS_INSTALLER" "$P20B" > "${SANDBOX_ROOT}/l20b.log" 2>&1
if grep -q 'DANGLING-MODELS-REF' "${SANDBOX_ROOT}/l20b.log"; then
    fail "L20-4 참조가 없는데도 안내가 발화 (거짓 신호)"
else
    pass "L20-4 참조가 없으면 안내도 없음"
fi

# ============================================================================
# L21: manifest 경로는 관리 루트를 벗어날 수 없다
#
# manifest 는 프로젝트 안(<proj>/.manifest)에 있어서 리포가 값을 통제할 수 있다.
# "../../어딘가" 같은 항목에 실제 해시를 맞춰 넣으면, --uninstall 이 관리 루트
# 바깥 파일을 지운다. 경로를 검증하지 않으면 임의 삭제 수단이 된다.
# ============================================================================
echo "=== L21: manifest 경로 탈출 차단 ==="
H21="${SANDBOX_ROOT}/l21-home"; P21="${SANDBOX_ROOT}/l21-proj"
mkdir -p "$H21" "$P21"
HOME="$H21" bash "${REPO_DIR}/install.sh" --project "$P21" >/dev/null 2>&1 < /dev/null
VICTIM="${SANDBOX_ROOT}/l21-victim.txt"
printf 'do not delete me\n' > "$VICTIM"
VHASH="$(file_hash "$VICTIM")"
# 상대 경로 탈출 + 절대 경로, 둘 다 심는다
if [ -z "$VHASH" ] || [ "$VHASH" = "HASH-UNAVAILABLE" ]; then
    fail "L21 해시를 만들 수 없어 삭제 경로에 도달하지 못함 (죽은 보안 테스트)"
fi
printf '../l21-victim.txt\t%s\n' "$VHASH" >> "${P21}/.manifest"
printf '%s\t%s\n' "$VICTIM" "$VHASH" >> "${P21}/.manifest"
HOME="$H21" bash "${REPO_DIR}/install.sh" --uninstall --project "$P21" \
    > "${SANDBOX_ROOT}/l21-1.log" 2>&1 < /dev/null
if [ -f "$VICTIM" ] && grep -q 'do not delete me' "$VICTIM"; then
    pass "L21-1 관리 루트 밖 파일은 uninstall 이 건드리지 않음"
else
    fail "L21-1 manifest 경로 탈출로 루트 밖 파일이 삭제됨: ${VICTIM}"
fi

# ============================================================================
# L22: 루트 단위 stale 스윕도 manifest 경로 탈출을 막아야 한다
#
# L21 은 --uninstall 경로만 막았다. 루트 스윕은 **일반 설치** 중에 돌기 때문에,
# 여기가 뚫리면 그냥 설치만 해도 프로젝트 밖 파일이 지워진다(실측으로 확인).
# ============================================================================
echo "=== L22: 루트 stale 스윕 경로 탈출 차단 ==="
H22="${SANDBOX_ROOT}/l22-home"; P22="${SANDBOX_ROOT}/l22-proj"
mkdir -p "$H22" "$P22"
HOME="$H22" bash "${REPO_DIR}/install.sh" --project "$P22" >/dev/null 2>&1 < /dev/null
VICTIM22="${SANDBOX_ROOT}/l22-victim.txt"
printf 'do not delete me\n' > "$VICTIM22"
V22H="$(file_hash "$VICTIM22")"
if [ -z "$V22H" ] || [ "$V22H" = "HASH-UNAVAILABLE" ]; then
    fail "L22 해시를 만들 수 없어 삭제 경로에 도달하지 못함 (죽은 보안 테스트)"
fi
printf '.claude/agents/../../../l22-victim.txt\t%s\n' "$V22H" >> "${P22}/.manifest"
HOME="$H22" bash "${REPO_DIR}/install.sh" --project "$P22" \
    > "${SANDBOX_ROOT}/l22-1.log" 2>&1 < /dev/null
if [ -f "$VICTIM22" ] && grep -q 'do not delete me' "$VICTIM22"; then
    pass "L22-1 일반 설치의 루트 스윕이 루트 밖 파일을 지우지 않음"
else
    fail "L22-1 루트 스윕이 프로젝트 밖 파일을 삭제함: ${VICTIM22}"
fi

# ============================================================================
# L23: 관리 파일 자리에 디렉토리가 있으면 그 안으로 복사하지 않는다
#
# `[ -f "$dst" ]` 만 보면 같은 경로에 디렉토리가 있을 때 조건이 거짓이 되어
# `cp` 가 **디렉토리 안으로** 복사하고, manifest 는 디렉토리 경로를 설치 파일인 양
# 기록한다. 이후 업그레이드도 uninstall 도 그 자산을 관리할 수 없게 된다.
# ============================================================================
echo "=== L23: 관리 파일 경로에 디렉토리 충돌 ==="
H23="${SANDBOX_ROOT}/l23-home"; P23="${SANDBOX_ROOT}/l23-proj"
mkdir -p "$H23" "$P23"
COLLIDE="${H23}/.claude/rules/golden-principles.md"
mkdir -p "$COLLIDE"
printf 'user content\n' > "${COLLIDE}/user-file.txt"
HOME="$H23" bash "${REPO_DIR}/install.sh" --global-only \
    > "${SANDBOX_ROOT}/l23-1.log" 2>&1 < /dev/null
RC23=$?
if [ "$RC23" -eq 0 ]; then
    pass "L23-1 디렉토리 충돌에도 설치가 죽지 않음 (exit 0)"
else
    fail "L23-1 디렉토리 충돌로 설치 실패 (exit ${RC23})"
fi
if [ -f "${COLLIDE}/golden-principles.md" ]; then
    fail "L23-2 디렉토리 안으로 복사됨 (${COLLIDE}/golden-principles.md)"
else
    pass "L23-2 디렉토리 안으로 복사하지 않음"
fi
if [ -f "${COLLIDE}/user-file.txt" ]; then
    pass "L23-3 충돌 디렉토리의 사용자 내용 보존"
else
    fail "L23-3 사용자 내용 소실"
fi
if grep -q '^rules/golden-principles\.md	' "${H23}/.claude/.manifest" 2>/dev/null; then
    fail "L23-4 디렉토리 경로를 설치 파일로 manifest 에 기록함"
else
    pass "L23-4 디렉토리 경로를 소유로 기록하지 않음"
fi

# ============================================================================
# L24: 관리 목적지가 심볼릭 링크면 그 링크를 통해 쓰지 않는다
#
# `-d`/`-f` 는 링크를 따라간다. 관리 디렉토리 자리에 바깥을 가리키는 링크가 있으면
# mkdir/cp 가 링크를 통해 **관리 루트 밖**에 쓴다(실측: 바깥 디렉토리에 SKILL.md 생성).
# 링크는 우리 소유가 아니므로 따라가지 않고 보존·보고한다.
# ============================================================================
echo "=== L24: 심볼릭 링크 목적지 차단 ==="
H24="${SANDBOX_ROOT}/l24-home"; OUT24="${SANDBOX_ROOT}/l24-outside"
mkdir -p "${H24}/.claude/skills" "${H24}/.claude/rules" "$OUT24"
printf 'outside marker\n' > "${OUT24}/marker.txt"
SK24="$(ls "${REPO_DIR}/global/skills" | head -1)"
ln -s "$OUT24" "${H24}/.claude/skills/${SK24}"
OUTF24="${SANDBOX_ROOT}/l24-outside-file.md"
printf 'outside file\n' > "$OUTF24"
ln -s "$OUTF24" "${H24}/.claude/rules/golden-principles.md"

HOME="$H24" bash "${REPO_DIR}/install.sh" --global-only \
    > "${SANDBOX_ROOT}/l24-1.log" 2>&1 < /dev/null
RC24=$?
if [ "$RC24" -eq 0 ]; then
    pass "L24-1 링크가 있어도 설치가 죽지 않음"
else
    fail "L24-1 설치 실패 (exit ${RC24})"
fi
OUT24_N="$(find "$OUT24" -type f | wc -l | tr -d ' ')"
if [ "$OUT24_N" -eq 1 ]; then
    pass "L24-2 디렉토리 링크를 통해 바깥에 쓰지 않음"
else
    fail "L24-2 링크를 통해 관리 루트 밖에 ${OUT24_N}개 파일 기록: $(ls "$OUT24" | tr '\n' ' ')"
fi
if grep -q 'outside file' "$OUTF24"; then
    pass "L24-3 파일 링크를 통해 바깥 파일을 덮어쓰지 않음"
else
    fail "L24-3 링크를 통해 바깥 파일이 덮어써짐"
fi
if grep -q "skills/${SK24}/" "${H24}/.claude/.manifest" 2>/dev/null; then
    fail "L24-4 링크 경로를 소유로 기록함"
else
    pass "L24-4 링크 경로를 소유로 기록하지 않음"
fi

# ============================================================================
# L25: 소유 기록을 남기지 못하면 조용히 성공하지 않는다
#
# settings 는 바뀌었는데 .settings-manifest 기록이 실패하면, 그 훅들은 영원히
# --uninstall 대상이 되지 못한다. 실패를 삼키면 그 상태가 정상처럼 보인다.
# ============================================================================
echo "=== L25: manifest 기록 실패 전파 ==="
H25="${SANDBOX_ROOT}/l25-home"; P25="${SANDBOX_ROOT}/l25-proj"
mkdir -p "$H25" "${P25}/.claude"
printf '{}\n' > "${P25}/.claude/settings.json"
mkdir -p "${P25}/.claude/.settings-manifest"   # 디렉토리로 막아 기록 실패를 만든다
HOME="$H25" bash "${REPO_DIR}/install.sh" --project "$P25" \
    > "${SANDBOX_ROOT}/l25-1.log" 2>&1 < /dev/null
RC25=$?
if [ "$RC25" -ne 0 ]; then
    pass "L25-1 소유 기록 실패 시 비영(非零) 종료"
else
    fail "L25-1 소유 기록에 실패했는데 exit 0 — uninstall 불가 상태가 정상처럼 보인다"
fi
if grep -q 'GUARD_BASH' "${P25}/.claude/settings.json" 2>/dev/null; then
    fail "L25-2 기록 실패인데 settings 변경이 남음 (롤백 미동작)"
else
    pass "L25-2 기록 실패 시 settings 변경이 롤백됨"
fi

# ============================================================================
# L26: 조상 경로가 심볼릭 링크여도 그리로 쓰지 않는다
# L27: 소스 루트가 없는 불완전한 체크아웃에서는 stale 스윕을 하지 않는다
# L28: settings.json 의 모드(권한)를 원자적 교체가 바꾸지 않는다
# ============================================================================
echo "=== L26: 조상 심볼릭 링크 차단 ==="
H26="${SANDBOX_ROOT}/l26-home"; OUT26="${SANDBOX_ROOT}/l26-outside"
mkdir -p "${H26}/.claude" "$OUT26"
ln -s "$OUT26" "${H26}/.claude/skills"          # 조상 자체가 링크
HOME="$H26" bash "${REPO_DIR}/install.sh" --global-only \
    > "${SANDBOX_ROOT}/l26-1.log" 2>&1 < /dev/null
N26="$(find "$OUT26" -type f 2>/dev/null | wc -l | tr -d ' ')"
if [ "$N26" -eq 0 ]; then
    pass "L26-1 조상 링크를 통해 관리 루트 밖에 쓰지 않음"
else
    fail "L26-1 조상 링크를 통해 바깥에 ${N26}개 파일 기록"
fi

echo "=== L27: 불완전한 체크아웃에서 stale 스윕 금지 ==="
H27="${SANDBOX_ROOT}/l27-home"; FIX27="${SANDBOX_ROOT}/l27-fix"
make_fixture_repo "$FIX27"
HOME="$H27" bash "${FIX27}/install.sh" --global-only >/dev/null 2>&1 < /dev/null
BEFORE27="$(find "${H27}/.claude/rules" "${H27}/.claude/skills" -type f 2>/dev/null | wc -l | tr -d ' ')"
DOCS_BEFORE27="$(find "${H27}/.claude/docs" -type f 2>/dev/null | wc -l | tr -d ' ')"
rm -rf "${FIX27}/global"      # 패키징 사고·불완전 체크아웃 재현
HOME="$H27" bash "${FIX27}/install.sh" --global-only \
    > "${SANDBOX_ROOT}/l27-1.log" 2>&1 < /dev/null
AFTER27="$(find "${H27}/.claude/rules" "${H27}/.claude/skills" -type f 2>/dev/null | wc -l | tr -d ' ')"
if [ "$BEFORE27" -gt 0 ] && [ "$AFTER27" -eq "$BEFORE27" ]; then
    pass "L27-1 global/ 부재 시 설치 자산을 지우지 않음 (${AFTER27}건 유지)"
else
    fail "L27-1 불완전한 체크아웃이 설치 자산을 삭제함 (${BEFORE27} → ${AFTER27})"
fi

# docs/ 만 빠진 경우가 더 위험하다 — 병합이 실패하지 않아 설치가 그대로 진행되고,
# 스윕이 설치된 문서 전체를 "업스트림 삭제"로 오판한다(실측: 21 → 1).
FIX27B="${SANDBOX_ROOT}/l27b-fix"; H27B="${SANDBOX_ROOT}/l27b-home"
make_fixture_repo "$FIX27B"
HOME="$H27B" bash "${FIX27B}/install.sh" --global-only >/dev/null 2>&1 < /dev/null
DOCS_B="$(find "${H27B}/.claude/docs" -type f 2>/dev/null | wc -l | tr -d ' ')"
rm -rf "${FIX27B}/docs"
HOME="$H27B" bash "${FIX27B}/install.sh" --global-only \
    > "${SANDBOX_ROOT}/l27b.log" 2>&1 < /dev/null
DOCS_A="$(find "${H27B}/.claude/docs" -type f 2>/dev/null | wc -l | tr -d ' ')"
if [ "$DOCS_B" -gt 1 ] && [ "$DOCS_A" -eq "$DOCS_B" ]; then
    pass "L27-2 docs/ 부재 시 설치된 문서를 지우지 않음 (${DOCS_A}건 유지)"
else
    fail "L27-2 docs/ 부재가 설치 문서를 삭제함 (${DOCS_B} → ${DOCS_A})"
fi

echo "=== L28: settings.json 모드 보존 ==="
H28="${SANDBOX_ROOT}/l28-home"; P28="${SANDBOX_ROOT}/l28-proj"
mkdir -p "$H28" "${P28}/.claude"
printf '{}\n' > "${P28}/.claude/settings.json"
chmod 600 "${P28}/.claude/settings.json"
HOME="$H28" bash "${REPO_DIR}/install.sh" --project "$P28" >/dev/null 2>&1 < /dev/null
MODE28="$(stat -f '%Lp' "${P28}/.claude/settings.json" 2>/dev/null || stat -c '%a' "${P28}/.claude/settings.json" 2>/dev/null)"
if [ "$MODE28" = "600" ]; then
    pass "L28-1 병합이 settings.json 모드(600)를 보존"
else
    fail "L28-1 병합 후 모드가 ${MODE28} 로 바뀜 (기대 600)"
fi

# ============================================================================
# L29: 설치 후 관리 디렉토리가 링크로 바뀌어도 삭제 경로가 밖을 지우지 않는다
# L30: settings.json 이 심볼릭 링크면 링크를 보존하고 대상 파일을 갱신한다
# L31: --uninstall 은 없는 프로젝트를 만들지 않는다
# ============================================================================
echo "=== L29: 삭제 경로의 조상 링크 재검사 ==="
H29="${SANDBOX_ROOT}/l29-home"; OUT29="${SANDBOX_ROOT}/l29-outside"
mkdir -p "$H29" "$OUT29"
HOME="$H29" bash "${REPO_DIR}/install.sh" --global-only >/dev/null 2>&1 < /dev/null
SK29="$(ls "${H29}/.claude/skills" | head -1)"
REL29="$(grep "^skills/${SK29}/" "${H29}/.claude/.manifest" | head -1 | cut -f1)"
BASE29="${REL29##*/}"
# 설치된 파일과 **내용이 같은** 파일을 바깥에 두고, 관리 디렉토리를 링크로 바꾼다
cp "${H29}/.claude/${REL29}" "${OUT29}/${BASE29}"
rm -rf "${H29}/.claude/skills/${SK29}"
ln -s "$OUT29" "${H29}/.claude/skills/${SK29}"
HOME="$H29" bash "${REPO_DIR}/install.sh" --uninstall \
    > "${SANDBOX_ROOT}/l29-1.log" 2>&1 < /dev/null
if [ -f "${OUT29}/${BASE29}" ]; then
    pass "L29-1 링크 너머의 외부 파일을 uninstall 이 지우지 않음"
else
    fail "L29-1 uninstall 이 링크를 따라 외부 파일을 삭제함: ${OUT29}/${BASE29}"
fi

echo "=== L30: 심볼릭 링크 settings.json ==="
H30="${SANDBOX_ROOT}/l30-home"; P30="${SANDBOX_ROOT}/l30-proj"; DOT30="${SANDBOX_ROOT}/l30-dotfiles"
mkdir -p "$H30" "${P30}/.claude" "$DOT30"
printf '{}\n' > "${DOT30}/settings.json"
ln -s "${DOT30}/settings.json" "${P30}/.claude/settings.json"
HOME="$H30" bash "${REPO_DIR}/install.sh" --project "$P30" \
    > "${SANDBOX_ROOT}/l30-1.log" 2>&1 < /dev/null
if [ -L "${P30}/.claude/settings.json" ]; then
    pass "L30-1 심볼릭 링크가 일반 파일로 대체되지 않음"
else
    fail "L30-1 링크가 일반 파일로 바뀌어 dotfile 관리가 끊김"
fi
if grep -q 'GUARD_BASH' "${DOT30}/settings.json" 2>/dev/null; then
    pass "L30-2 링크 대상 파일이 실제로 갱신됨"
else
    fail "L30-2 링크 대상이 갱신되지 않음 (병합 유실)"
fi

echo "=== L31: uninstall 은 없는 프로젝트를 만들지 않는다 ==="
H31="${SANDBOX_ROOT}/l31-home"; P31="${SANDBOX_ROOT}/l31-absent"
mkdir -p "$H31"
HOME="$H31" bash "${REPO_DIR}/install.sh" --uninstall --project "$P31" \
    > "${SANDBOX_ROOT}/l31-1.log" 2>&1 < /dev/null
if [ ! -d "$P31" ]; then
    pass "L31-1 없는 프로젝트를 uninstall 이 생성하지 않음"
else
    fail "L31-1 uninstall 이 프로젝트 디렉토리를 새로 만듦: ${P31}"
fi

# ============================================================================
# L32: 관리 루트 자체가 심볼릭 링크인 경우 (dotfiles 흔한 구성)
# L33: 소스 "하위 트리" 만 빠져도 stale 로 오판하면 안 된다
# ============================================================================
echo "=== L32: 링크된 관리 루트 ==="
H32="${SANDBOX_ROOT}/l32-home"; REAL32="${SANDBOX_ROOT}/l32-real-claude"
mkdir -p "$H32" "$REAL32"
ln -s "$REAL32" "${H32}/.claude"
HOME="$H32" bash "${REPO_DIR}/install.sh" --global-only \
    > "${SANDBOX_ROOT}/l32-1.log" 2>&1 < /dev/null
RC32=$?
N32="$(find "$REAL32" -type f 2>/dev/null | wc -l | tr -d ' ')"
if [ "$RC32" -eq 0 ] && [ "$N32" -gt 10 ]; then
    pass "L32-1 링크된 ~/.claude 에도 정상 설치 (${N32}건, 사용자가 의도한 위치)"
else
    fail "L32-1 링크된 관리 루트에서 설치 실패 (rc=${RC32}, files=${N32})"
fi
# 루트를 해석한 뒤에도 그 **안쪽** 링크는 여전히 거부되어야 한다
OUT32="${SANDBOX_ROOT}/l32-outside"; mkdir -p "$OUT32"
rm -rf "${REAL32}/rules"; ln -s "$OUT32" "${REAL32}/rules"
HOME="$H32" bash "${REPO_DIR}/install.sh" --global-only \
    > "${SANDBOX_ROOT}/l32-2.log" 2>&1 < /dev/null
N32B="$(find "$OUT32" -type f 2>/dev/null | wc -l | tr -d ' ')"
if [ "$N32B" -eq 0 ]; then
    pass "L32-2 루트 해석 후에도 내부 링크는 거부"
else
    fail "L32-2 내부 링크를 통해 밖에 ${N32B}건 기록"
fi

echo "=== L33: 소스 하위 트리 부재 ==="
H33="${SANDBOX_ROOT}/l33-home"; FIX33="${SANDBOX_ROOT}/l33-fix"
make_fixture_repo "$FIX33"
HOME="$H33" bash "${FIX33}/install.sh" --global-only >/dev/null 2>&1 < /dev/null
SK_B33="$(find "${H33}/.claude/skills" -type f 2>/dev/null | wc -l | tr -d ' ')"
rm -rf "${FIX33}/global/skills"       # global/ 은 남아 있고 하위 트리만 사라짐
HOME="$H33" bash "${FIX33}/install.sh" --global-only \
    > "${SANDBOX_ROOT}/l33-1.log" 2>&1 < /dev/null
SK_A33="$(find "${H33}/.claude/skills" -type f 2>/dev/null | wc -l | tr -d ' ')"
if [ "$SK_B33" -gt 0 ] && [ "$SK_A33" -eq "$SK_B33" ]; then
    pass "L33-1 소스 하위 트리 부재 시 설치 스킬을 지우지 않음 (${SK_A33}건 유지)"
else
    fail "L33-1 하위 트리 부재가 설치 자산을 삭제함 (${SK_B33} → ${SK_A33})"
fi

# ============================================================================
# L34: 심볼릭 링크로 관리되는 manifest / MODELS.md / settings 목적지
# ============================================================================
echo "=== L34: 링크된 소유 기록·레거시 파일 보존 ==="
H34="${SANDBOX_ROOT}/l34-home"; P34="${SANDBOX_ROOT}/l34-proj"; DOT34="${SANDBOX_ROOT}/l34-dot"
mkdir -p "$H34" "$P34" "$DOT34"
: > "${DOT34}/manifest"
ln -s "${DOT34}/manifest" "${P34}/.manifest"
HOME="$H34" bash "${REPO_DIR}/install.sh" --project "$P34" \
    > "${SANDBOX_ROOT}/l34-1.log" 2>&1 < /dev/null
if [ -L "${P34}/.manifest" ]; then
    pass "L34-1 링크된 .manifest 가 일반 파일로 대체되지 않음"
else
    fail "L34-1 링크된 .manifest 가 대체되어 dotfile 관리가 끊김"
fi
if [ -s "${DOT34}/manifest" ]; then
    pass "L34-2 링크 대상에 소유 기록이 실제로 쓰임"
else
    fail "L34-2 링크 대상이 갱신되지 않음 (기록 유실)"
fi

# settings.json 자리에 디렉토리가 있으면 "생성 성공" 이라고 보고하면 안 된다
P34B="${SANDBOX_ROOT}/l34b-proj"; H34B="${SANDBOX_ROOT}/l34b-home"
mkdir -p "$H34B" "${P34B}/.claude/settings.json"
HOME="$H34B" bash "${REPO_DIR}/install.sh" --project "$P34B" \
    > "${SANDBOX_ROOT}/l34-2.log" 2>&1 < /dev/null
RC34B=$?
if [ "$RC34B" -ne 0 ]; then
    pass "L34-3 settings.json 자리에 디렉토리가 있으면 실패로 보고"
else
    fail "L34-3 디렉토리인데 '생성 성공' 으로 보고 (사용 가능한 settings 가 없다)"
fi

# 레거시 MODELS.md 가 사용자 링크면 지우지 않는다
P34C="${SANDBOX_ROOT}/l34c-proj"; H34C="${SANDBOX_ROOT}/l34c-home"
mkdir -p "$H34C" "${P34C}/.claude" "${SANDBOX_ROOT}/l34c-real"
printf '%s\n' "$LEGACY_BODY" > "${SANDBOX_ROOT}/l34c-real/MODELS.md"
ln -s "${SANDBOX_ROOT}/l34c-real/MODELS.md" "${P34C}/.claude/MODELS.md"
HOME="$H34C" bash "$DOCS_INSTALLER" "$P34C" > "${SANDBOX_ROOT}/l34-3.log" 2>&1
if [ -L "${P34C}/.claude/MODELS.md" ] && [ -f "${SANDBOX_ROOT}/l34c-real/MODELS.md" ]; then
    pass "L34-4 사용자 링크 MODELS.md 는 제거하지 않음"
else
    fail "L34-4 사용자 링크(또는 그 대상)가 삭제됨"
fi

# ============================================================================
# L35: uninstall 이 링크로 관리되는 manifest 를 지우지 않는다
# ============================================================================
echo "=== L35: 링크 manifest 는 uninstall 이 지우지 않는다 ==="
H35="${SANDBOX_ROOT}/l35-home"; P35="${SANDBOX_ROOT}/l35-proj"; DOT35="${SANDBOX_ROOT}/l35-dot"
mkdir -p "$H35" "$P35" "$DOT35"
: > "${DOT35}/manifest"; : > "${DOT35}/settings-manifest"
ln -s "${DOT35}/manifest" "${P35}/.manifest"
HOME="$H35" bash "${REPO_DIR}/install.sh" --project "$P35" >/dev/null 2>&1 < /dev/null
mkdir -p "${P35}/.claude"
HOME="$H35" bash "${REPO_DIR}/install.sh" --uninstall --project "$P35" \
    > "${SANDBOX_ROOT}/l35-1.log" 2>&1 < /dev/null
if [ -L "${P35}/.manifest" ]; then
    pass "L35-1 링크된 .manifest 를 uninstall 이 지우지 않음"
else
    fail "L35-1 uninstall 이 사용자 링크를 삭제해 dotfile 관리가 끊김"
fi

# ============================================================================
# L36: --project 가 ~/.claude 안을 가리키면 프로젝트 manifest 가 우선이어야 한다
# L37: 사용자가 만든 <file>.bak* 는 retention 이 지우지 않는다
# ============================================================================
echo "=== L36: 중첩 루트에서 프로젝트 우선 ==="
H36="${SANDBOX_ROOT}/l36-home"; P36="${H36}/.claude/nested-proj"
mkdir -p "$H36"
HOME="$H36" bash "${REPO_DIR}/install.sh" --project "$P36" \
    > "${SANDBOX_ROOT}/l36-1.log" 2>&1 < /dev/null
if [ -f "${P36}/.manifest" ] && grep -q '^\.claude/' "${P36}/.manifest" 2>/dev/null; then
    pass "L36-1 프로젝트 자산이 프로젝트 manifest 에 기록됨"
else
    fail "L36-1 프로젝트 manifest 없음/비었음 — 글로벌에 기록되어 uninstall 이 못 찾는다"
fi
HOME="$H36" bash "${REPO_DIR}/install.sh" --uninstall --project "$P36" \
    > "${SANDBOX_ROOT}/l36-2.log" 2>&1 < /dev/null
LEFT36="$(find "${P36}/.claude/skills" -type f 2>/dev/null | wc -l | tr -d ' ')"
if [ "$LEFT36" -eq 0 ]; then
    pass "L36-2 중첩 프로젝트도 uninstall 로 정리됨"
else
    fail "L36-2 중첩 프로젝트 소유 파일 ${LEFT36}건이 지워지지 않음"
fi

echo "=== L37: 사용자 백업 파일 보존 ==="
H37="${SANDBOX_ROOT}/l37-home"; FIX37="${SANDBOX_ROOT}/l37-fix"
make_fixture_repo "$FIX37"
HOME="$H37" bash "${FIX37}/install.sh" --global-only >/dev/null 2>&1 < /dev/null
RULE37="${H37}/.claude/rules/golden-principles.md"
i=1
while [ "$i" -le 5 ]; do
    printf 'user backup %s\n' "$i" > "${RULE37}.bak.${i}"
    i=$((i + 1))
done
# 업스트림 변경 → 설치기가 백업을 새로 만들고 retention 이 돈다
printf '\nUPSTREAM 37\n' >> "${FIX37}/global/rules/golden-principles.md"
HOME="$H37" bash "${FIX37}/install.sh" --global-only \
    > "${SANDBOX_ROOT}/l37-1.log" 2>&1 < /dev/null
KEPT37=0
i=1
while [ "$i" -le 5 ]; do
    [ -f "${RULE37}.bak.${i}" ] && grep -q "user backup ${i}" "${RULE37}.bak.${i}" 2>/dev/null && KEPT37=$((KEPT37 + 1))
    i=$((i + 1))
done
if [ "$KEPT37" -eq 5 ]; then
    pass "L37-1 사용자가 만든 백업 5건 전부 보존"
else
    fail "L37-1 retention 이 사용자 백업을 삭제함 (${KEPT37}/5 생존)"
fi

# ============================================================================
# L38: 롤백이 .settings-backups 색인도 원상 복구한다
# L39: 조각 소스가 사라지면 그 조각이 넣은 settings identity 도 정리된다
# ============================================================================
echo "=== L38: 롤백의 백업 색인 커버리지 ==="
H38="${SANDBOX_ROOT}/l38-home"; P38="${SANDBOX_ROOT}/l38-proj"; FIX38="${SANDBOX_ROOT}/l38-fix"
mkdir -p "$H38" "$P38"
make_fixture_repo "$FIX38"
HOME="$H38" bash "${FIX38}/install.sh" --project "$P38" >/dev/null 2>&1 < /dev/null
SNAP38="${SANDBOX_ROOT}/l38-before.txt"
snapshot_tree "$P38" > "$SNAP38"
# settings 가 실제로 바뀌도록 조각을 고치고, 위임 단계에서 실패시킨다
python3 - "${FIX38}/project/settings-fragments/cli-orchestration.json" <<'PY38'
import json,sys
p=sys.argv[1]; d=json.load(open(p))
d.setdefault("hooks",{}).setdefault("Stop",[]).append(
  {"matcher":"","hooks":[{"type":"command","command":"L38-NEW"}]})
json.dump(d,open(p,"w"),indent=2)
PY38
printf '#!/bin/bash\nexit 7\n' > "${FIX38}/docs/Claude code system setup/install.sh"
HOME="$H38" bash "${FIX38}/install.sh" --project "$P38" \
    > "${SANDBOX_ROOT}/l38-1.log" 2>&1 < /dev/null
SNAP38B="${SANDBOX_ROOT}/l38-after.txt"
snapshot_tree "$P38" > "$SNAP38B"
if diff -q "$SNAP38" "$SNAP38B" >/dev/null 2>&1; then
    pass "L38-1 롤백이 프로젝트 트리를 바이트 단위로 복구 (백업 색인 포함)"
else
    fail "L38-1 롤백 후 차이: $(diff "$SNAP38" "$SNAP38B" | head -3 | tr '\n' ' ')"
fi

echo "=== L39: 사라진 조각의 settings identity 정리 ==="
H39="${SANDBOX_ROOT}/l39-home"; P39="${SANDBOX_ROOT}/l39-proj"; FIX39="${SANDBOX_ROOT}/l39-fix"
mkdir -p "$H39" "$P39"
make_fixture_repo "$FIX39"
HOME="$H39" bash "${FIX39}/install.sh" --with-verify-hooks --project "$P39" >/dev/null 2>&1 < /dev/null
S39="${P39}/.claude/settings.json"
if settings_commands "$S39" | grep -q 'stop-self-check\.sh'; then
    pass "L39-0 verify-hooks 조각이 배선됨 (테스트 헛돎 방지)"
else
    fail "L39-0 사전 조건 실패"
fi
rm -f "${FIX39}/project/settings-fragments/verification-hooks.json"
# 조각이 리포에서 사라진 뒤의 평범한 재설치. (플래그를 그대로 주면 "요청한 조각이
# 없음" 이라 하드 실패가 정답이므로, 스윕 동작을 보려면 플래그 없이 돌린다.)
HOME="$H39" bash "${FIX39}/install.sh" --project "$P39" \
    > "${SANDBOX_ROOT}/l39-1.log" 2>&1 < /dev/null
if settings_commands "$S39" | grep -q 'stop-self-check\.sh'; then
    fail "L39-1 조각이 사라졌는데 그 훅이 settings 에 그대로 남아 계속 실행됨"
else
    pass "L39-1 사라진 조각의 소유 identity 가 settings 에서 제거됨"
fi
if grep -q 'verification-hooks.json' "${P39}/.claude/.settings-manifest" 2>/dev/null; then
    fail "L39-2 .settings-manifest 에 사라진 조각 기록이 남음"
else
    pass "L39-2 사라진 조각의 소유 기록도 정리됨"
fi

# ============================================================================
# L40: 백업 경로가 dangling 심볼릭 링크면 그 링크를 통해 쓰지 않는다
#
# `[ ! -e "$f.bak" ]` 는 **깨진 링크에도 참**이다. 그러면 그 경로가 백업 자리로
# 뽑히고 `cp -p` 가 링크를 따라가 관리 루트 밖 파일을 만들거나 덮어쓴다.
# ============================================================================
echo "=== L40: 백업 경로의 dangling 링크 ==="
H40="${SANDBOX_ROOT}/l40-home"; FIX40="${SANDBOX_ROOT}/l40-fix"
OUT40="${SANDBOX_ROOT}/l40-outside.txt"
mkdir -p "$H40"
make_fixture_repo "$FIX40"
HOME="$H40" bash "${FIX40}/install.sh" --global-only >/dev/null 2>&1 < /dev/null
RULE40="${H40}/.claude/rules/golden-principles.md"
rm -f "$OUT40"
ln -s "$OUT40" "${RULE40}.bak"                 # 깨진 링크 (대상 없음)
printf '\nUPSTREAM 40\n' >> "${FIX40}/global/rules/golden-principles.md"
HOME="$H40" bash "${FIX40}/install.sh" --global-only \
    > "${SANDBOX_ROOT}/l40-1.log" 2>&1 < /dev/null
if [ ! -e "$OUT40" ]; then
    pass "L40-1 깨진 링크를 통해 관리 루트 밖에 백업을 쓰지 않음"
else
    fail "L40-1 링크를 따라 밖에 파일 생성: ${OUT40}"
fi

# 대상이 이미 있는 링크(사용자 파일)를 덮어쓰지도 않아야 한다
OUT40B="${SANDBOX_ROOT}/l40-outside2.txt"
printf 'user content\n' > "$OUT40B"
rm -f "${RULE40}.bak" "${RULE40}.bak."*
ln -s "$OUT40B" "${RULE40}.bak"
printf '\nUPSTREAM 40B\n' >> "${FIX40}/global/rules/golden-principles.md"
HOME="$H40" bash "${FIX40}/install.sh" --global-only \
    > "${SANDBOX_ROOT}/l40-2.log" 2>&1 < /dev/null
if grep -q 'user content' "$OUT40B"; then
    pass "L40-2 링크 너머 사용자 파일을 백업이 덮어쓰지 않음"
else
    fail "L40-2 백업이 링크를 따라 사용자 파일을 덮어씀"
fi

# ============================================================================
# L41: uninstall 실패 시 .settings-backups 색인도 원상 복구된다
# ============================================================================
echo "=== L41: uninstall 롤백의 백업 색인 커버리지 ==="
H41="${SANDBOX_ROOT}/l41-home"; P41="${SANDBOX_ROOT}/l41-proj"
mkdir -p "$H41" "$P41"
HOME="$H41" bash "${REPO_DIR}/install.sh" --project "$P41" >/dev/null 2>&1 < /dev/null
IDX41="${H41}/.claude/.settings-backups"
BEFORE41="$( [ -f "$IDX41" ] && cat "$IDX41" || printf '' )"
# 프로젝트 settings 를 깨뜨려 뒤 단계에서 실패시킨다 (글로벌 unmerge 는 이미 끝난 뒤)
printf '{ broken json\n' > "${P41}/.claude/settings.json"
HOME="$H41" bash "${REPO_DIR}/install.sh" --uninstall --project "$P41" \
    > "${SANDBOX_ROOT}/l41-1.log" 2>&1 < /dev/null
RC41=$?
AFTER41="$( [ -f "$IDX41" ] && cat "$IDX41" || printf '' )"
if [ "$RC41" -ne 0 ]; then
    pass "L41-0 깨진 settings 로 uninstall 이 실패 (사전 조건)"
else
    fail "L41-0 실패하지 않음 — 이 테스트가 롤백을 검사하지 못한다"
fi
if [ "$BEFORE41" = "$AFTER41" ]; then
    pass "L41-1 실패 롤백이 .settings-backups 색인을 원상 복구"
else
    fail "L41-1 색인에 새 소유 줄이 남음 (미래의 사용자 파일이 우리 것으로 오인돼 삭제될 수 있다)"
fi

# ============================================================================
# L42: 공백·글로브가 든 fragment id 도 정확히 처리된다
#
# `for id in $ids` 는 공백에서 쪼개지고 글로브가 확장된다 — 그런 id 가 소유한
# 훅·권한은 영원히 남는다.
# ============================================================================
echo "=== L42: 특이 문자 fragment id ==="
H42="${SANDBOX_ROOT}/l42-home"; P42="${SANDBOX_ROOT}/l42-proj"
mkdir -p "$H42" "${P42}/.claude"
cat > "${P42}/.claude/settings.json" <<'EOF'
{
  "hooks": {
    "Stop": [
      { "matcher": "", "hooks": [
        { "type": "command", "command": "space-id-cmd" },
        { "type": "command", "command": "glob-id-cmd" },
        { "type": "command", "command": "user-own-cmd" }
      ] }
    ]
  }
}
EOF
printf 'my frag.json\thook\tStop\t\tspace-id-cmd\n'  > "${P42}/.claude/.settings-manifest"
printf 'star*.json\thook\tStop\t\tglob-id-cmd\n'    >> "${P42}/.claude/.settings-manifest"
HOME="$H42" bash "${REPO_DIR}/install.sh" --uninstall --project "$P42" \
    > "${SANDBOX_ROOT}/l42-1.log" 2>&1 < /dev/null
C42="$(settings_commands "${P42}/.claude/settings.json")"
if printf '%s\n' "$C42" | grep -q '^space-id-cmd$'; then
    fail "L42-1 공백 든 id 의 소유 훅이 제거되지 않음"
else
    pass "L42-1 공백 든 fragment id 의 소유 훅 제거"
fi
if printf '%s\n' "$C42" | grep -q '^glob-id-cmd$'; then
    fail "L42-2 글로브 든 id 의 소유 훅이 제거되지 않음"
else
    pass "L42-2 글로브 든 fragment id 의 소유 훅 제거"
fi
if printf '%s\n' "$C42" | grep -q '^user-own-cmd$'; then
    pass "L42-3 소유 기록 없는 사용자 훅은 보존"
else
    fail "L42-3 사용자 훅까지 삭제됨"
fi

finish
