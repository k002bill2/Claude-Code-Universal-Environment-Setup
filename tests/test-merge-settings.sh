#!/bin/bash
# ============================================================================
# tests/test-merge-settings.sh — lib/merge-settings.sh 단위 테스트
# ----------------------------------------------------------------------------
# 실행: bash tests/test-merge-settings.sh
#
# 병합 계약 (identity 기반 — 이 파일이 계약의 실행 명세다):
#   - hooks identity = (event, matcher, command). matcher 는 (.matcher // "") 로
#     정규화해 비교한다.
#   - 추가: 같은 (event, matcher) 엔트리가 있으면 그 hooks[] 에 없는 command 만
#     추가, 없으면 엔트리 신규 append. 부분중복이 구조적으로 불가능해야 한다.
#   - 같은 fragment 안에서 동일 identity 가 2번 나와도 1번만 반영된다.
#   - 제거: MERGE_MANIFEST 의 이전 소유 레코드(+MERGE_LEGACY_REMOVALS) 중
#     새 fragment 에 없는 identity 만 settings 에서 제거. 사용자 hook 은 보존.
#   - permissions.allow: 합집합 + 이전 소유분 중 fragment 에서 빠진 항목 제거.
#     deny/ask 등 다른 permissions 키와 알 수 없는 최상위 키는 전부 보존.
#   - jq 경로와 node 폴백은 동일 입력 → 동일 출력(바이트 동일)이어야 한다.
#   - malformed settings/fragment → 실패 반환 + 대상 파일 무변경.
#   - 백업은 bounded (.bak, .bak.1, .bak.2 최대 3개).
#
# 격리: 샌드박스 디렉토리에서만 파일 생성. 실제 $HOME 미접촉.
# 제약: bash 3.2 호환, 모든 경로 인용.
# ============================================================================
set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "${REPO_DIR}/tests/helpers.sh"

if ! command -v jq >/dev/null 2>&1; then
    echo "FAIL: 이 테스트는 jq 가 필요합니다" >&2
    exit 1
fi
if ! command -v node >/dev/null 2>&1; then
    echo "FAIL: 이 테스트는 node 폴백 검증에 node 가 필요합니다" >&2
    exit 1
fi

init_sandbox
WORK="${SANDBOX_ROOT}/work"
mkdir -p "$WORK"

# 병합 엔진 로드 (서브셸에서 매 케이스 fresh 하게 쓰기 위해 경로만 기억)
ENGINE="${REPO_DIR}/lib/merge-settings.sh"

# 케이스 헬퍼: 지정 settings/fragment 로 병합 실행 (전역 오염 방지 위해 서브셸)
#   $1 settings, $2 fragment, $3 manifest("" 이면 미사용), $4 legacy removals("")
run_merge() {
    (
        . "$ENGINE"
        MERGE_MANIFEST="${3:-}"
        MERGE_LEGACY_REMOVALS="${4:-}"
        export MERGE_MANIFEST MERGE_LEGACY_REMOVALS
        merge_settings_fragment "$1" "$2"
    )
}

# 백업 retention 단독 실행 (엔진은 서브셸에서만 로드된다 — 위 run_merge 와 동일 규약)
#   $1 = 원본 파일, $2 = 보존 개수
run_prune() {
    (
        . "$ENGINE"
        MERGE_BACKUP_KEEP="${2:-3}"
        export MERGE_BACKUP_KEEP
        msf_prune_backups "$1"
    )
}

# node 폴백 강제 병합
run_merge_nodeonly() {
    (
        . "$ENGINE"
        MERGE_MANIFEST="${3:-}"
        MERGE_LEGACY_REMOVALS="${4:-}"
        export MERGE_MANIFEST MERGE_LEGACY_REMOVALS
        merge_settings_fragment "$1" "$2"
    )
}

# ============================================================================
echo "=== M1: 기존 이벤트에 새 command 가 append 되어야 한다 (jq 리바인딩 회귀) ==="
# ============================================================================
D="${WORK}/m1"; mkdir -p "$D"
cat > "${D}/settings.json" <<'EOF'
{
  "hooks": {
    "PostToolUse": [
      { "matcher": "Edit|Write", "hooks": [ { "type": "command", "command": "existing-cmd-A" } ] }
    ]
  }
}
EOF
cat > "${D}/frag.json" <<'EOF'
{
  "hooks": {
    "PostToolUse": [
      { "matcher": "Edit|Write", "hooks": [ { "type": "command", "command": "new-cmd-B" } ] }
    ]
  }
}
EOF
run_merge "${D}/settings.json" "${D}/frag.json"
CMDS="$(settings_commands "${D}/settings.json" | sort | tr '\n' ' ')"
if printf '%s' "$CMDS" | grep -q 'new-cmd-B'; then
    pass "M1 새 command 가 기존 이벤트에 추가됨"
