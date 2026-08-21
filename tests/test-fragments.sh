#!/bin/bash
set -uo pipefail
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "${REPO_DIR}/tests/helpers.sh"
init_sandbox

# ==================== JSON Fragments Tests ====================
echo "=== F1: JSON parse all fragments ==="
for dir in "${REPO_DIR}/project/settings-fragments" "${REPO_DIR}/global/settings-fragments"; do
    [ -d "$dir" ] || continue
    for frag in "$dir"/*.json; do
        [ -f "$frag" ] || continue
        name="$(basename "$frag")"
        if jq empty "$frag" 2>&1 >/dev/null; then
            pass "F1 JSON valid: $name"
        else
            fail "F1 JSON invalid: $name"
        fi
    done
done

# ==================== cli-orchestration Tests ====================
echo "=== F2: cli-orchestration allow list — 인자 허용 접두 문법 + 광범위 금지 ==="
CLI_ORK="${REPO_DIR}/project/settings-fragments/cli-orchestration.json"
# 인자를 받는 명령은 정확 매칭이면 무용지물이다 ("git add" 는 인자 없는 호출만
# 허용하는데 그런 호출은 아무 일도 하지 않는다). 접두 문법 `cmd:*` 을 써야 한다.
for cmd in "Bash(git add:*)" "Bash(git commit:*)" "Bash(git push:*)" \
           "Bash(git pull:*)" "Bash(git branch:*)" "Bash(git checkout:*)" \
           "Bash(npm run build:*)" "Bash(npm run test:*)"; do
    if jq -r '.permissions.allow[]' "$CLI_ORK" 2>/dev/null | grep -qxF "$cmd"; then
        pass "F2 인자 허용 접두 항목 존재: $cmd"
    else
        fail "F2 인자 허용 접두 항목 없음: $cmd"
    fi
done
# 인자 없이 쓰는 명령은 정확 매칭 유지 (최소권한)
for cmd in "Bash(git status)" "Bash(npm install)"; do
    if jq -r '.permissions.allow[]' "$CLI_ORK" 2>/dev/null | grep -qxF "$cmd"; then
        pass "F2 무인자 명령은 정확 매칭 유지: $cmd"
    else
        fail "F2 무인자 명령이 사라짐: $cmd"
    fi
done
# 인자를 받는데 정확 매칭으로만 남아 있는 항목이 없어야 한다(무용지물 방지)
F2_DEAD=""
for cmd in "Bash(git add)" "Bash(git commit)" "Bash(git push)" "Bash(git pull)" \
           "Bash(git branch)" "Bash(git checkout)" "Bash(npm run build)" "Bash(npm run test)"; do
    if jq -r '.permissions.allow[]' "$CLI_ORK" 2>/dev/null | grep -qxF "$cmd"; then
        F2_DEAD="${F2_DEAD} ${cmd}"
    fi
done
if [ -z "$F2_DEAD" ]; then
    pass "F2 인자 불가 정확매칭 잔재 없음"
else
    fail "F2 인자를 못 받는 정확매칭이 남아 있음:${F2_DEAD}"
fi
# 광범위 권한이 되살아나지 않았는지 (이번 수정의 반대 방향 회귀 감시)
F2_BROAD=""
for bad in "Bash(git *)" "Bash(npm *)" "Bash(docker *)" "Bash(*)" "Bash(git:*)" "Bash(npm:*)"; do
    if jq -r '.permissions.allow[]' "$CLI_ORK" 2>/dev/null | grep -qxF "$bad"; then
        F2_BROAD="${F2_BROAD} ${bad}"
    fi
done
if [ -z "$F2_BROAD" ]; then
    pass "F2 광범위 권한 없음 (git */npm */docker */전체)"
else
    fail "F2 광범위 권한이 존재:${F2_BROAD}"
fi

# `cmd:*`(접두 매칭)은 정당한 문법이다. 금지 대상은 "공백 + *" 형태의 광범위
# 매칭(`Bash(git *)`)뿐이므로 그것만 걸러낸다.
if jq -r '.permissions.allow[]' "$CLI_ORK" 2>/dev/null | grep -q ' \*)'; then
    fail "F2 광범위 매칭(공백+*) 항목이 있음: $(jq -r '.permissions.allow[]' "$CLI_ORK" | grep ' \*)' | tr '\n' ' ')"
else
    pass "F2 광범위 매칭(공백+*) 항목 없음"
fi

# ==================== verification-hooks Tests ====================
echo "=== F3: verification-hooks removes Write(*.tsx) ==="
VH="${REPO_DIR}/project/settings-fragments/verification-hooks.json"
if jq '.hooks.PostToolUse[]?.matcher' "$VH" 2>/dev/null | grep -q 'Write(.*tsx'; then
    fail "F3 verification-hooks still has Write(*.tsx)"
