#!/bin/bash
# ============================================================================
# tests/helpers.sh — 테스트 공용 헬퍼 (source 해서 사용)
# ----------------------------------------------------------------------------
# 계약:
#   - 실제 $HOME 을 절대 건드리지 않는다: 모든 테스트는 mktemp 샌드박스 +
#     HOME 오버라이드로만 실행한다.
#   - trap 으로 종료 시 샌드박스 전부 삭제 (잔여물 0).
#   - bash 3.2 호환 (연관배열·소문자변환 금지), 모든 경로 인용.
#
# 제공:
#   pass/fail/skip 카운터, 샌드박스, 스냅샷, 해시, fixture 리포 복사,
#   설치 실행 래퍼, jq 숨김 셔임(node 폴백 강제)
# ============================================================================

FAIL_COUNT=0
PASS_COUNT=0
SKIP_COUNT=0
pass() { printf 'PASS: %s\n' "$1"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { printf 'FAIL: %s\n' "$1"; FAIL_COUNT=$((FAIL_COUNT + 1)); }
skip() { printf 'SKIP: %s\n' "$1"; SKIP_COUNT=$((SKIP_COUNT + 1)); }

# ── 샌드박스 (호출 파일당 1개, trap 정리) ────────────────────────────────
init_sandbox() {
    SANDBOX_ROOT="$(mktemp -d)"
    trap 'rm -rf "$SANDBOX_ROOT"' EXIT INT TERM
}

# ── 해시/스냅샷 ─────────────────────────────────────────────────────────
# 이식 가능한 내용 해시. shasum → sha256sum → cksum 순으로 시도한다.
# **절대 빈 값을 돌려주지 않는다** — 빈 해시는 스냅샷을 조용히 비게 만들어
# 롤백·멱등 비교가 무조건 통과하는 거짓 안심을 만든다(실측으로 확인).
file_hash() {
    local h=""
    if command -v shasum >/dev/null 2>&1; then
        h="$(shasum -a 256 "$1" 2>/dev/null | awk '{print $1}')"
    fi
    if [ -z "$h" ] && command -v sha256sum >/dev/null 2>&1; then
        h="$(sha256sum "$1" 2>/dev/null | awk '{print $1}')"
    fi
    if [ -z "$h" ] && command -v cksum >/dev/null 2>&1; then
        h="$(cksum "$1" 2>/dev/null | awk '{print $1 "-" $2}')"
    fi
    if [ -z "$h" ]; then
        # 해시 수단이 하나도 없으면 침묵하지 않는다. 이 값이 스냅샷에 들어가면
        # 비교는 여전히 동작하고(모든 파일이 같은 토큰), 로그로 원인이 드러난다.
        printf 'HASH-UNAVAILABLE'
        return 1
    fi
    printf '%s' "$h"
}

# 파일 모드(8진수). GNU(stat -c) → BSD/macOS(stat -f) 순.
path_mode() {
    local m
    m="$(stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1" 2>/dev/null)"
    case "$m" in
        ''|*[!0-7]*) printf 'MODE?' ;;
        *)           printf '%s' "$m" ;;
    esac
}

# 트리 스냅샷 — 롤백이 복원한다고 **약속한 것**을 전부 담는다.
#   내용 해시만 보면 실행 비트 소실·링크가 일반 파일로 변질·빈 디렉토리 잔존을
#   비교가 놓쳐, chmod/경로 상태 롤백이 사실상 미검증으로 남는다.
# 형식(정렬됨): "<종류> <모드|대상> <해시> <상대경로>"
snapshot_tree() {
    ( cd "$1" 2>/dev/null || return 0
      find . -mindepth 1 -print 2>/dev/null | LC_ALL=C sort | while IFS= read -r p; do
          [ -n "$p" ] || continue
          if [ -L "$p" ]; then
              printf 'link  ->%s  -  %s\n' "$(readlink "$p" 2>/dev/null)" "$p"
          elif [ -d "$p" ]; then
              printf 'dir   %s  -  %s\n' "$(path_mode "$p")" "$p"
          elif [ -f "$p" ]; then
              printf 'file  %s  %s  %s\n' "$(path_mode "$p")" "$(file_hash "$p")" "$p"
          else
              printf 'other -  -  %s\n' "$p"
          fi
      done )
}

count_baks_in() {
    find "$@" \( -name '*.bak' -o -name '*.bak.*' \) -print 2>/dev/null | wc -l | tr -d ' '
}

# 특정 파일 하나의 백업 개수 (bounded retention 검증용)
count_baks_of() {
    # $1 = 원본 파일 절대경로
    local dir base
    dir="$(dirname "$1")"
    base="$(basename "$1")"
    find "$dir" -maxdepth 1 \( -name "${base}.bak" -o -name "${base}.bak.*" \) -print 2>/dev/null \
        | wc -l | tr -d ' '
}

# settings.json 안의 모든 command 문자열을 재귀 수집
settings_commands() {
    jq -r '[.. | objects | .command? // empty] | .[]' "$1" 2>/dev/null
}

# ── fixture 리포 복사 (소스 조작 테스트용 — 원본 리포는 불변) ────────────
# $1 = 목적지. .git 제외 전체 복사.
make_fixture_repo() {
    local dst="$1"
    mkdir -p "$dst"
    ( cd "$REPO_DIR" && find . -name .git -prune -o -type d -print 2>/dev/null ) | \
        while IFS= read -r d; do mkdir -p "${dst}/${d}"; done
    ( cd "$REPO_DIR" && find . -name .git -prune -o -type f -print 2>/dev/null ) | \
        while IFS= read -r f; do cp -p "${REPO_DIR}/${f}" "${dst}/${f}"; done
}

# ── npm/codex 네트워크 차단 셔임 ────────────────────────────────────────
install_net_shims() {
    # $1 = 셔임 디렉토리
    mkdir -p "$1"
    local cmd
    for cmd in npm codex; do
        printf '#!/bin/bash\nexit 0\n' > "$1/${cmd}"
        chmod +x "$1/${cmd}"
    done
    export PATH="$1:${PATH}"
}

# ── node 폴백 강제: jq 만 실패하는 셔임 디렉토리를 PATH 앞에 추가한 서브셸 실행 ──
# 사용: run_without_jq <command...>  (서브셸이라 호출자 PATH 불변)
run_without_jq() {
    local shim="${SANDBOX_ROOT}/nojq-shim"
    if [ ! -x "${shim}/jq" ]; then
        mkdir -p "$shim"
        printf '#!/bin/bash\nexit 127\n' > "${shim}/jq"
        chmod +x "${shim}/jq"
    fi
    ( export PATH="${shim}:${PATH}"; "$@" )
}

# ── 결과 요약 (각 테스트 파일 끝에서 호출) ──────────────────────────────
finish() {
    echo ""
    echo "=== RESULT: PASS ${PASS_COUNT} / FAIL ${FAIL_COUNT} / SKIP ${SKIP_COUNT} ==="
    if [ "$FAIL_COUNT" -gt 0 ]; then
        exit 1
    fi
    exit 0
}