else
    fail "M1 새 command 미추가 (결과: ${CMDS})"
fi
if printf '%s' "$CMDS" | grep -q 'existing-cmd-A'; then
    pass "M1 기존 command 보존"
else
    fail "M1 기존 command 소실 (결과: ${CMDS})"
fi
# 같은 matcher 엔트리에 병합됐는지 (엔트리 분열 없이)
ENTRIES="$(jq -r '.hooks.PostToolUse | length' "${D}/settings.json")"
if [ "$ENTRIES" = "1" ]; then
    pass "M1 같은 matcher 엔트리로 병합 (엔트리 1개 유지)"
else
    fail "M1 엔트리가 ${ENTRIES}개로 분열"
fi

# ============================================================================
echo "=== M2: 부분 겹침 시 기존 command 중복이 생기지 않아야 한다 ==="
# ============================================================================
D="${WORK}/m2"; mkdir -p "$D"
cat > "${D}/settings.json" <<'EOF'
{
  "hooks": {
    "PostToolUse": [
      { "matcher": "Write", "hooks": [ { "type": "command", "command": "shared-cmd" } ] }
    ]
  }
}
EOF
cat > "${D}/frag.json" <<'EOF'
{
  "hooks": {
    "PostToolUse": [
      { "matcher": "Write", "hooks": [
        { "type": "command", "command": "shared-cmd" },
        { "type": "command", "command": "extra-cmd" }
      ] }
    ]
  }
}
EOF
run_merge "${D}/settings.json" "${D}/frag.json"
DUP="$(settings_commands "${D}/settings.json" | grep -c '^shared-cmd$')"
if [ "$DUP" = "1" ]; then
    pass "M2 shared-cmd 중복 없음 (1회)"
else
    fail "M2 shared-cmd 가 ${DUP}회 존재 (부분중복 append 회귀)"
fi
if settings_commands "${D}/settings.json" | grep -q '^extra-cmd$'; then
    pass "M2 신규 extra-cmd 추가됨"
else
    fail "M2 신규 extra-cmd 미추가"
fi

# ============================================================================
echo "=== M3: jq 경로와 node 폴백이 동일 결과를 내야 한다 (parity) ==="
# ============================================================================
D="${WORK}/m3"; mkdir -p "$D"
cat > "${D}/base.json" <<'EOF'
{
  "env": { "FOO": "bar" },
  "permissions": { "allow": ["Bash(git status *)"], "deny": ["Read(./.env)"] },
  "hooks": {
    "PostToolUse": [
      { "matcher": "Write", "hooks": [ { "type": "command", "command": "shared-cmd" } ] }
    ],
    "Stop": [
      { "hooks": [ { "type": "command", "command": "user-stop-hook" } ] }
    ]
  }
}
EOF
cat > "${D}/frag.json" <<'EOF'
{
  "permissions": { "allow": ["Bash(git diff *)"] },
  "hooks": {
    "PostToolUse": [
      { "matcher": "Write", "hooks": [
        { "type": "command", "command": "shared-cmd" },
        { "type": "command", "command": "extra-cmd" }
      ] },
      { "matcher": "Edit", "hooks": [ { "type": "command", "command": "edit-cmd" } ] }
    ]
  }
}
EOF
cp "${D}/base.json" "${D}/via-jq.json"
cp "${D}/base.json" "${D}/via-node.json"
run_merge "${D}/via-jq.json" "${D}/frag.json"
run_without_jq run_merge_nodeonly "${D}/via-node.json" "${D}/frag.json"
if [ -s "${D}/via-node.json" ] && cmp -s "${D}/via-jq.json" "${D}/via-node.json"; then
    pass "M3 jq/node 결과 바이트 동일"
else
    fail "M3 jq/node 결과 불일치: $(diff <(jq -S . "${D}/via-jq.json" 2>/dev/null) <(jq -S . "${D}/via-node.json" 2>/dev/null) | head -5 | tr '\n' ' ')"
fi

# ============================================================================
echo "=== M4: 동일 병합 재실행은 unchanged (멱등) ==="
# ============================================================================
H_BEFORE="$(file_hash "${D}/via-jq.json")"
run_merge "${D}/via-jq.json" "${D}/frag.json"
H_AFTER="$(file_hash "${D}/via-jq.json")"
if [ "$H_BEFORE" = "$H_AFTER" ]; then
    pass "M4 재병합 무변경 (멱등)"
else
    fail "M4 재병합에 파일 변경됨"
fi

# ============================================================================
echo "=== M5: 사용자 hook·알 수 없는 키 보존 ==="
# ============================================================================
if settings_commands "${D}/via-jq.json" | grep -q '^user-stop-hook$'; then
    pass "M5 사용자 Stop hook 보존"
else
    fail "M5 사용자 Stop hook 소실"