else
    pass "F3 verification-hooks removed Write(*.tsx)"
fi

if jq '.hooks.PostToolUse[]?.hooks[]?.command' "$VH" 2>/dev/null | grep -q 'build-checker'; then
    pass "F3 verification-hooks has build-checker"
else
    fail "F3 verification-hooks missing build-checker"
fi

# ==================== guardrails JSON Tests ====================
echo "=== F4: guardrails python guards work ==="
GR="${REPO_DIR}/project/settings-fragments/guardrails.json"

# Test 1: Valid command passes
VALID_CMD='{"tool_input":{"command":"echo test"}}'
result=$(echo "$VALID_CMD" | python3 -c "import json,sys,os; d=json.load(sys.stdin); sys.exit(0)" 2>&1; echo $?)
if [ "$result" = "0" ]; then
    pass "F4 valid command passes JSON parse"
else
    fail "F4 valid command fails JSON parse"
fi

# Test 2: Malformed JSON fails (fail-closed)
BAD_JSON='{"tool_input": invalid}'
result=$(echo "$BAD_JSON" | python3 -c "import json,sys; json.load(sys.stdin)" 2>&1; echo $?)
if [ "$result" != "0" ]; then
    pass "F4 malformed JSON rejected"
else
    fail "F4 malformed JSON accepted"
fi

# Test 3: Forbidden command detected
FORBIDDEN='{"tool_input":{"command":"rm -rf /etc"}}'
# 주의: `python3 << 'TAG'` 는 히어독을 python 의 **stdin(=스크립트 소스)** 으로 만든다.
# 그러면 파이프의 페이로드가 python 에 도달하지 못하고 json.load 가 EOF 로 예외를 내
# except 절에서 exit 2 가 나온다 — 탐지 로직을 통째로 지워도 통과하는 영구 거짓 양성이었다.
# 스크립트는 파일로 주고 페이로드는 stdin 으로 준다(= Claude Code 가 하는 방식).
F4_CHK="${TMPDIR:-/tmp}/f4-check.$$.py"
cat > "$F4_CHK" <<'CHECKGUARD'
import json,sys
try:
    d=json.load(sys.stdin)
    c=d.get('tool_input',{}).get('command','')
    if 'rm -rf /etc' in c:
        sys.exit(2)
    sys.exit(0)
except Exception:
    sys.exit(3)
CHECKGUARD
result=$(echo "$FORBIDDEN" | python3 "$F4_CHK" >/dev/null 2>&1; echo $?)
rm -f "$F4_CHK"
if [ "$result" = "2" ]; then
    pass "F4 forbidden command rm -rf /etc detected"
else
    fail "F4 forbidden command rm -rf /etc not detected"
fi

# ==================== F6: 배포되는 guardrails 훅 "실행" 검증 ====================
# F4 는 테스트가 자기 인라인 python 을 돌려서 통과했다 — 실제 배포 문자열은
# 한 번도 실행되지 않았다. 여기서는 fragment 에 들어 있는 command 를 그대로
# 셸에 먹이고 훅 페이로드를 stdin 으로 준다 (Claude Code 가 하는 방식 그대로).
echo "=== F6: shipped guardrails hook commands executed as real hooks ==="
GUARD_FRAG="${REPO_DIR}/project/settings-fragments/guardrails.json"
G_BASH="$(jq -r '.hooks.PreToolUse[0].hooks[0].command' "$GUARD_FRAG")"
G_EDIT="$(jq -r '.hooks.PreToolUse[1].hooks[0].command' "$GUARD_FRAG")"

run_hook() {
    # $1 = 훅 명령 문자열, $2 = stdin 페이로드 → exit code 출력
    printf '%s' "$2" | bash -c "$1" >/dev/null 2>&1
    echo $?
}
expect_hook() {
    # $1 = 라벨, $2 = 훅, $3 = 페이로드, $4 = 기대 exit code
    local got
    got="$(run_hook "$2" "$3")"
    if [ "$got" = "$4" ]; then
        pass "F6 $1 (exit ${got})"
    else
        fail "F6 $1 — exit ${got}, 기대 ${4}"
    fi
}

expect_hook "정상 Bash 는 통과해야 한다 (npm run build)" \
    "$G_BASH" '{"tool_input":{"command":"npm run build"}}' 0
expect_hook "위험 Bash 는 차단 (rm -rf /etc)" \
    "$G_BASH" '{"tool_input":{"command":"rm -rf /etc"}}' 2
expect_hook "malformed JSON 은 fail-closed" \
    "$G_BASH" 'not-json' 2