fi
if [ "$(jq -r '.env.FOO' "${D}/via-jq.json")" = "bar" ]; then
    pass "M5 env 키 보존"
else
    fail "M5 env 키 소실/변형"
fi
if [ "$(jq -rc '.permissions.deny' "${D}/via-jq.json")" = '["Read(./.env)"]' ]; then
    pass "M5 permissions.deny 보존"
else
    fail "M5 permissions.deny 소실: $(jq -rc '.permissions.deny' "${D}/via-jq.json")"
fi
if [ "$(jq -rc '.permissions.allow | index("Bash(git status *)")' "${D}/via-jq.json")" != "null" ]; then
    pass "M5 기존 permissions.allow 항목 보존"
else
    fail "M5 기존 permissions.allow 항목 소실"
fi

# ============================================================================
echo "=== M6: matcher 는 identity 의 일부 — 같은 command 라도 matcher 다르면 별개 ==="
# ============================================================================
D="${WORK}/m6"; mkdir -p "$D"
cat > "${D}/settings.json" <<'EOF'
{
  "hooks": {
    "PostToolUse": [
      { "matcher": "Edit", "hooks": [ { "type": "command", "command": "same-cmd" } ] }
    ]
  }
}
EOF
cat > "${D}/frag.json" <<'EOF'
{
  "hooks": {
    "PostToolUse": [
      { "matcher": "Write", "hooks": [ { "type": "command", "command": "same-cmd" } ] }
    ]
  }
}
EOF
run_merge "${D}/settings.json" "${D}/frag.json"
W_CNT="$(jq -r '[.hooks.PostToolUse[] | select((.matcher // "") == "Write")] | length' "${D}/settings.json")"
E_CNT="$(jq -r '[.hooks.PostToolUse[] | select((.matcher // "") == "Edit")] | length' "${D}/settings.json")"
if [ "$W_CNT" = "1" ] && [ "$E_CNT" = "1" ]; then
    pass "M6 matcher 별 별개 엔트리 (Edit 1 + Write 1)"
else
    fail "M6 matcher identity 미반영 (Write=${W_CNT}, Edit=${E_CNT})"
fi

# ============================================================================
echo "=== M7: 같은 fragment 안의 동일 identity 2회 → 1회만 반영 ==="
# ============================================================================
D="${WORK}/m7"; mkdir -p "$D"
printf '{}\n' > "${D}/settings.json"
cat > "${D}/frag.json" <<'EOF'
{
  "hooks": {
    "Stop": [
      { "hooks": [ { "type": "command", "command": "dup-cmd" } ] },
      { "hooks": [ { "type": "command", "command": "dup-cmd" } ] }
    ]
  }
}
EOF
run_merge "${D}/settings.json" "${D}/frag.json"
DUP="$(settings_commands "${D}/settings.json" | grep -c '^dup-cmd$')"
if [ "$DUP" = "1" ]; then
    pass "M7 fragment 내부 중복 identity 1회만 반영"
else
    fail "M7 fragment 내부 중복이 ${DUP}회 반영됨"
fi

# ============================================================================
echo "=== M8: malformed settings → 실패 + 파일 무변경 ==="
# ============================================================================
D="${WORK}/m8"; mkdir -p "$D"
printf '{ broken json\n' > "${D}/settings.json"
cat > "${D}/frag.json" <<'EOF'
{ "hooks": { "Stop": [ { "hooks": [ { "type": "command", "command": "x" } ] } ] } }
EOF
H_BEFORE="$(file_hash "${D}/settings.json")"
if run_merge "${D}/settings.json" "${D}/frag.json" >/dev/null 2>&1; then
    fail "M8 malformed settings 인데 병합이 성공 반환"
else
    pass "M8 malformed settings 에서 실패 반환"
fi
H_AFTER="$(file_hash "${D}/settings.json")"
if [ "$H_BEFORE" = "$H_AFTER" ]; then
    pass "M8 실패 시 원본 무변경"
else
    fail "M8 실패했는데 원본이 변경됨"
fi

# ============================================================================
echo "=== M9: manifest 기반 upgrade — 조각 개정 시 stale 소유 hook 제거 + 사용자 보존 ==="
# ============================================================================
D="${WORK}/m9"; mkdir -p "$D"
printf '{}\n' > "${D}/settings.json"
cat > "${D}/frag-v1.json" <<'EOF'
{
  "hooks": {
    "PostToolUse": [
      { "matcher": "Write", "hooks": [
        { "type": "command", "command": "old-owned-cmd" },
        { "type": "command", "command": "kept-owned-cmd" }
      ] }
    ]
  },
  "permissions": { "allow": ["Bash(old-broad *)", "Bash(kept-narrow *)"] }
}
EOF
cat > "${D}/frag-v2.json" <<'EOF'
{
  "hooks": {
    "PostToolUse": [
      { "matcher": "Write", "hooks": [ { "type": "command", "command": "kept-owned-cmd" } ] }
    ]
  },
  "permissions": { "allow": ["Bash(kept-narrow *)"] }
}
EOF
MANIFEST="${D}/manifest.txt"
: > "$MANIFEST"
# v1 병합 (소유 기록). 신규 레코드는 MERGE_NEW_RECORDS 로 반환되어야 한다.
(
    . "$ENGINE"
    MERGE_MANIFEST="$MANIFEST"
    merge_settings_fragment "${D}/settings.json" "${D}/frag-v1.json" || exit 1
    printf '%s\n' "$MERGE_NEW_RECORDS" >> "$MANIFEST"
)
# 사용자가 직접 훅과 allow 를 추가 (installer 소유 아님)
jq '.hooks.PostToolUse += [{ "matcher": "Write", "hooks": [ { "type": "command", "command": "user-own-cmd" } ] }]
    | .permissions.allow += ["Bash(user-rule *)"]' \
    "${D}/settings.json" > "${D}/tmp.json" && mv "${D}/tmp.json" "${D}/settings.json"
# v2 로 upgrade — 같은 fragment id 를 위해 파일명을 맞춘다
cp "${D}/frag-v2.json" "${D}/frag-v1.json"
(
    . "$ENGINE"
    MERGE_MANIFEST="$MANIFEST"
    merge_settings_fragment "${D}/settings.json" "${D}/frag-v1.json" || exit 1
)
CMDS="$(settings_commands "${D}/settings.json")"
if printf '%s\n' "$CMDS" | grep -q '^old-owned-cmd$'; then
    fail "M9 stale 소유 hook(old-owned-cmd)이 잔존"
else
    pass "M9 stale 소유 hook 제거됨"
fi
if printf '%s\n' "$CMDS" | grep -q '^kept-owned-cmd$'; then
    pass "M9 유지 대상 소유 hook 보존"
else
    fail "M9 유지 대상 소유 hook 이 사라짐"
fi
if printf '%s\n' "$CMDS" | grep -q '^user-own-cmd$'; then
    pass "M9 사용자 hook 보존"
else
    fail "M9 사용자 hook 이 제거됨"
fi
ALLOW="$(jq -rc '.permissions.allow' "${D}/settings.json")"
case "$ALLOW" in
    *'Bash(old-broad *)'*) fail "M9 stale 소유 allow 잔존: ${ALLOW}" ;;
    *) pass "M9 stale 소유 allow 제거됨" ;;
esac
case "$ALLOW" in
    *'Bash(user-rule *)'*) pass "M9 사용자 allow 보존" ;;
    *) fail "M9 사용자 allow 소실: ${ALLOW}" ;;
esac
case "$ALLOW" in
    *'Bash(kept-narrow *)'*) pass "M9 유지 대상 소유 allow 보존" ;;
    *) fail "M9 유지 대상 소유 allow 소실: ${ALLOW}" ;;
esac

# ============================================================================
echo "=== M10: MERGE_LEGACY_REMOVALS — manifest 없는 기존 설치의 기지(旣知) stale 제거 ==="
# ============================================================================
D="${WORK}/m10"; mkdir -p "$D"
cat > "${D}/settings.json" <<'EOF'
{
  "hooks": {
    "PostToolUse": [
      { "matcher": "Write(*.tsx)", "hooks": [
        { "type": "command", "command": "npx tsc --noEmit" },
        { "type": "command", "command": "npm run lint:fix" }
      ] },
      { "matcher": "Write(*.tsx)", "hooks": [ { "type": "command", "command": "user-kept-cmd" } ] }
    ]
  },
  "permissions": { "allow": ["Bash(npm *)", "Bash(user-rule *)"] }
}
EOF
cat > "${D}/frag.json" <<'EOF'
{ "hooks": { "Stop": [ { "matcher": "", "hooks": [ { "type": "command", "command": "new-stop" } ] } ] } }
EOF
LEGACY="$(printf 'hook\tPostToolUse\tWrite(*.tsx)\tnpx tsc --noEmit\nhook\tPostToolUse\tWrite(*.tsx)\tnpm run lint:fix\nperm\tallow\tBash(npm *)')"
run_merge "${D}/settings.json" "${D}/frag.json" "" "$LEGACY"
CMDS="$(settings_commands "${D}/settings.json")"
if printf '%s\n' "$CMDS" | grep -q 'lint:fix\|npx tsc'; then
    fail "M10 legacy stale hook 잔존: $(printf '%s' "$CMDS" | tr '\n' ' ')"
else
    pass "M10 legacy stale hook 2종 제거"
fi
if printf '%s\n' "$CMDS" | grep -q '^user-kept-cmd$'; then
    pass "M10 동일 matcher 의 사용자 hook 보존"
else
    fail "M10 사용자 hook 이 함께 제거됨"