expect_hook "경로 경계: /etcd-backup.tar 는 /etc 가 아니다" \
    "$G_BASH" '{"tool_input":{"command":"rm /etcd-backup.tar"}}' 0
expect_hook "경로 경계: /devops-notes.txt 는 /dev 가 아니다" \
    "$G_BASH" '{"tool_input":{"command":"rm /devops-notes.txt"}}' 0

# 루트/홈 "통째 삭제"는 글로브 형태가 정본이다. 정규식의 `/*` 는 슬래시 반복이지
# 글로브가 아니므로, 이 케이스들이 없으면 `rm -rf /*` 가 조용히 통과한다
# (실측: 통과했다). 오탐 방향(정상 경로 삭제)도 같이 고정해 둔다.
expect_hook "루트 통째 삭제 차단 (글로브 형태)" \
    "$G_BASH" '{"tool_input":{"command":"rm -rf /*"}}' 2
expect_hook "루트 통째 삭제 차단 (플래그 + 글로브)" \
    "$G_BASH" '{"tool_input":{"command":"rm -rf --no-preserve-root /*"}}' 2
expect_hook "루트 통째 삭제 차단 (플래그 순서 변형 -fr)" \
    "$G_BASH" '{"tool_input":{"command":"rm -fr /*"}}' 2
expect_hook "홈 통째 삭제 차단 (글로브 형태)" \
    "$G_BASH" '{"tool_input":{"command":"rm -rf ~/*"}}' 2
expect_hook "루트 통째 삭제 차단 (슬래시만)" \
    "$G_BASH" '{"tool_input":{"command":"rm -rf /"}}' 2
expect_hook "홈 통째 삭제 차단 (\$HOME 변수 형태)" \
    "$G_BASH" '{"tool_input":{"command":"rm -rf $HOME"}}' 2
expect_hook "홈 통째 삭제 차단 (\${HOME} 중괄호 + 글로브)" \
    "$G_BASH" '{"tool_input":{"command":"rm -rf ${HOME}/*"}}' 2
expect_hook "오탐 금지: 하위 경로 삭제는 통과 (rm -rf /tmp/x)" \
    "$G_BASH" '{"tool_input":{"command":"rm -rf /tmp/x"}}' 0
expect_hook "오탐 금지: 상대 경로 삭제는 통과 (rm -rf ./build)" \
    "$G_BASH" '{"tool_input":{"command":"rm -rf ./build"}}' 0
expect_hook "오탐 금지: 홈 하위 경로 삭제는 통과 (rm -rf ~/proj/node_modules)" \
    "$G_BASH" '{"tool_input":{"command":"rm -rf ~/proj/node_modules"}}' 0
expect_hook "오탐 금지: \$HOME 하위 경로 삭제는 통과" \
    "$G_BASH" '{"tool_input":{"command":"rm -rf $HOME/proj/dist"}}' 0
expect_hook "오탐 금지: \$HOMEDIR 은 \$HOME 이 아니다" \
    "$G_BASH" '{"tool_input":{"command":"rm -rf $HOMEDIR"}}' 0

expect_hook "정상 파일 쓰기는 통과 (src/app.ts)" \
    "$G_EDIT" '{"tool_input":{"file_path":"/home/u/src/app.ts"}}' 0
expect_hook "보호 경로 쓰기는 차단 (/etc/passwd)" \
    "$G_EDIT" '{"tool_input":{"file_path":"/etc/passwd"}}' 2
expect_hook ".env 쓰기는 차단" \
    "$G_EDIT" '{"tool_input":{"file_path":"/home/u/.env"}}' 2
expect_hook "Edit malformed JSON 은 fail-closed" \
    "$G_EDIT" 'garbage' 2
expect_hook "경로 경계: /etcd/config.yml 은 /etc 가 아니다" \
    "$G_EDIT" '{"tool_input":{"file_path":"/etcd/config.yml"}}' 0
expect_hook "경로 경계: /devtools/x.ts 는 /dev 가 아니다" \
    "$G_EDIT" '{"tool_input":{"file_path":"/devtools/x.ts"}}' 0

# 10MB stdin 상한: "차단됐다"만으로는 부족하다. 상한 때문에 막힌 것인지
# (malformed 로 막힌 것이 아닌지) stderr 사유까지 확인한다.
F6_BIG="${TMPDIR:-/tmp}/f6-big.$$"
F6_ERR="${TMPDIR:-/tmp}/f6-err.$$"
{
    printf '{"tool_input":{"command":"echo hi"}}'
    head -c 11000000 /dev/zero | tr '\0' ' '
} > "$F6_BIG" 2>/dev/null
bash -c "$G_BASH" < "$F6_BIG" >/dev/null 2>"$F6_ERR"
F6_CODE=$?
if [ "$F6_CODE" = "2" ] && grep -q '10MB' "$F6_ERR"; then
    pass "F6 10MB 초과 stdin 이 상한 사유로 차단됨 (exit 2)"
else
    fail "F6 10MB 상한 미동작 — exit ${F6_CODE}, stderr: $(head -1 "$F6_ERR")"
fi
# 상한 바로 아래는 정상 통과해야 한다 (상한이 모든 것을 막는 것이 아님을 증명)
{
    printf '{"tool_input":{"command":"echo '
    head -c 900000 /dev/zero | tr '\0' 'x'
    printf '"}}'
} > "$F6_BIG" 2>/dev/null
bash -c "$G_BASH" < "$F6_BIG" >/dev/null 2>&1
F6_CODE=$?
if [ "$F6_CODE" = "0" ]; then
    pass "F6 상한 미만(약 0.9MB) 페이로드는 정상 통과"
else
    fail "F6 상한 미만 페이로드가 차단됨 (exit ${F6_CODE})"
fi
rm -f "$F6_BIG" "$F6_ERR"

# ==================== F7: Notification 훅 — 스크립트 소스 인젝션 ====================
# .message 는 외부에서 오는 값이다. 그 값을 알림 스크립트 "소스 문자열"에
# 그대로 끼워 넣으면, 메시지 안의 따옴표로 임의 스크립트를 주입할 수 있다.
# 메시지는 반드시 별도 인자로 전달되어야 한다.
echo "=== F7: Notification hook passes message as argument, not as source ==="
G_NOTIFY="$(jq -r '.hooks.Notification[0].hooks[0].command' "$GUARD_FRAG")"
NSHIM="${SANDBOX_ROOT_F7:-${TMPDIR:-/tmp}}/f7-shim.$$"
mkdir -p "$NSHIM"
{
    echo '#!/bin/bash'
    echo 'printf "%s\n" "$@" > "$NOTIFY_LOG"'
} > "${NSHIM}/osa-stub"
# 훅이 부르는 실제 이름으로 셔임을 건다
cp "${NSHIM}/osa-stub" "${NSHIM}/osascript"
chmod +x "${NSHIM}/osascript"
NOTIFY_LOG="${NSHIM}/args.log"; export NOTIFY_LOG
F7_PAYLOAD='{"message":"hi\" with title \"INJECTED"}'
printf '%s' "$F7_PAYLOAD" | PATH="${NSHIM}:${PATH}" bash -c "$G_NOTIFY" >/dev/null 2>&1

if [ -f "$NOTIFY_LOG" ]; then
    pass "F7 알림 백엔드가 실제로 호출됨 (테스트 헛돎 방지)"
    if grep -q 'display notification' "$NOTIFY_LOG" && \
       ! grep 'display notification' "$NOTIFY_LOG" | grep -q 'INJECTED'; then
        pass "F7 메시지가 스크립트 소스에 삽입되지 않음 (인젝션 차단)"
    else
        fail "F7 스크립트 인젝션 가능: $(grep 'display notification' "$NOTIFY_LOG" | head -1)"
    fi
    if grep -qF 'hi" with title "INJECTED' "$NOTIFY_LOG"; then
        pass "F7 메시지가 별도 인자로 원문 그대로 전달됨"
    else
        fail "F7 메시지가 인자로 전달되지 않음: $(tr '\n' '|' < "$NOTIFY_LOG")"
    fi
else
    fail "F7 알림 백엔드 셔임이 호출되지 않음 — 테스트 헛돎"
fi
rm -rf "$NSHIM"
unset NOTIFY_LOG

# ==================== F8: 문서 계약 — 레거시 MODELS.md / stale sweep ====================
echo "=== F8: README 가 실제 동작을 문서화하는지 ==="
README_MD="${REPO_DIR}/README.md"
DOCS_INSTALL_F8="${REPO_DIR}/docs/Claude code system setup/install.sh"

# 해시 기반 자동 삭제를 실제로 구현했는지 + 그 해시가 실재하는 배포본의 것인지
if grep -q 'LEGACY_MODELS_HASHES=' "$DOCS_INSTALL_F8"; then
    pass "F8 레거시 MODELS.md 해시 목록이 설치기에 존재"
else
    fail "F8 레거시 MODELS.md 정리 로직 없음"
fi
if grep -q 'LEGACY-MODELS-KEPT' "$DOCS_INSTALL_F8"; then
    pass "F8 보존 시 전용 안내 표지가 설치기에 존재"
else
    fail "F8 보존 안내 표지 없음"