fi
ALLOW="$(jq -rc '.permissions.allow' "${D}/settings.json")"
case "$ALLOW" in
    *'Bash(npm *)'*) fail "M10 legacy 광범위 allow 잔존: ${ALLOW}" ;;
    *) pass "M10 legacy 광범위 allow 제거" ;;
esac
case "$ALLOW" in
    *'Bash(user-rule *)'*) pass "M10 사용자 allow 보존" ;;
    *) fail "M10 사용자 allow 소실: ${ALLOW}" ;;
esac
# 빈 엔트리 정리: command 가 모두 제거된 엔트리는 남지 않아야 한다
EMPTY="$(jq -r '[.hooks.PostToolUse[]? | select((.hooks | length) == 0)] | length' "${D}/settings.json")"
if [ "$EMPTY" = "0" ]; then
    pass "M10 빈 hook 엔트리 정리됨"
else
    fail "M10 빈 hook 엔트리 ${EMPTY}개 잔존"
fi

# ============================================================================
echo "=== M11: node 폴백에서도 manifest upgrade 동일 동작 ==="
# ============================================================================
D="${WORK}/m11"; mkdir -p "$D"
printf '{}\n' > "${D}/settings.json"
cat > "${D}/frag.json" <<'EOF'
{ "hooks": { "PostToolUse": [ { "matcher": "Write", "hooks": [
  { "type": "command", "command": "old-owned-cmd" },
  { "type": "command", "command": "kept-owned-cmd" } ] } ] } }
EOF
MANIFEST="${D}/manifest.txt"
: > "$MANIFEST"
run_without_jq bash -c '
    . "'"$ENGINE"'"
    MERGE_MANIFEST="'"$MANIFEST"'"
    merge_settings_fragment "'"${D}/settings.json"'" "'"${D}/frag.json"'" || exit 1
    printf "%s\n" "$MERGE_NEW_RECORDS" >> "'"$MANIFEST"'"
'
cat > "${D}/frag.json" <<'EOF'
{ "hooks": { "PostToolUse": [ { "matcher": "Write", "hooks": [
  { "type": "command", "command": "kept-owned-cmd" } ] } ] } }
EOF
run_without_jq bash -c '
    . "'"$ENGINE"'"
    MERGE_MANIFEST="'"$MANIFEST"'"
    merge_settings_fragment "'"${D}/settings.json"'" "'"${D}/frag.json"'"
'
CMDS="$(settings_commands "${D}/settings.json")"
if printf '%s\n' "$CMDS" | grep -q '^old-owned-cmd$'; then
    fail "M11 node 폴백에서 stale 소유 hook 잔존"
else
    pass "M11 node 폴백 stale 소유 hook 제거"
fi
if printf '%s\n' "$CMDS" | grep -q '^kept-owned-cmd$'; then
    pass "M11 node 폴백 유지 대상 보존"
else
    fail "M11 node 폴백 유지 대상 소실"
fi

# ============================================================================
echo "=== M12: 백업 bounded retention (같은 파일 반복 병합 → .bak* 최대 3개) ==="
# ============================================================================
D="${WORK}/m12"; mkdir -p "$D"
printf '{}\n' > "${D}/settings.json"
i=1
while [ "$i" -le 5 ]; do
    cat > "${D}/frag.json" <<EOF
{ "hooks": { "Stop": [ { "hooks": [ { "type": "command", "command": "cmd-${i}" } ] } ] } }
EOF
    run_merge "${D}/settings.json" "${D}/frag.json" "${D}/.settings-manifest"
    i=$((i + 1))
done
BAKS="$(count_baks_of "${D}/settings.json")"
if [ "$BAKS" -le 3 ] && [ "$BAKS" -ge 1 ]; then
    pass "M12 백업 bounded (${BAKS}개 ≤ 3)"
else
    fail "M12 백업 ${BAKS}개 — bounded retention 미동작"
fi

# ============================================================================
echo "=== M13: bounded retention 이 '가장 오래된 것'을 지우는지 (생존자 신원) ==="
# ============================================================================
# 개수만 세면 무엇이 지워졌는지 알 수 없다. mtime 을 고정해 신원까지 확인한다.
D13="${WORK}/m13 dir with space"; mkdir -p "$D13"
T13="${D13}/settings.json"
printf '{}\n' > "$T13"
i=1
while [ "$i" -le 5 ]; do
    printf 'v%s\n' "$i" > "${T13}.bak.${i}"
    i=$((i + 1))
done
# 이름 순서와 mtime 순서를 "반대로" 준다. 디렉토리 나열 순서에 기대는 구현은
# 여기서 반드시 틀린다 — 이름이 빠른 .bak.1 이 가장 최신이다.
touch -t 202601050101 "${T13}.bak.1"   # 최신
touch -t 202601040101 "${T13}.bak.2"
touch -t 202601030101 "${T13}.bak.3"
touch -t 202601020101 "${T13}.bak.4"
touch -t 202601010101 "${T13}.bak.5"   # 가장 오래됨

# 새 계약: prune 은 설치기가 만든 백업만 지운다 → 실제 경로처럼 색인에 등록한다
own_prune13() {
    (
        . "$ENGINE"
        MERGE_MANIFEST="${D13}/.settings-manifest"
        export MERGE_MANIFEST
        for b in "${T13}.bak.1" "${T13}.bak.2" "${T13}.bak.3" "${T13}.bak.4" "${T13}.bak.5"; do
            msf_backup_record "$b"
        done
        MERGE_BACKUP_KEEP=3 msf_prune_backups "$T13"
    )
}
own_prune13

M13_LEFT="$(find "$D13" -maxdepth 1 -name 'settings.json.bak.*' 2>/dev/null | wc -l | tr -d ' ')"
if [ "$M13_LEFT" -eq 3 ]; then
    pass "M13 백업 3개만 남음"
else
    fail "M13 백업 ${M13_LEFT}개 남음 (기대 3)"
fi
# mtime 이 가장 오래된 둘 = .bak.5, .bak.4
if [ ! -e "${T13}.bak.5" ] && [ ! -e "${T13}.bak.4" ]; then
    pass "M13 가장 오래된 2개(.bak.5,.bak.4)가 삭제됨"
else
    fail "M13 오래된 백업이 살아남음: $(ls "${T13}.bak.5" "${T13}.bak.4" 2>/dev/null | tr '\n' ' ')"
fi
M13_OK=true
for want in 1 2 3; do
    if [ ! -f "${T13}.bak.${want}" ] || [ "$(cat "${T13}.bak.${want}" 2>/dev/null)" != "v${want}" ]; then
        M13_OK=false
    fi
done
if $M13_OK; then
    pass "M13 최신 3개(.bak.1,.bak.2,.bak.3)가 내용까지 그대로 보존됨"
else
    fail "M13 최신 백업이 삭제/훼손됨 — 남은 것: $(for k in 1 2 3 4 5; do [ -f "${T13}.bak.${k}" ] && printf '%s ' "${k}"; done)"
fi

# ============================================================================
echo "=== M14: 소유 집합 = 이번 fragment identity - 사용자가 이미 갖고 있던 것 ==="
# ============================================================================
# 조각이 선언한 identity 가 "병합 전 settings 에 이미 있었고 우리가 소유한 적도 없는"
# 것이라면 그것은 사용자가 직접 넣은 것이다. 소유로 기록하면 --uninstall 이 사용자
# 항목을 지운다(README Uninstall Policy 위반).
# 동시에, 재실행에서 prev(이전 소유)를 빼지 않으면 "이미 있으니 사용자 것"으로 오판해
# 소유 기록이 통째로 비고 uninstall 이 무력화된다 — 양방향을 모두 고정한다.
D="${WORK}/m14"; mkdir -p "$D"
cat > "${D}/settings.json" <<'EOF'
{
  "hooks": {
    "Stop": [
      { "matcher": "", "hooks": [ { "type": "command", "command": "user-preexisting-cmd" } ] }
    ]
  },
  "permissions": { "allow": ["Bash(user-owns-this)"] }
}
EOF
# 조각이 사용자 항목과 "같은 identity" 를 함께 선언한다 (겹침)
cat > "${D}/frag.json" <<'EOF'
{
  "hooks": {
    "Stop": [
      { "matcher": "", "hooks": [
        { "type": "command", "command": "user-preexisting-cmd" },
        { "type": "command", "command": "frag-only-cmd" }
      ] }
    ]
  },
  "permissions": { "allow": ["Bash(user-owns-this)", "Bash(frag-only-rule)"] }
}
EOF
M14_MAN="${D}/manifest.txt"
run_merge "${D}/settings.json" "${D}/frag.json" "$M14_MAN"

if grep -q 'frag-only-cmd' "$M14_MAN" 2>/dev/null; then
    pass "M14 조각 고유 hook 은 소유로 기록"
else
    fail "M14 조각 고유 hook 이 소유로 기록되지 않음: $(cat "$M14_MAN" 2>/dev/null | tr '\n' ' ')"
fi
if grep -q 'user-preexisting-cmd' "$M14_MAN" 2>/dev/null; then
    fail "M14 사용자가 이미 갖고 있던 hook 을 소유로 기록함 (uninstall 이 사용자 것을 지운다)"
else
    pass "M14 사용자 선점 hook 은 비소유"
fi
if grep -q 'Bash(user-owns-this)' "$M14_MAN" 2>/dev/null; then
    fail "M14 사용자가 이미 갖고 있던 allow 를 소유로 기록함"
else
    pass "M14 사용자 선점 allow 는 비소유"