fi
# README 가 두 정책을 모두 설명해야 한다 (문서가 동작보다 약속을 덜 하거나 더 하면 안 됨)
if grep -q 'LEGACY-MODELS-KEPT' "$README_MD"; then
    pass "F8 README 가 레거시 MODELS.md 정책을 문서화"
else
    fail "F8 README 에 레거시 MODELS.md 정책 설명 없음"
fi
if grep -q 'stale sweep' "$README_MD" && grep -q '소스 존재 여부' "$README_MD"; then
    pass "F8 README 가 업스트림 제거 자산 스윕 정책을 문서화"
else
    fail "F8 README 에 stale sweep 정책 설명 없음"
fi

# ==================== docs install script Tests ====================
echo "=== F5: docs/Claude code system setup/install.sh no model hard pin ==="
DOCS_INSTALL="${REPO_DIR}/docs/Claude code system setup/install.sh"
if grep '"model"' "$DOCS_INSTALL" | grep -q "claude-"; then
    fail "F5 install.sh has model hard pin"
else
    pass "F5 install.sh no model hard pin"
fi

if grep "MODELS\.md" "$DOCS_INSTALL" | grep -q "install_managed"; then
    fail "F5 install.sh still installs MODELS.md"
else
    pass "F5 install.sh no MODELS.md installation"
fi

# 설치하지 않는 파일을 사용자에게 참조시키면 안 된다. 특히 585줄 근처의
# CLAUDE.md 템플릿 heredoc 은 그 문장을 사용자 리포에 영구히 써 넣는다.
# 설치하지 않는 파일을 "참조하라"고 사용자에게 시키면 안 된다. 반대로 "삭제하라"는
# 안내는 정당하다(레거시 정리). 그래서 단순 경로 매칭이 아니라 참조/SSOT 문맥만 센다.
# 예외: 끊긴 참조를 **경고**하는 줄은 정당하다. 레거시 파일을 지운 뒤 사용자
# CLAUDE.md 에 남은 참조를 알리는 것은 "참조하라"가 아니라 "고쳐라"다.
# 전용 표지로 구분한다 — 표지 없이 문맥만 보면 정반대 의미를 같은 것으로 센다.
DANGLING="$(grep -n 'MODELS\.md' "$DOCS_INSTALL" | grep -E '참조|SSOT' \
            | grep -v 'DANGLING-MODELS-REF' | grep -v '아직 참조합니다' \
            | grep -c . | tr -d ' ')"
if [ "$DANGLING" -eq 0 ]; then
    pass "F5 설치하지 않는 MODELS.md 를 참조/SSOT 로 안내하는 문장 없음"
else
    fail "F5 MODELS.md 를 참조하라고 안내하는 문장이 ${DANGLING}곳: $(grep -n 'MODELS\.md' "$DOCS_INSTALL" | grep -E '참조|SSOT' | grep -v 'DANGLING-MODELS-REF' | grep -v '아직 참조합니다' | head -2 | tr '\n' ' ')"
fi
# 사용자 리포에 영구히 써 넣는 CLAUDE.md 템플릿에는 흔적이 없어야 한다
CLAUDE_TPL="$(sed -n "/<<'CLAUDEMD_EOF'/,/^CLAUDEMD_EOF$/p" "$DOCS_INSTALL")"
if printf '%s' "$CLAUDE_TPL" | grep -q 'MODELS\.md'; then
    fail "F5 생성되는 CLAUDE.md 템플릿이 MODELS.md 를 참조함"
else
    pass "F5 생성되는 CLAUDE.md 템플릿에 MODELS.md 참조 없음"
fi

# ── F6 (계속): secret/credential 디렉토리 성분 차단 ──────────────────────
# basename 만 보면 secrets/config.yml 이 통과한다(실측). 디렉토리 이름이 통째로
# secret/credential 계열이면 그 아래 전부를 보호한다. 단 성분 "완전 일치"라
# mysecrets-project/ 같은 무고한 이름은 그대로 통과해야 한다.
expect_hook "secret 디렉토리 성분 차단 (secrets/config.yml)" \
    "$G_EDIT" '{"tool_input":{"file_path":"/home/u/proj/secrets/config.yml"}}' 2
expect_hook "credential 디렉토리 성분 차단 (credentials/aws.json)" \
    "$G_EDIT" '{"tool_input":{"file_path":"/home/u/proj/credentials/aws.json"}}' 2
expect_hook "숨김 secret 디렉토리 차단 (.secrets/x.txt)" \
    "$G_EDIT" '{"tool_input":{"file_path":"/home/u/proj/.secrets/x.txt"}}' 2
expect_hook "대소문자 무관 차단 (Secrets/x.txt)" \
    "$G_EDIT" '{"tool_input":{"file_path":"/home/u/proj/Secrets/x.txt"}}' 2
expect_hook "단수형 credential 디렉토리 차단" \
    "$G_EDIT" '{"tool_input":{"file_path":"/home/u/proj/credential/token"}}' 2
expect_hook "오탐 금지: mysecrets-project/ 는 secret 디렉토리가 아니다" \
    "$G_EDIT" '{"tool_input":{"file_path":"/home/u/mysecrets-project/app.ts"}}' 0
expect_hook "오탐 금지: secretsmanager/ 는 성분 완전 일치가 아니다" \
    "$G_EDIT" '{"tool_input":{"file_path":"/home/u/secretsmanager/client.ts"}}' 0
expect_hook "basename 기존 동작 보존 (my-secrets.txt)" \
    "$G_EDIT" '{"tool_input":{"file_path":"/home/u/my-secrets.txt"}}' 2

# ============================================================================
echo "=== F9: 구버전 이주 목록 드리프트 + 번들 문서 계약 ==="
# ============================================================================
# (a) lib/legacy-identities.tsv 는 base 438aaf9 조각들에서 기계적으로 도출된 값이다.
#     "결정론적으로 도출했다"를 주장이 아니라 매 실행 검사로 바꾼다.
LEGACY_TSV="${REPO_DIR}/lib/legacy-identities.tsv"
if [ ! -f "$LEGACY_TSV" ]; then
    fail "F9 lib/legacy-identities.tsv 없음 — 구버전 이주 근거 소실"
elif ! command -v git >/dev/null 2>&1 || \
     ! git -C "$REPO_DIR" rev-parse --verify -q 438aaf9 >/dev/null 2>&1; then
    skip "F9 드리프트 검증 (git 또는 base 438aaf9 없음)"