fi

# 재실행: 우리 것은 계속 소유여야 한다 (prev 를 빼지 않으면 여기서 비어버린다)
run_merge "${D}/settings.json" "${D}/frag.json" "$M14_MAN"
if grep -q 'frag-only-cmd' "$M14_MAN" 2>/dev/null; then
    pass "M14 재실행 후에도 조각 고유 hook 소유 유지"
else
    fail "M14 재실행에서 소유 기록이 사라짐 (prev 미차감 회귀) — manifest: $(cat "$M14_MAN" 2>/dev/null | tr '\n' ' ')"
fi
if grep -q 'frag-only-rule' "$M14_MAN" 2>/dev/null; then
    pass "M14 재실행 후에도 조각 고유 allow 소유 유지"
else
    fail "M14 재실행에서 allow 소유 기록이 사라짐"
fi

# uninstall: 우리 것만 사라지고 사용자 것은 남아야 한다
(
    . "$ENGINE"
    MERGE_MANIFEST="$M14_MAN"
    export MERGE_MANIFEST
    unmerge_settings_fragment "${D}/settings.json" "frag.json"
) >/dev/null 2>&1
M14_CMDS="$(settings_commands "${D}/settings.json")"
M14_ALLOW="$(jq -rc '.permissions.allow // []' "${D}/settings.json")"
if printf '%s\n' "$M14_CMDS" | grep -q '^user-preexisting-cmd$'; then
    pass "M14 uninstall 후 사용자 hook 보존"
else
    fail "M14 uninstall 이 사용자 hook 을 삭제함"
fi
case "$M14_ALLOW" in
    *'Bash(user-owns-this)'*) pass "M14 uninstall 후 사용자 allow 보존" ;;
    *) fail "M14 uninstall 이 사용자 allow 를 삭제함: ${M14_ALLOW}" ;;
esac
if printf '%s\n' "$M14_CMDS" | grep -q '^frag-only-cmd$'; then
    fail "M14 uninstall 이 조각 고유 hook 을 제거하지 못함"
else
    pass "M14 uninstall 이 조각 고유 hook 제거"
fi

# ============================================================================
echo "=== M15: 소유 기록 실패 시 settings 를 원래대로 되돌린다 ==="
# ============================================================================
# 엔진 단독으로도 일관성을 지켜야 한다. settings 만 바뀌고 기록이 없으면 그 훅들은
# 영원히 uninstall 대상이 되지 못한다 — 실패했으면 아무것도 바뀌지 않아야 한다.
D="${WORK}/m15"; mkdir -p "$D"
cat > "${D}/settings.json" <<'EOF'
{ "hooks": { "Stop": [ { "matcher": "", "hooks": [ { "type": "command", "command": "orig-cmd" } ] } ] } }
EOF
ORIG15="$(file_hash "${D}/settings.json")"
cat > "${D}/frag.json" <<'EOF'
{ "hooks": { "Stop": [ { "matcher": "", "hooks": [ { "type": "command", "command": "new-cmd" } ] } ] } }
EOF
mkdir -p "${D}/blocked-manifest"     # 디렉토리라 기록이 불가능하다
if run_merge "${D}/settings.json" "${D}/frag.json" "${D}/blocked-manifest" >/dev/null 2>&1; then
    fail "M15 기록 불가인데 병합이 성공 반환"
else
    pass "M15 기록 불가 시 실패 반환"
fi
if [ "$ORIG15" = "$(file_hash "${D}/settings.json")" ]; then
    pass "M15 실패 시 settings 원상 복구 (부분 적용 없음)"
else
    fail "M15 settings 만 바뀌고 기록은 없는 상태로 남음: $(settings_commands "${D}/settings.json" | tr '\n' ' ')"
fi

# ============================================================================
echo "=== M16: 소유 색인 불가 시 백업을 지우지 않는다 (fail-closed) ==="
# ============================================================================
# 색인을 만들 수 없으면(디렉토리 등) "전부 우리 것" 으로 되돌아가면 안 된다 —
# 사용자가 만든 settings.json.bak* 가 상한을 넘는 순간 삭제된다.
D16="${WORK}/m16"; mkdir -p "$D16"
printf '{}\n' > "${D16}/settings.json"
i=1
while [ "$i" -le 5 ]; do
    printf 'user backup %s\n' "$i" > "${D16}/settings.json.bak.${i}"
    i=$((i + 1))
done
mkdir -p "${D16}/.settings-backups"        # 색인 자리를 디렉토리로 막는다
cat > "${D16}/frag.json" <<'EOF'
{ "hooks": { "Stop": [ { "hooks": [ { "type": "command", "command": "m16-cmd" } ] } ] } }
EOF
run_merge "${D16}/settings.json" "${D16}/frag.json" "${D16}/.settings-manifest" >/dev/null 2>&1
M16_KEPT=0
i=1
while [ "$i" -le 5 ]; do
    [ -f "${D16}/settings.json.bak.${i}" ] && M16_KEPT=$((M16_KEPT + 1))
    i=$((i + 1))