else
    F9_TMP="$(mktemp -d)"
    # 이주 대상은 base 전부가 아니라 **현재 조각이 더 이상 선언하지 않는 것**뿐이다.
    # base 와 현재가 공유하는 identity 까지 목록에 넣으면, 사용자가 독립적으로 만든
    # 같은 identity 를 우리 것으로 주장해 uninstall 이 지운다.
    (
        . "${REPO_DIR}/lib/merge-settings.sh"
        git -C "$REPO_DIR" ls-tree -r --name-only 438aaf9 \
            | grep 'settings-fragments/.*\.json$' | sort > "${F9_TMP}/list"
        while IFS= read -r f; do
            fid="$(basename "$f")"
            git -C "$REPO_DIR" show "438aaf9:${f}" > "${F9_TMP}/base.json"
            msf_extract_records "${F9_TMP}/base.json" > "${F9_TMP}/base.txt"
            : > "${F9_TMP}/cur.txt"
            for c in "${REPO_DIR}/project/settings-fragments/${fid}" \
                     "${REPO_DIR}/global/settings-fragments/${fid}"; do
                [ -f "$c" ] && msf_extract_records "$c" > "${F9_TMP}/cur.txt"
            done
            if [ -s "${F9_TMP}/cur.txt" ]; then
                grep -F -x -v -f "${F9_TMP}/cur.txt" "${F9_TMP}/base.txt" 2>/dev/null \
                    | sed "s|^|${fid}	|" || true
            else
                sed "s|^|${fid}	|" "${F9_TMP}/base.txt"
            fi
        done < "${F9_TMP}/list"
    ) > "${F9_TMP}/regen.tsv" 2>/dev/null
    grep -v '^#' "$LEGACY_TSV" > "${F9_TMP}/shipped.tsv"
    if cmp -s "${F9_TMP}/regen.tsv" "${F9_TMP}/shipped.tsv"; then
        pass "F9 legacy-identities.tsv 가 base 438aaf9 재생성 결과와 일치 ($(grep -c . "${F9_TMP}/shipped.tsv")건)"
    else
        fail "F9 legacy-identities.tsv 드리프트: $(diff "${F9_TMP}/regen.tsv" "${F9_TMP}/shipped.tsv" | head -3 | tr '\n' ' ')"
    fi
    # 현재 조각이 여전히 선언하는 identity 가 목록에 섞이면 안 된다 (과잉 주장 방지)
    F9_OVERCLAIM=0
    for cf in "${REPO_DIR}"/project/settings-fragments/*.json "${REPO_DIR}"/global/settings-fragments/*.json; do
        [ -f "$cf" ] || continue
        cfid="$(basename "$cf")"
        ( . "${REPO_DIR}/lib/merge-settings.sh"; msf_extract_records "$cf" ) > "${F9_TMP}/c.txt" 2>/dev/null
        awk -F '\t' -v id="$cfid" 'NF >= 2 && $1 == id {
            line = $2; for (i = 3; i <= NF; i++) line = line "\t" $i; print line
        }' "$LEGACY_TSV" > "${F9_TMP}/l.txt" 2>/dev/null || : > "${F9_TMP}/l.txt"
        if [ -s "${F9_TMP}/c.txt" ] && [ -s "${F9_TMP}/l.txt" ]; then
            n="$(grep -F -x -f "${F9_TMP}/c.txt" "${F9_TMP}/l.txt" 2>/dev/null | grep -c . || true)"
            F9_OVERCLAIM=$((F9_OVERCLAIM + n))
        fi
    done
    if [ "$F9_OVERCLAIM" -eq 0 ]; then
        pass "F9 이주 목록에 현재도 배포 중인 identity 없음 (과잉 주장 없음)"
    else
        fail "F9 이주 목록이 현재 배포 identity ${F9_OVERCLAIM}건을 포함 — 사용자 항목을 주장해 uninstall 이 지운다"
    fi
    rm -rf "$F9_TMP"
fi

# (b) 번들 문서는 ~/.claude/docs/claude-code-setup/ 로 설치되어 에이전트가 읽는다.
#     설치기가 더 이상 하지 않는 일을 한다고 적혀 있으면 그것이 곧 오정보다.
DOCS_ROOT="${REPO_DIR}/docs"
MODELS_CLAIM="$(grep -rl 'MODELS\.md' "$DOCS_ROOT" --include='*.md' 2>/dev/null | wc -l | tr -d ' ')"
if [ "$MODELS_CLAIM" -eq 0 ]; then
    pass "F9 번들 문서에 MODELS.md 설치 주장 없음"
else
    fail "F9 번들 문서 ${MODELS_CLAIM}개가 아직 MODELS.md 를 설치물로 안내: $(grep -rl 'MODELS\.md' "$DOCS_ROOT" --include='*.md' 2>/dev/null | head -2 | tr '\n' ' ')"
fi

# (c) settings.json 에 model 키를 박으라는 예시/지시 — 설치기의 불변식과 정면 충돌
MODEL_KEY="$(grep -rn '"model": "claude-\|- model: "claude-' "$DOCS_ROOT" --include='*.md' 2>/dev/null | wc -l | tr -d ' ')"
if [ "$MODEL_KEY" -eq 0 ]; then
    pass "F9 번들 문서에 settings.json model 하드코딩 예시 없음"
else
    fail "F9 번들 문서에 model 하드코딩 ${MODEL_KEY}곳: $(grep -rn '"model": "claude-\|- model: "claude-' "$DOCS_ROOT" --include='*.md' 2>/dev/null | head -2 | cut -c1-90 | tr '\n' ' ')"
fi

# ── F6 (계속): 인용된 보호 경로 우회 차단 ────────────────────────────────
# 정규식이 "공백 다음의 인용 없는 경로" 만 봐서 따옴표 하나로 우회된다(실측 exit 0).
# 파괴적 명령 가드에서 따옴표가 곧 우회 수단이면 가드가 아니다.
expect_hook "인용 우회 차단: rm -rf \"/etc\"" \
    "$G_BASH" '{"tool_input":{"command":"rm -rf \"/etc\""}}' 2
expect_hook "인용 우회 차단: rm -rf '\''/'\''" \
    "$G_BASH" '{"tool_input":{"command":"rm -rf '\''/'\''"}}' 2
expect_hook "인용 우회 차단: rm -rf \"\$HOME\"" \
    "$G_BASH" '{"tool_input":{"command":"rm -rf \"$HOME\""}}' 2
expect_hook "인용 우회 차단: rm -rf \"/\"" \
    "$G_BASH" '{"tool_input":{"command":"rm -rf \"/\""}}' 2
expect_hook "오탐 금지(인용): rm -rf \"/tmp/x\" 는 통과" \
    "$G_BASH" '{"tool_input":{"command":"rm -rf \"/tmp/x\""}}' 0
expect_hook "오탐 금지(인용): rm -rf \"./build\" 는 통과" \
    "$G_BASH" '{"tool_input":{"command":"rm -rf \"./build\""}}' 0

# ── F6 (계속): 셸 구분자가 경로 경계로 인정돼야 한다 ─────────────────────
# 복합 명령에서 보호 경로 뒤에 바로 `;` 가 오면 lookahead 가 경계로 인정하지 않아
# 통과했다(실측 exit 0). 구분자도 토큰 경계다.
expect_hook "구분자 경계: rm -rf /etc; echo ok" \
    "$G_BASH" '{"tool_input":{"command":"rm -rf /etc; echo ok"}}' 2
expect_hook "구분자 경계: rm -rf /;true" \
    "$G_BASH" '{"tool_input":{"command":"rm -rf /;true"}}' 2
expect_hook "구분자 경계: rm -rf /etc&&x" \
    "$G_BASH" '{"tool_input":{"command":"rm -rf /etc&&x"}}' 2
expect_hook "구분자 경계: rm -rf /etc|tee x" \
    "$G_BASH" '{"tool_input":{"command":"rm -rf /etc|tee x"}}' 2
expect_hook "오탐 금지(구분자): rm -rf ./build; echo ok" \
    "$G_BASH" '{"tool_input":{"command":"rm -rf ./build; echo ok"}}' 0
expect_hook "오탐 금지(구분자): rm -rf /tmp/x; echo ok" \
    "$G_BASH" '{"tool_input":{"command":"rm -rf /tmp/x; echo ok"}}' 0

# ── F6 (계속): 경로 표기 정규화 (중복 슬래시 · .. 우회) ─────────────────
# `/tmp/../etc/passwd` 와 `//etc/passwd` 는 결국 보호 경로로 해석되는데,
# 문자열을 정규화하지 않으면 경계 검사가 다른 경로로 보고 통과시킨다.
# posixpath.normpath 는 선행 `//` 를 보존하므로 슬래시 축약이 별도로 필요하다.
expect_hook "정규화: rm -rf /tmp/../etc/passwd" \
    "$G_BASH" '{"tool_input":{"command":"rm -rf /tmp/../etc/passwd"}}' 2
expect_hook "정규화: rm -rf //etc/passwd" \
    "$G_BASH" '{"tool_input":{"command":"rm -rf //etc/passwd"}}' 2
expect_hook "정규화: rm -rf /var/../" \
    "$G_BASH" '{"tool_input":{"command":"rm -rf /var/../"}}' 2
expect_hook "오탐 금지(정규화): rm -rf /tmp/../tmp/build" \
    "$G_BASH" '{"tool_input":{"command":"rm -rf /tmp/../tmp/build"}}' 0
expect_hook "정규화(Edit): //etc/passwd 차단" \
    "$G_EDIT" '{"tool_input":{"file_path":"//etc/passwd"}}' 2
expect_hook "정규화(Edit): /tmp/../etc/hosts 차단" \
    "$G_EDIT" '{"tool_input":{"file_path":"/tmp/../etc/hosts"}}' 2
expect_hook "정규화(Edit): //home/u/secrets/a.yml 차단" \
    "$G_EDIT" '{"tool_input":{"file_path":"//home/u/secrets/a.yml"}}' 2
expect_hook "오탐 금지(Edit 정규화): /tmp/../tmp/x.ts 통과" \
    "$G_EDIT" '{"tool_input":{"file_path":"/tmp/../tmp/x.ts"}}' 0

# ── F6 (계속): 토큰 내부 인용 (셸이 이어붙이는 형태) ────────────────────
# `rm -rf /e"tc"` 를 셸은 `/etc` 로 실행한다. 따옴표를 공백으로만 바꾸면
# `/e tc` 가 되어 매칭에서 빠진다 — 인용을 제거한 형태도 함께 봐야 한다.
expect_hook "토큰 내부 인용: rm -rf /e\"tc\"" \
    "$G_BASH" '{"tool_input":{"command":"rm -rf /e\"tc\""}}' 2
expect_hook "토큰 내부 인용: rm -rf '\''/et'\''c" \
    "$G_BASH" '{"tool_input":{"command":"rm -rf '\''/et'\''c"}}' 2
expect_hook "토큰 내부 인용(Edit): se\"crets\"/config.yml" \
    "$G_EDIT" '{"tool_input":{"file_path":"/home/u/se\"crets\"/config.yml"}}' 2
expect_hook "오탐 금지: rm -rf \"my\"build" \
    "$G_BASH" '{"tool_input":{"command":"rm -rf \"my\"build"}}' 0

# ── F6 (계속): 보호 경로에 붙은 셸 확장 ─────────────────────────────────
# `rm -rf /etc${UNSET-}` 를 셸은 `/etc` 로 실행하는데, 정규식은 `$` 를 보고
# 경계가 아니라고 판단해 통과시킨다. 확장을 제거한 해석도 함께 본다.
expect_hook "셸 확장 인접: rm -rf /etc\${UNSET-}" \
    "$G_BASH" '{"tool_input":{"command":"rm -rf /etc${UNSET-}"}}' 2
expect_hook "셸 확장 인접: rm -rf /\$EMPTY" \
    "$G_BASH" '{"tool_input":{"command":"rm -rf /$EMPTY"}}' 2
expect_hook "오탐 금지(확장): rm -rf /tmp/\$BUILD" \
    "$G_BASH" '{"tool_input":{"command":"rm -rf /tmp/$BUILD"}}' 0

finish