done
if [ "$M16_KEPT" -eq 5 ]; then
    pass "M16 색인 불가 시 사용자 백업 5건 전부 보존"
else
    fail "M16 색인 불가인데 백업을 지움 (${M16_KEPT}/5 생존)"
fi

# ============================================================================
echo "=== M17: settings 백업도 경로 재사용에 안전해야 한다 ==="
# ============================================================================
D17="${WORK}/m17"; mkdir -p "$D17"
printf '{}\n' > "${D17}/settings.json"
M17MAN="${D17}/.settings-manifest"
(
    . "$ENGINE"
    MERGE_MANIFEST="$M17MAN"; export MERGE_MANIFEST
    printf 'installer backup\n' > "${D17}/settings.json.bak"
    msf_backup_record "${D17}/settings.json.bak"
)
rm -f "${D17}/settings.json.bak"
printf 'USER FILE — keep\n' > "${D17}/settings.json.bak"
i=1
while [ "$i" -le 4 ]; do
    printf 'installer v%s\n' "$i" > "${D17}/settings.json.bak.${i}"
    ( . "$ENGINE"; MERGE_MANIFEST="$M17MAN"; export MERGE_MANIFEST
      msf_backup_record "${D17}/settings.json.bak.${i}" )
    touch -t "20260${i}010101" "${D17}/settings.json.bak.${i}"
    i=$((i + 1))
done
touch -t 202512010101 "${D17}/settings.json.bak"
( . "$ENGINE"
  MERGE_MANIFEST="$M17MAN"; export MERGE_MANIFEST
  MERGE_BACKUP_KEEP=2 msf_prune_backups "${D17}/settings.json" )
if [ -f "${D17}/settings.json.bak" ] && grep -q 'USER FILE' "${D17}/settings.json.bak"; then
    pass "M17 경로를 재사용한 사용자 파일 보존"
else
    fail "M17 settings retention 이 사용자 파일을 삭제함"
fi

# ============================================================================
echo "=== M18: unmerge 는 사용자 중복본과 다른 조각의 소유분을 남긴다 ==="
# ============================================================================
# (a) 사용자가 우리와 같은 identity 를 하나 더 넣어 두면, 제거는 **우리 몫 하나만**
#     지워야 한다. 전부 지우면 사용자가 넣은 것까지 사라진다.
D18="${WORK}/m18"; mkdir -p "$D18"
cat > "${D18}/settings.json" <<'EOF'
{
  "hooks": {
    "Stop": [
      { "matcher": "", "hooks": [
        { "type": "command", "command": "shared-cmd" },
        { "type": "command", "command": "shared-cmd" }
      ] }
    ]
  }
}
EOF
printf 'a.json\thook\tStop\t\tshared-cmd\n' > "${D18}/.settings-manifest"
(
    . "$ENGINE"
    MERGE_MANIFEST="${D18}/.settings-manifest"; export MERGE_MANIFEST
    unmerge_settings_fragment "${D18}/settings.json" "a.json"
) >/dev/null 2>&1
M18_N="$(settings_commands "${D18}/settings.json" | grep -c '^shared-cmd$' || true)"
if [ "$M18_N" -eq 1 ]; then
    pass "M18 중복 중 우리 몫 하나만 제거 (사용자 중복본 보존)"
else
    fail "M18 shared-cmd 가 ${M18_N}개 남음 (기대 1) — 전부 제거되어 사용자 것까지 사라졌다"
fi

# (b) 같은 identity 를 아직 살아 있는 다른 조각이 소유하고 있으면 남겨야 한다.
D18B="${WORK}/m18b"; mkdir -p "$D18B"
cat > "${D18B}/settings.json" <<'EOF'
{
  "hooks": {
    "Stop": [
      { "matcher": "", "hooks": [ { "type": "command", "command": "co-owned-cmd" } ] }
    ]
  }
}
EOF
printf 'a.json\thook\tStop\t\tco-owned-cmd\n'  > "${D18B}/.settings-manifest"
printf 'b.json\thook\tStop\t\tco-owned-cmd\n' >> "${D18B}/.settings-manifest"
(
    . "$ENGINE"
    MERGE_MANIFEST="${D18B}/.settings-manifest"; export MERGE_MANIFEST
    unmerge_settings_fragment "${D18B}/settings.json" "a.json"
) >/dev/null 2>&1
if settings_commands "${D18B}/settings.json" | grep -q '^co-owned-cmd$'; then
    pass "M18b 다른 조각이 아직 소유한 identity 는 보존"
else
    fail "M18b 살아 있는 다른 조각의 소유분까지 제거됨"
fi

finish
