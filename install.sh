#!/bin/bash
set -euo pipefail

# ============================================================================
# Claude Code Universal Environment Setup — 통합 설치기 (오케스트레이터)
# ----------------------------------------------------------------------------
# ./install.sh 한 번으로 docs 폴더의 모든 기능까지 설치한다.
#
# Usage:
#   ./install.sh [OPTIONS]
#
# Options:
#   --project PATH       프로젝트 설치 대상 디렉토리
#   --global-only        글로벌(~/.claude/)만 설치
#   --dry-run            변경 없이 미리보기 ('[DRY RUN] Would ...')
#   --full               --with-advisor + --with-examples + --with-pm2
#                        + verify-hooks 조각 파일 설치
#                        (단 settings 병합은 --with-verify-hooks 명시 시에만)
#   --with-advisor       codex-advisor-worker-bundle 설치 위임
#   --with-examples      examples/ 자산을 프로젝트에 설치
#   --with-pm2           PM2 템플릿을 <project>/docs/templates/pm2/ 로 복사
#                        + pm2-hooks fragment 를 settings.json 에 병합
#                        (명시했을 때만 — --full 만으로는 병합하지 않는다)
#   --with-verify-hooks  verification-hooks fragment 를 settings.json 에 병합
#   --uninstall          installer 소유 자산만 제거 (아래 '제거 정책' 참조)
#   -h, --help           도움말
#
# 대화형 프롬프트 없음. 유일한 예외: 플래그 없이 실행 + stdin 이 TTY 일 때만
# 프로젝트 경로를 질문한다 (비TTY 는 프로젝트 단계 스킵 안내).
#
# 파일 정책 (소유권 manifest 기반 — lib/manifest.sh):
#   - 관리 파일/관리 디렉토리 모두 "파일 단위"로 판정한다. 디렉토리를 rm -rf 로
#     통째 교체하지 않는다.
#       * manifest 기록 해시 == 현재 해시 → installer 소유·미변경 → 갱신/삭제 가능
#       * manifest 에 없지만 내용이 소스와 동일 → 소유권 인수(adopt) 후 UNCHANGED
#       * manifest 에 없고 내용도 다름 (사용자 추가) → 보존
#       * manifest 에 있으나 해시가 다름 (사용자 수정) → 보존
#   - stale 정리: 소스에서 사라진 파일은 "installer 소유·미변경" 일 때만 제거한다.
#   - 백업: 관리 "파일" 갱신 시에만 .bak(.bak.1...) + bounded retention(기본 3).
#     관리 디렉토리는 디렉토리 단위 백업을 만들지 않는다 — 덮어쓰는 대상이
#     "installer 가 쓴 뒤 아무도 안 건드린 파일" 뿐이라 백업할 사용자 내용이 없다.
#   - 사용자 소유 파일(CLAUDE.md, skill-rules.json, .mcp.json.example): skip-if-exists
#   - 요약에 INSTALLED / UNCHANGED / BACKED_UP / SKIPPED 카운트 출력
#
# 제거 정책 (--uninstall):
#   - 파일은 manifest 기록 해시와 현재 해시가 같을 때만 제거(사용자 수정·추가 보존)
#   - settings.json 은 .settings-manifest 가 기록한 hooks/permissions identity 만 제거
#   - 빈 디렉토리만 정리, *.bak 은 남긴다, 재실행 멱등
#
# 실패 시 롤백:
#   - 이번 실행이 건드린 파일/설정/manifest 를 저널에 기록하고, 실패·INT·TERM 시
#     EXIT 트랩에서 역순 복원한다(부분 설치를 남기지 않음).
#   - 위임 설치기(system-setup / advisor) 산출물은 저널 밖 = 롤백 대상 아님.
#
# 제약: bash 3.2 호환(연관배열·소문자변환 금지), 모든 경로 인용(공백 경로 지원)
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_HOME="${HOME}/.claude"
# 관리 루트가 심볼릭 링크인 구성(dotfiles)이 흔하다. 링크를 거부하면 그런 설치가
# 통째로 막히고, 링크인 채로 두면 조상 검사가 루트만 예외로 남겨 일관성이 깨진다.
# 그래서 **정규화**한다 — 사용자가 가리킨 실제 디렉토리를 루트로 삼으면
# "루트가 링크" 라는 경우가 사라지고, 그 아래 링크는 그대로 거부된다.
if [ -L "$CLAUDE_HOME" ] && [ -d "$CLAUDE_HOME" ]; then
    CLAUDE_HOME="$(cd "$CLAUDE_HOME" && pwd -P)"
fi
SYSTEM_SETUP_INSTALLER="${SCRIPT_DIR}/docs/Claude code system setup/install.sh"
ADVISOR_INSTALLER="${SCRIPT_DIR}/docs/codex-advisor-worker-bundle/install.sh"
SAFETY_DOC_SRC="${SCRIPT_DIR}/docs/Claude code system setup/Parallel Agents Safety Protocol v3.1.0.md"
FRAGMENTS_DIR="${SCRIPT_DIR}/project/settings-fragments"
GLOBAL_FRAGMENTS_DIR="${SCRIPT_DIR}/global/settings-fragments"
HOOKS_SRC_DIR="${SCRIPT_DIR}/project/hooks"
DOCS_SRC_DIR="${SCRIPT_DIR}/docs"
DOCS_DST_DIR="${CLAUDE_HOME}/docs/claude-code-setup"
LEGACY_IDENTITIES_FILE="${SCRIPT_DIR}/lib/legacy-identities.tsv"

# 공용 병합 엔진 및 manifest
# shellcheck source=lib/merge-settings.sh
. "${SCRIPT_DIR}/lib/merge-settings.sh"
# shellcheck source=lib/manifest.sh
. "${SCRIPT_DIR}/lib/manifest.sh"

DRY_RUN=false
GLOBAL_ONLY=false
PROJECT_DIR=""
FULL=false
WITH_ADVISOR=false
WITH_EXAMPLES=false
WITH_PM2=false
WITH_VERIFY_HOOKS=false
INSTALL_VERIFY_FRAGMENT=false
UNINSTALL=false
# pm2-hooks 조각의 settings.json 병합은 --with-pm2 를 "명시"했을 때만.
# --full 은 settings.json 배선을 늘리지 않는다(verify-hooks 와 동일한 기존 규칙).
PM2_HOOKS_MERGE=false
ANY_FLAG=false
GUARDRAILS_SKIPPED=false

INSTALLED_COUNT=0
UNCHANGED_COUNT=0
BACKED_UP_COUNT=0
SKIPPED_COUNT=0
REMOVED_COUNT=0
PRESERVED_COUNT=0

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info()  { echo -e "${BLUE}[INFO]${NC} $1"; }
log_ok()    { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --project PATH       Install project settings to specified directory"
    echo "  --global-only        Install global settings (~/.claude/) only"
    echo "  --dry-run            Preview changes without modifying files"
    echo "  --full               --with-advisor + --with-examples + --with-pm2"
    echo "                       + verify-hooks fragment file (merge only with --with-verify-hooks)"
    echo "  --with-advisor       Delegate to codex-advisor-worker-bundle installer"
    echo "  --with-examples      Install examples/ assets into the project"
    echo "  --with-pm2           Copy PM2 templates + merge pm2-hooks fragment (explicit flag only)"
    echo "  --with-verify-hooks  Merge verification-hooks fragment into settings.json"
    echo "  --uninstall          Remove installer-owned files and settings hooks/permissions"
    echo "                       (user-added / user-modified content is preserved)"
    echo "  -h, --help           Show this help"
}

# ──────────────────────────────────────────────────────
# Argument parsing (no interactive prompts; one TTY exception below)
# ──────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)           DRY_RUN=true; ANY_FLAG=true; shift ;;
        --global-only)       GLOBAL_ONLY=true; ANY_FLAG=true; shift ;;
        --project)
            PROJECT_DIR="${2:-}"
            if [ -z "$PROJECT_DIR" ]; then log_error "--project 에 경로가 필요합니다"; exit 1; fi
            ANY_FLAG=true; shift 2 ;;
        --full)              FULL=true; ANY_FLAG=true; shift ;;
        --with-advisor)      WITH_ADVISOR=true; ANY_FLAG=true; shift ;;
        --with-examples)     WITH_EXAMPLES=true; ANY_FLAG=true; shift ;;
        --with-pm2)          WITH_PM2=true; PM2_HOOKS_MERGE=true; ANY_FLAG=true; shift ;;
        --with-verify-hooks) WITH_VERIFY_HOOKS=true; ANY_FLAG=true; shift ;;
        --uninstall)         UNINSTALL=true; ANY_FLAG=true; shift ;;
        -h|--help)           usage; exit 0 ;;
        *)                   log_error "Unknown option: $1"; usage; exit 1 ;;
    esac
done

if $FULL; then
    WITH_ADVISOR=true
    WITH_EXAMPLES=true
    WITH_PM2=true
    # --full 은 verify-hooks "조각 파일"만 설치한다.
    # settings.json 병합은 --with-verify-hooks 를 명시했을 때만.
fi
if $FULL || $WITH_VERIFY_HOOKS; then
    INSTALL_VERIFY_FRAGMENT=true
fi

# ──────────────────────────────────────────────────────
# Prerequisites: jq 또는 node 필수 (병합 엔진), advisor 는 python3 또는 jq
# ──────────────────────────────────────────────────────
check_prereqs() {
    if ! command -v jq >/dev/null 2>&1 && ! command -v node >/dev/null 2>&1; then
        log_error "jq 또는 node 가 필요합니다 (settings.json 병합 엔진이 의존)."
        log_error "예: brew install jq  — 설치 후 재실행하세요."
        exit 1
    fi
    if $WITH_ADVISOR; then
        if ! command -v python3 >/dev/null 2>&1 && ! command -v jq >/dev/null 2>&1; then
            log_error "--with-advisor 에는 python3 또는 jq 가 필요합니다."
            exit 1
        fi
    fi
}

# ──────────────────────────────────────────────────────
# File policy helpers (system-setup 의 install_managed 패턴 이식)
# ──────────────────────────────────────────────────────
# 빈 슬롯 판정에 `-L` 을 함께 본다. `-e` 는 **깨진 링크에 거짓**이라, 링크만
# 있는 경로를 "비었다" 고 보고 골라 `cp -p` 가 링크를 따라 관리 루트 밖에
# 파일을 만들거나 덮어쓴다(실측 확인).
backup_path() {
    local f="$1"
    if [ ! -e "$f.bak" ] && [ ! -L "$f.bak" ]; then
        printf '%s' "$f.bak"
        return
    fi
    local i=1
    while [ -e "$f.bak.$i" ] || [ -L "$f.bak.$i" ]; do
        i=$((i + 1))
    done
    printf '%s' "$f.bak.$i"
}

# 관리 파일: manifest 기반 소유권 판정 + 백업 + 설치
# 소유권 판정 (dst 가 이미 있을 때):
#   (a) manifest 에 없고 내용이 소스와 동일  → 소유권 인수(adopt) 후 UNCHANGED
#       — 이주(migration)가 수렴하게 만드는 규칙이다. 내용이 같으니 잃을
#         사용자 데이터가 없고, 다음 릴리스부터 정상 갱신 대상이 된다.
#   (b) manifest 에 없고 내용이 다름        → 소유권 불명 → 보존(SKIPPED)
#   (c) 기록 해시 == 현재 dst 해시          → installer 소유·미변경 → 갱신
#   (d) 기록 해시 != 현재 dst 해시          → 사용자 수정 → 보존(SKIPPED)
install_managed_file() {
    local src="$1" dst="$2" label="$3"
    if [ ! -f "$src" ]; then
        log_warn "소스 없음, 스킵: ${src}"
        SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
        return 0
    fi

    # 목적지가 심볼릭 링크면 따라가지 않는다. `-f`/`-d` 는 링크를 따라가므로
    # `cp` 가 링크를 통해 **관리 루트 밖**에 쓴다(실측: 바깥 디렉토리에 파일 생성).
    # 링크는 우리가 만든 것이 아니므로 소유로 주장하지도, 덮어쓰지도 않는다.
    if [ -L "$dst" ] || ! managed_path_safe "$dst"; then
        log_warn "SKIPPED (심볼릭 링크 경로 — 따라가지 않음): ${label}"
        SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
        return 0
    fi

    # 같은 경로에 디렉토리(또는 특수 파일)가 있으면 `[ -f ]` 가 거짓이 되어
    # `cp` 가 그 **안으로** 복사하고 manifest 는 디렉토리 경로를 설치 파일인 양
    # 기록한다. 그 뒤로는 업그레이드도 uninstall 도 그 자산을 관리하지 못한다.
    # 남의 디렉토리를 지울 수는 없으니 보존하고 보고한다.
    if [ -e "$dst" ] && [ ! -f "$dst" ]; then
        log_warn "SKIPPED (파일 자리에 디렉토리/특수 파일이 있음): ${label}"
        SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
        return 0
    fi

    mf_resolve "$dst"
    local manifest="$MF_FILE" relpath="$MF_REL"

    local src_hash recorded="" cur
    src_hash="$(manifest_hash_file "$src")"
    if [ -n "$manifest" ]; then
        recorded="$(manifest_get "$manifest" "$relpath")"
    fi

    if [ -f "$dst" ]; then
        cur="$(manifest_hash_file "$dst")"
        if [ -n "$manifest" ]; then
            if [ -z "$recorded" ]; then
                if [ "$cur" != "$src_hash" ]; then
                    log_warn "USER-OWNED (not in manifest): ${label}"
                    SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
                    return 0
                fi
            elif [ "$cur" != "$recorded" ]; then
                log_warn "USER-MODIFIED: ${label}"
                SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
                return 0
            fi
        fi
        if [ "$cur" = "$src_hash" ]; then
            # 내용 동일 — 쓰지 않는다. manifest 는 값이 다를 때만 갱신한다
            # (매 실행 재작성은 manifest 바이트를 흔들어 멱등 스냅샷을 깬다).
            if [ -n "$manifest" ] && [ "$recorded" != "$src_hash" ]; then
                if ! $DRY_RUN; then
                    rb_track "$manifest"
                    manifest_set "$manifest" "$relpath" "$src_hash"
                fi
            fi
            log_ok "UNCHANGED: ${label}"
            UNCHANGED_COUNT=$((UNCHANGED_COUNT + 1))
            return 0
        fi
        # 여기까지 왔으면 installer 소유이고 소스가 바뀐 경우뿐이다 → 백업 후 갱신
        local bak
        bak="$(backup_path "$dst")"
        if [ -L "$bak" ]; then
            log_warn "SKIPPED (백업 경로가 심볼릭 링크 — 따라가지 않음): ${label}"
            SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
            return 0
        fi
        if $DRY_RUN; then
            log_info "[DRY RUN] Would backup: ${dst} -> ${bak}"
        else
            rb_track "$bak"
            rb_track_backups "$dst"
            cp -p "$dst" "$bak"
            if [ -n "$manifest" ]; then
                rb_track "$(manifest_backup_index "$manifest")"
                manifest_backup_record "$manifest" "$bak"
                MANIFEST_BACKUP_INDEX="$(manifest_backup_index "$manifest")"
            else
                MANIFEST_BACKUP_INDEX=""
            fi
            manifest_prune_backups "$dst"
            log_warn "BACKED_UP: ${dst} -> ${bak}"
        fi
        BACKED_UP_COUNT=$((BACKED_UP_COUNT + 1))
    fi

    if $DRY_RUN; then
        log_info "[DRY RUN] Would install: ${label}"
    else
        mkdir -p "$(dirname "$dst")"
        rb_track "$dst"
        cp "$src" "$dst"
        if [ -n "$manifest" ]; then
            rb_track "$manifest"
            manifest_set "$manifest" "$relpath" "$src_hash"
        fi
        log_ok "INSTALLED: ${label}"
    fi
    INSTALLED_COUNT=$((INSTALLED_COUNT + 1))
}

# ──────────────────────────────────────────────────────
# manifest 대상 해석: dst 절대경로 → (manifest 루트, manifest 파일, 상대경로)
#   글로벌: ~/.claude/...        → 루트 ~/.claude,  manifest ~/.claude/.manifest
#   프로젝트: <PROJECT_DIR>/...  → 루트 PROJECT_DIR, manifest <PROJECT_DIR>/.manifest
#   그 외( PROJECT_DIR 미지정 등 ) → MF_ROOT 빈 문자열 = 소유권 추적 없음
# 반환은 전역 변수(MF_ROOT/MF_FILE/MF_REL) — bash 3.2 라 다중 반환 수단이 없다.
# ──────────────────────────────────────────────────────
mf_resolve() {
    local dst="$1"
    MF_ROOT=""; MF_FILE=""; MF_REL=""
    # 프로젝트를 먼저 본다 — 더 구체적인 루트가 이긴다.
    # --project 가 ~/.claude 안을 가리키면 글로벌 우선 판정이 프로젝트 자산을
    # 글로벌 manifest 에 적어, 프로젝트 uninstall 이 그것을 찾지 못한다.
    if [ -n "$PROJECT_DIR" ]; then
        case "$dst" in
            "$PROJECT_DIR"/*)
                MF_ROOT="$PROJECT_DIR"
                MF_REL="${dst#"$PROJECT_DIR"/}"
                ;;
        esac
    fi
    if [ -z "$MF_ROOT" ]; then
        case "$dst" in
            "$CLAUDE_HOME"/*)
                MF_ROOT="$CLAUDE_HOME"
                MF_REL="${dst#"$CLAUDE_HOME"/}"
                ;;
        esac
    fi
    [ -n "$MF_ROOT" ] || return 0
    # 불변식: manifest 는 "루트 기준 상대경로"만 담는다. 절대경로가 들어가면
    # uninstall 이 대상을 찾지 못하고(경로가 루트 밑에 없다) stale 정리가 자기
    # 기록을 지운다. 조용히 진행하느니 여기서 멈춘다 — 롤백이 원상복구한다.
    case "$MF_REL" in
        ''|/*)
            log_error "내부 오류: manifest 상대경로 계산 실패 (root=${MF_ROOT}, dst=${dst})"
            log_error "경로에 glob 메타문자([ ] * ?)가 있는지 확인하세요."
            exit 1
            ;;
    esac
    MF_FILE="${MF_ROOT}/.manifest"
}

# 관리 루트와 대상 사이의 **모든 성분**이 심볼릭 링크가 아닌지 확인한다.
#
# 최종 목적지만 검사하면 조상(.claude/skills 같은)이 링크일 때 mkdir -p / cp 가
# 그 링크를 통해 관리 루트 밖에 쓴다(실측: 바깥 디렉토리에 19개 파일 기록).
# 남의 링크를 지울 수는 없으니 따라가지 않고 거부한다.
path_ancestors_safe() {
    local root="$1" target="$2" rel cur comp
    rel="${target#"$root"/}"
    [ "$rel" != "$target" ] || return 0   # 루트 밑이 아니면 이 검사의 대상이 아니다
    cur="$root"
    while [ -n "$rel" ]; do
        case "$rel" in
            */*) comp="${rel%%/*}"; rel="${rel#*/}" ;;
            *)   comp="$rel";       rel="" ;;
        esac
        [ -n "$comp" ] || continue
        cur="${cur}/${comp}"
        [ -L "$cur" ] && return 1
    done
    return 0
}

# 관리 루트를 알아내 조상 링크를 검사한다 (루트 밖이면 검사 생략)
managed_path_safe() {
    local target="$1"
    case "$target" in
        "$CLAUDE_HOME"/*) path_ancestors_safe "$CLAUDE_HOME" "$target"; return $? ;;
    esac
    if [ -n "$PROJECT_DIR" ]; then
        case "$target" in
            "$PROJECT_DIR"/*) path_ancestors_safe "$PROJECT_DIR" "$target"; return $? ;;
        esac
    fi
    return 0
}

# 파일 하나를 지운 뒤, 그 때문에 비게 된 상위 디렉토리만 root 직전까지 정리한다.
# (`find -type d -empty -delete` 는 사용자가 만든 빈 디렉토리까지 지운다 — 금지)
prune_empty_parents() {
    local root="$1" path="$2"
    local d
    d="$(dirname "$path")"
    while [ "$d" != "$root" ] && [ "$d" != "/" ] && [ "$d" != "." ]; do
        rmdir "$d" 2>/dev/null || break
        d="$(dirname "$d")"
    done
}

# ──────────────────────────────────────────────────────
# 관리 디렉토리: manifest 기반 재귀 동기화 (bash 3.2 호환)
#
# rm -rf 통째 교체를 쓰지 않는다. 파일 단위로만 판정한다:
#   - installer 소유(manifest 기록 해시 == 현재 dst 해시) → 갱신/삭제 가능
#   - manifest 에 없지만 내용이 소스와 동일           → 소유권 인수(adopt)
#   - manifest 에 없고 내용도 다름 (= 사용자 추가)     → 보존
#   - manifest 에 있으나 해시가 다름 (= 사용자 수정)   → 보존
# stale(소스에서 사라진) 파일은 "installer 소유이고 미변경"일 때만 제거한다.
#
# 백업 정책: 디렉토리 단위 백업(cp -Rp dst dst.bak)을 하지 않는다. 그 방식은
#   사용자가 파일 하나만 추가해도 diff 가 깨져 매 실행마다 .bak 트리가 증식했다
#   (실측: 재실행 1회당 .bak 29개). 파일 단위 판정에서는 사용자 데이터가 위험한
#   경로 자체가 없다 — 덮어쓰는 대상은 "installer 가 쓴 뒤 아무도 안 건드린
#   파일"뿐이라 백업할 사용자 내용이 존재하지 않는다.
# ──────────────────────────────────────────────────────
install_managed_dir() {
    local src="$1" dst="$2" label="$3"
    src="${src%/}"
    dst="${dst%/}"
    if [ ! -d "$src" ]; then
        log_warn "소스 없음, 스킵: ${src}"
        SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
        return 0
    fi

    # 관리 디렉토리 자리의 심볼릭 링크도 따라가지 않는다(위와 같은 이유).
    if [ -L "$dst" ] || ! managed_path_safe "$dst"; then
        log_warn "SKIPPED (심볼릭 링크 경로 — 따라가지 않음): ${label}"
        SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
        return 0
    fi

    mf_resolve "$dst"
    local manifest="$MF_FILE" prefix="$MF_REL"

    local changed=0 preserved=0

    # ── Phase 1: 소스 파일 목록 (tmpfile 경유 — 파이프는 서브셸이라 카운터가 유실된다)
    local tmp_files
    tmp_files="$(mktemp)" || return 1
    find "$src" -type f -print > "$tmp_files"

    # ── Phase 2: 파일 단위 동기화
    local src_file rel dst_file mf_rel recorded cur src_hash
    while IFS= read -r src_file; do
        [ -n "$src_file" ] || continue
        rel="${src_file#"$src"/}"
        # 접두 제거는 실패할 수 없다(find "$src" 의 결과는 항상 "$src/" 로 시작).
        # 실패했다면 내부 버그다 — 조용히 건너뛰면 "0개 설치 + exit 0" 이라는
        # 최악의 침묵이 된다(대괄호 경로에서 실제로 그랬다). 즉시 실패시킨다.
        if [ "$rel" = "$src_file" ]; then
            log_error "내부 오류: 소스 접두 제거 실패 (src=${src}, file=${src_file})"
            exit 1
        fi
        dst_file="${dst}/${rel}"
        # 파일 자리에 링크·디렉토리가 있으면 그리로 쓰지 않는다 (위와 같은 이유)
        if [ -L "$dst_file" ] || ! managed_path_safe "$dst_file" \
           || { [ -e "$dst_file" ] && [ ! -f "$dst_file" ]; }; then
            preserved=$((preserved + 1))
            continue
        fi
        mf_rel=""
        [ -n "$manifest" ] && mf_rel="${prefix}/${rel}"

        src_hash="$(manifest_hash_file "$src_file")"
        recorded=""
        [ -n "$manifest" ] && recorded="$(manifest_get "$manifest" "$mf_rel")"

        if [ -f "$dst_file" ]; then
            cur="$(manifest_hash_file "$dst_file")"
            if [ -z "$recorded" ]; then
                if [ "$cur" != "$src_hash" ]; then
                    # 소유권 불명 + 내용 상이 → 사용자 파일로 보고 보존
                    preserved=$((preserved + 1))
                    continue
                fi
                # 내용이 소스와 동일 → 안전하게 소유권 인수(이주 수렴)
            elif [ "$cur" != "$recorded" ]; then
                # installer 가 썼던 파일을 사용자가 수정 → 보존
                preserved=$((preserved + 1))
                continue
            fi
            if [ "$cur" = "$src_hash" ]; then
                # 이미 동일 — 쓰지 않는다. manifest 도 값이 같으면 건드리지 않는다
                # (매 실행 재작성은 manifest 바이트를 흔들어 멱등 스냅샷을 깬다)
                if [ -n "$manifest" ] && [ "$recorded" != "$src_hash" ]; then
                    if $DRY_RUN; then
                        log_info "[DRY RUN] Would adopt: ${label}${rel}"
                    else
                        rb_track "$manifest"
                        manifest_set "$manifest" "$mf_rel" "$src_hash"
                    fi
                fi
                continue
            fi
        fi

        if $DRY_RUN; then
            log_info "[DRY RUN] Would install: ${label}${rel}"
        else
            mkdir -p "$(dirname "$dst_file")"
            rb_track "$dst_file"
            cp -p "$src_file" "$dst_file"
            if [ -n "$manifest" ]; then
                rb_track "$manifest"
                manifest_set "$manifest" "$mf_rel" "$src_hash"
            fi
        fi
        changed=$((changed + 1))
    done < "$tmp_files"
    rm -f "$tmp_files"

    # ── Phase 3: stale 정리 — 소스에서 사라졌고 installer 소유·미변경인 파일만
    if [ -n "$manifest" ] && [ -f "$manifest" ]; then
        local tmp_stale
        tmp_stale="$(mktemp)" || return 1
        # 이 디렉토리 관할(prefix/) 항목만 추린다. awk 로 탭 분해 — 경로에
        # 공백이 있어도 안전.
        awk -F '\t' -v p="${prefix}/" 'NF >= 2 && index($1, p) == 1 { print }' \
            "$manifest" > "$tmp_stale"

        local mf_path mf_hash rel_in_dir
        while IFS="$(printf '\t')" read -r mf_path mf_hash; do
            [ -n "$mf_path" ] || continue
            if ! manifest_path_safe "$mf_path"; then
                log_warn "manifest 경로 거부(루트 이탈): ${mf_path}"
                continue
            fi
            rel_in_dir="${mf_path#"$prefix"/}"
            [ -f "${src}/${rel_in_dir}" ] && continue   # 소스에 아직 있음
            dst_file="${dst}/${rel_in_dir}"
            if [ -L "$dst_file" ] || ! managed_path_safe "$dst_file"; then
                continue
            fi
            if [ ! -e "$dst_file" ]; then
                # 목적지에도 없음 → 기록만 정리
                if ! $DRY_RUN; then
                    rb_track "$manifest"
                    manifest_remove "$manifest" "$mf_path"
                fi
                continue
            fi
            cur="$(manifest_hash_file "$dst_file")"
            if [ "$cur" != "$mf_hash" ]; then
                # 사용자가 수정한 파일 → 지우지 않는다 (기록은 유지: 재실행 멱등)
                preserved=$((preserved + 1))
                continue
            fi
            if $DRY_RUN; then
                log_info "[DRY RUN] Would remove stale: ${label}${rel_in_dir}"
            else
                rb_track "$dst_file"
                rb_track "$manifest"
                rm -f "$dst_file"
                manifest_remove "$manifest" "$mf_path"
                prune_empty_parents "$dst" "$dst_file"
            fi
            changed=$((changed + 1))
        done < "$tmp_stale"
        rm -f "$tmp_stale"
    fi

    if [ "$changed" -eq 0 ]; then
        log_ok "UNCHANGED: ${label}"
        UNCHANGED_COUNT=$((UNCHANGED_COUNT + 1))
    else
        if $DRY_RUN; then
            log_info "[DRY RUN] Would install: ${label}"
        else
            log_ok "INSTALLED: ${label} (${changed}건)"
        fi
        INSTALLED_COUNT=$((INSTALLED_COUNT + 1))
    fi
    if [ "$preserved" -gt 0 ]; then
        log_warn "PRESERVED (사용자 파일 ${preserved}건): ${label}"
    fi
}

# 사용자 소유 파일: 존재하면 절대 덮지 않음 (skip-if-exists)
install_user_file() {
    local src="$1" dst="$2" label="$3"
    if [ ! -f "$src" ]; then
        log_warn "소스 없음, 스킵: ${src}"
        SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
        return 0
    fi
    if [ -e "$dst" ]; then
        log_info "SKIPPED (이미 존재 — 사용자 소유): ${label}"
        SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
        return 0
    fi
    if $DRY_RUN; then
        log_info "[DRY RUN] Would install: ${label}"
    else
        mkdir -p "$(dirname "$dst")"
        rb_track "$dst"
        cp "$src" "$dst"
        log_ok "INSTALLED: ${label}"
    fi
    INSTALLED_COUNT=$((INSTALLED_COUNT + 1))
}

# 사용자 소유 파일(stdin 내용): 존재하면 절대 덮지 않음
install_user_content() {
    local dst="$1" label="$2"
    if [ -e "$dst" ]; then
        cat > /dev/null   # stdin 소비
        log_info "SKIPPED (이미 존재 — 사용자 소유): ${label}"
        SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
        return 0
    fi
    if $DRY_RUN; then
        cat > /dev/null
        log_info "[DRY RUN] Would create: ${label}"
    else
        mkdir -p "$(dirname "$dst")"
        rb_track "$dst"
        cat > "$dst"
        log_ok "INSTALLED: ${label}"
    fi
    INSTALLED_COUNT=$((INSTALLED_COUNT + 1))
}

ensure_gitkeep() {
    local path="$1"
    if [ -L "$path" ]; then
        log_warn "SKIPPED (심볼릭 링크 — 따라가지 않음): ${path}"
        SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
        return 0
    fi
    if [ -e "$path" ]; then
        # 이미 있다. 내용이 **비어 있으면** installer 가 만드는 것과 바이트 동일이므로
        # 잃을 사용자 데이터가 없다 → 소유권을 인수한다(구버전 업그레이드 수렴).
        # base 438aaf9 설치기가 만든 dev/*/.gitkeep 이 정확히 이 경우다. 인수하지
        # 않으면 영원히 소유권 불명으로 남아 --uninstall 이 자기 산출물을 남긴다.
        # 내용이 있으면 사용자 파일이므로 절대 인수하지 않는다.
        if ! $DRY_RUN && [ -f "$path" ] && [ ! -s "$path" ]; then
            mf_resolve "$path"
            if [ -n "$MF_FILE" ]; then
                local gk_hash
                gk_hash="$(manifest_hash_file "$path")"
                # 값이 실제로 달라질 때만 쓴다 — 매 실행 재작성은 manifest 바이트를
                # 흔들어 멱등 스냅샷을 깬다.
                if [ "$(manifest_get "$MF_FILE" "$MF_REL")" != "$gk_hash" ]; then
                    rb_track "$MF_FILE"
                    manifest_set "$MF_FILE" "$MF_REL" "$gk_hash"
                fi
            fi
        fi
        log_ok "UNCHANGED: ${path}"
        UNCHANGED_COUNT=$((UNCHANGED_COUNT + 1))
        return 0
    fi
    if $DRY_RUN; then
        log_info "[DRY RUN] Would create: ${path}"
    else
        mkdir -p "$(dirname "$path")"
        rb_track "$path"
        touch "$path"
        # installer 산출물이므로 소유권을 기록한다 — 기록이 없으면 --uninstall 이
        # 자기가 만든 빈 디렉토리 표식을 영원히 남긴다.
        # (위의 skip-if-exists 조기 반환 덕분에 사용자가 먼저 만든 .gitkeep 은
        #  여기 오지 않는다 = 절대 인수하지 않는다.)
        mf_resolve "$path"
        if [ -n "$MF_FILE" ]; then
            rb_track "$MF_FILE"
            manifest_set "$MF_FILE" "$MF_REL" "$(manifest_hash_file "$path")"
        fi
        log_ok "INSTALLED: ${path}"
    fi
    INSTALLED_COUNT=$((INSTALLED_COUNT + 1))
}

# settings.json 하나당 소유권 manifest 하나. settings.json 바로 옆에 둔다
# (~/.claude/.settings-manifest, <proj>/.claude/.settings-manifest).
# 이 값이 없으면 lib/merge-settings.sh 는 "이전에 무엇을 소유했는지"를 알 수 없어
# --uninstall 이 아무것도 되돌리지 못한다 — 실제로 그 상태였다(회귀).
settings_manifest_for() {
    printf '%s/.settings-manifest' "$(dirname "$1")"
}

# ──────────────────────────────────────────────────────
# 구버전(.settings-manifest 없음) 이주 배선
#
# 구버전 설치기가 써 놓은 광범위 권한(Bash(npm *) 등)과 옛 guard 훅은 소유 기록이
# 없어 "사용자 것"으로 보이고, 그래서 영원히 남는다. base 438aaf9 조각들이 소유했던
# identity 목록(lib/legacy-identities.tsv)이 그 이주 근거다.
#   제거 대상 = (그 목록) - (이번 조각이 선언한 identity)
# 즉 지금도 배포하는 항목은 남고 폐기된 항목만 사라진다.
#
# 판정 시점이 중요하다: manifest 파일은 첫 조각 병합에서 생성되므로, "지금 파일이
# 있는가"로 물으면 2번째 조각부터 legacy 가 아니라고 오판한다. 그래서 settings 경로별로
# **실행 시작 시점의** 부재 여부를 한 번만 기록해 두고 계속 그 값을 쓴다.
# 이 게이트가 폭발 반경도 제한한다 — 손으로 쓴 settings.json 에 처음 설치하는 경우
# 사용자의 Bash(npm *) 를 지우지 않는다.
# ──────────────────────────────────────────────────────
SETTINGS_LEGACY_CHECKED=""
SETTINGS_LEGACY_ELIGIBLE=""

msf_list_has() {
    # $1 = 개행 구분 목록, $2 = 찾을 값 (줄 단위 완전 일치)
    #
    # `printf | grep -q` 를 쓰지 않는다: grep -q 는 첫 매치에서 즉시 끝나고, 그러면
    # 생산자가 SIGPIPE 로 죽으며 `set -o pipefail` 이 그것을 파이프라인 실패로 바꾼다
    # (이 리포가 테스트 인프라에서 이미 한 번 당한 함정 — HANDOFF 참조).
    # 지금은 목록이 짧아 파이프 버퍼에 다 들어가서 우연히 동작할 뿐이다.
    # case 문 부분 일치는 서브프로세스도 파이프도 없어 그 함정 자체가 없다.
    # 양쪽을 개행으로 감싸 "줄 단위 완전 일치" 를 만든다. 패턴 안의 "$2" 는
    # 인용되어 있으므로 glob 메타문자가 있어도 리터럴로 비교된다.
    case "
${1}
" in
        *"
${2}
"*) return 0 ;;
    esac
    return 1
}

# 판정 단위는 (settings, fragment) 조합이다. 파일 단위로 물으면, 첫 실행에서
# python3 부재로 guardrails 가 스킵되고 cli-orchestration 이 .settings-manifest 를
# 만든 경우 다음 실행에서 "이미 이주됨"으로 오판해 옛 guardrails 훅이 영구히 남는다.
note_legacy_state() {
    local settings="$1" smanifest="$2" frag_id="$3"
    local key="${settings}|${frag_id}"
    msf_list_has "$SETTINGS_LEGACY_CHECKED" "$key" && return 0
    SETTINGS_LEGACY_CHECKED="${SETTINGS_LEGACY_CHECKED}
${key}"
    # 이 조각의 소유 기록이 (이번 실행에서 처음 볼 때) 없으면 아직 이주 전이다.
    if [ ! -f "$smanifest" ] || [ -z "$(msf_manifest_records "$smanifest" "$frag_id")" ]; then
        SETTINGS_LEGACY_ELIGIBLE="${SETTINGS_LEGACY_ELIGIBLE}
${key}"
    fi
    return 0
}

# 이주 근거 대조: 목록의 identity 가 **전부** 지금 settings 안에 있어야 한다.
#
# .settings-manifest 부재만으로 legacy 라 단정하면, 직접 관리하는 settings.json 에
# 우연히 Bash(npm *) 한 줄이 있다는 이유로 사용자 설정을 지운다. 구버전 설치기는
# 조각의 identity 를 한꺼번에 썼으므로 "통째로 있음" 이 곧 그 설치기의 지문이다.
# 부분 일치는 사용자가 직접 쓴 것으로 보고 건드리지 않는다(보수적).
legacy_corroborated() {
    local settings="$1" list="$2"
    [ -n "$list" ] || return 1
    [ -f "$settings" ] || return 1
    local present line
    present="$(msf_extract_records "$settings" 2>/dev/null)" || return 1
    [ -n "$present" ] || return 1
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        msf_list_has "$present" "$line" || return 1
    done <<LEGACY_EOF
${list}
LEGACY_EOF
    return 0
}

legacy_removals_for() {
    local frag_id="$1"
    if [ ! -f "$LEGACY_IDENTITIES_FILE" ]; then
        # 조용히 넘어가면 "이주된 줄 알았는데 안 된" 상태가 된다 — 반드시 알린다.
        log_warn "구버전 이주 목록 없음, 이주 스킵: ${LEGACY_IDENTITIES_FILE}"
        SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
        return 0
    fi
    msf_manifest_records "$LEGACY_IDENTITIES_FILE" "$frag_id"
}

# settings fragment 병합 (lib/merge-settings.sh 위임 + 카운트 반영)
merge_fragment_into() {
    local settings="$1" fragment="$2" label="$3"
    if $DRY_RUN; then MERGE_DRY_RUN=1; else MERGE_DRY_RUN=0; fi
    MERGE_MANIFEST="$(settings_manifest_for "$settings")"
    local frag_id_lg
    frag_id_lg="$(basename "$fragment")"
    note_legacy_state "$settings" "$MERGE_MANIFEST" "$frag_id_lg"
    MERGE_LEGACY_REMOVALS=""
    if msf_list_has "$SETTINGS_LEGACY_ELIGIBLE" "${settings}|${frag_id_lg}"; then
        local lg_cand
        lg_cand="$(legacy_removals_for "$frag_id_lg")"
        if legacy_corroborated "$settings" "$lg_cand"; then
            MERGE_LEGACY_REMOVALS="$lg_cand"
            log_warn "구버전 이주: ${label} — 폐기된 항목 $(printf '%s\n' "$lg_cand" | grep -c .)건 제거 (직전 상태는 .bak 에 보존)"
        fi
    fi
    if ! $DRY_RUN; then
        # 병합은 settings / 소유 manifest / 새 백업 파일 3가지를 건드린다.
        # 백업 경로는 결정적이므로 호출 전에 미리 추적해 둘 수 있다.
        rb_track "$settings"
        rb_track "$MERGE_MANIFEST"
        rb_track "$(msf_backup_index)"
        rb_track "$(msf_backup_path "$settings")"
        rb_track_backups "$settings"
    fi
    if ! merge_settings_fragment "$settings" "$fragment"; then
        log_error "settings 병합 실패: ${label} — fragment/settings JSON 유효성을 확인하세요"
        exit 1
    fi
    case "$MERGE_STATUS" in
        created)
            log_ok "INSTALLED: ${label} (settings 신규 생성)"
            INSTALLED_COUNT=$((INSTALLED_COUNT + 1))
            ;;
        merged)
            if [ -n "$MERGE_BACKUP_PATH" ]; then
                BACKED_UP_COUNT=$((BACKED_UP_COUNT + 1))
            fi
            log_ok "INSTALLED: ${label} (병합)"
            INSTALLED_COUNT=$((INSTALLED_COUNT + 1))
            ;;
        unchanged)
            log_ok "UNCHANGED: ${label}"
            UNCHANGED_COUNT=$((UNCHANGED_COUNT + 1))
            ;;
    esac
}


# ──────────────────────────────────────────────────────
# 원자적 롤백 저널
#
# 이 설치기는 수십 개 파일과 2개 settings.json 을 순차로 고친다. 중간에
# 실패하거나 Ctrl-C 가 들어오면 "절반만 설치된" 상태가 남는데, 그 상태는
# manifest 와 실제 파일이 어긋나 다음 실행의 소유권 판정까지 오염시킨다.
#
# 방식: 어떤 경로를 이번 실행에서 "처음" 건드리기 직전에 그 시점의 상태를
# 저널에 적는다(내용 사본 또는 '없었음' 표시). 실패 시 저널을 역순으로 되감아
# 정확히 그 상태로 되돌린다. 최초 상태만 기록하므로 같은 파일을 여러 번 고쳐도
# 복원 지점은 하나다.
#
# 트리거: EXIT 트랩 + INSTALL_COMPLETE 센티널. ERR 트랩만으로는 delegate_*
#   의 `exit 1` 을 못 잡고, 시그널 트랩만으로는 set -e 실패를 못 잡는다.
#   INT/TERM 은 `exit` 를 호출해 EXIT 트랩으로 합류시킨다.
#
# 범위 한계(의도적):
#   - 위임 설치기(system-setup / advisor 번들)가 쓴 파일은 이 저널 밖이다.
#     그쪽 산출물은 롤백되지 않는다 — 각 번들이 자체 백업 정책을 갖는다.
#   - 경로에 개행이 들어 있으면 저널이 깨진다(설치기 전체의 기존 가정과 동일).
# ──────────────────────────────────────────────────────
RB_DIR=""
RB_SEQ=0
INSTALL_COMPLETE=false

rb_init() {
    $DRY_RUN && return 0
    RB_DIR="$(mktemp -d)" || return 1
    : > "${RB_DIR}/journal"
    : > "${RB_DIR}/tracked"
    mkdir -p "${RB_DIR}/store"
}

# 경로를 건드리기 직전에 호출한다. 최초 1회만 기록한다.
rb_track() {
    [ -n "$RB_DIR" ] || return 0
    local path="$1"
    [ -n "$path" ] || return 0
    if grep -qxF "$path" "${RB_DIR}/tracked" 2>/dev/null; then
        return 0
    fi
    printf '%s\n' "$path" >> "${RB_DIR}/tracked"
    RB_SEQ=$((RB_SEQ + 1))
    if [ -f "$path" ]; then
        cp -p "$path" "${RB_DIR}/store/${RB_SEQ}"
        printf '%s\tfile\t%s\n' "$RB_SEQ" "$path" >> "${RB_DIR}/journal"
    elif [ -e "$path" ]; then
        # 디렉토리 등 — 내용 보존 대상이 아니므로 존재만 기록(복원 시 무시)
        printf '%s\tother\t%s\n' "$RB_SEQ" "$path" >> "${RB_DIR}/journal"
    else
        printf '%s\tabsent\t%s\n' "$RB_SEQ" "$path" >> "${RB_DIR}/journal"
    fi
}

# 기존 백업들을 prune 이 지우기 전에 통째로 추적한다
# (prune 은 어느 것을 지울지 호출자에게 알려주지 않는다)
rb_track_backups() {
    [ -n "$RB_DIR" ] || return 0
    local f="$1" dir base b
    dir="$(dirname "$f")"
    base="$(basename "$f")"
    while IFS= read -r b; do
        [ -n "$b" ] && rb_track "$b"
    done < <(find "$dir" -maxdepth 1 \( -name "${base}.bak" -o -name "${base}.bak.*" \) -print 2>/dev/null)
}

# 롤백으로 파일을 지운 뒤 비게 된 디렉토리를 관리 루트 안에서만 정리한다
rb_prune_dir() {
    local path="$1"
    case "$path" in
        "$CLAUDE_HOME"/*) prune_empty_parents "$CLAUDE_HOME" "$path" ;;
        *)
            if [ -n "$PROJECT_DIR" ]; then
                case "$path" in
                    "$PROJECT_DIR"/*) prune_empty_parents "$PROJECT_DIR" "$path" ;;
                esac
            fi
            ;;
    esac
}

rb_rollback() {
    [ -n "$RB_DIR" ] || return 0
    [ -f "${RB_DIR}/journal" ] || return 0
    local n
    n="$(wc -l < "${RB_DIR}/journal" 2>/dev/null | tr -d ' ')"
    [ -n "$n" ] && [ "$n" -gt 0 ] || return 0

    log_error "설치가 완료되지 않았습니다 — 이번 실행이 바꾼 ${n}건을 되돌립니다 (ROLLBACK)"
    local seq kind path
    while IFS="$(printf '\t')" read -r seq kind path; do
        [ -n "$path" ] || continue
        case "$kind" in
            file)
                mkdir -p "$(dirname "$path")" 2>/dev/null || true
                cp -p "${RB_DIR}/store/${seq}" "$path" 2>/dev/null || true
                ;;
            absent)
                rm -f "$path" 2>/dev/null || true
                rb_prune_dir "$path"
                ;;
        esac
    done < <(sed -n '1!G;h;$p' "${RB_DIR}/journal")
    log_error "ROLLBACK 완료: ${n}건 원상 복구 (위임 설치기 산출물은 대상 밖)"
}

rb_finish() {
    local rc=$?
    if ! $INSTALL_COMPLETE; then
        rb_rollback || true
    fi
    if [ -n "$RB_DIR" ]; then
        rm -rf "$RB_DIR" 2>/dev/null || true
    fi
    exit "$rc"
}


# ──────────────────────────────────────────────────────
# 통째로 제거된 자산의 stale 정리 (루트 단위 스윕)
#
# install_managed_dir 의 stale 정리는 "이번에 열거된 디렉토리 안"만 본다. 그래서
# 스킬 디렉토리가 통째로 사라지거나 rules/agents 파일이 업스트림에서 삭제되면
# 그 항목은 애초에 방문되지 않아 목적지와 manifest 양쪽에 영원히 남았다.
# 여기서는 manifest 를 루트 단위로 훑어, "관리 접두에 속하는데 그 자산을 만든
# 소스가 더 이상 없는" 항목을 정리한다.
#
# 판정 기준은 '이번 실행에서 건드렸는가' 가 아니라 **소스 존재 여부**다. 전자로
# 하면 --with-examples 없이 돌렸을 때 이전에 깐 examples 자산이 지워진다 —
# 사용자가 이번에 요청하지 않았을 뿐 업스트림에는 그대로 있는데도.
# 삭제 조건은 다른 곳과 동일하다: manifest 기록 해시 == 현재 해시(소유·미변경).
# ──────────────────────────────────────────────────────

# normalize_docs_dirname 의 역함수. 정규화가 단사(單射)가 아닐 수 있으므로
# 후보를 둘 다 내고 "하나라도 있으면 살아 있음" 으로 본다(보수적).
denormalize_docs_dirname() {
    case "$1" in
        "system-setup") printf '%s\n%s\n' "Claude code system setup" "system-setup" ;;
        *)              printf '%s\n' "$1" ;;
    esac
}

# manifest 상대경로 → 그 자산을 만든 소스 후보(개행 구분).
# 관리 접두가 아니면 return 1 (스윕 대상 아님 — 사용자/위임 설치기 산출물 보호).
manifest_source_candidates() {
    local scope="$1" rel="$2" rest dirname sub d
    if [ "$scope" = "global" ]; then
        case "$rel" in
            rules/*|skills/*)
                printf '%s\n' "${SCRIPT_DIR}/global/${rel}"
                ;;
            docs/claude-code-setup/*)
                rest="${rel#docs/claude-code-setup/}"
                case "$rest" in
                    */*) dirname="${rest%%/*}"; sub="${rest#*/}" ;;
                    *)   return 1 ;;
                esac
                while IFS= read -r d; do
                    [ -n "$d" ] && printf '%s\n' "${DOCS_SRC_DIR}/${d}/${sub}"
                done <<EOF
$(denormalize_docs_dirname "$dirname")
EOF
                ;;
            *) return 1 ;;
        esac
        return 0
    fi

    case "$rel" in
        .claude/skills/*|.claude/agents/*)
            # project/ 와 examples/ 두 곳에서 올 수 있다
            printf '%s\n' "${SCRIPT_DIR}/project/${rel#.claude/}" \
                          "${SCRIPT_DIR}/examples/${rel#.claude/}"
            ;;
        .claude/commands/*|.claude/hooks/*)
            printf '%s\n' "${SCRIPT_DIR}/project/${rel#.claude/}"
            ;;
        .claude/settings-fragments/*)
            printf '%s\n' "${FRAGMENTS_DIR}/${rel#.claude/settings-fragments/}"
            ;;
        docs/templates/pm2/*)
            printf '%s\n' "${SCRIPT_DIR}/templates/pm2/${rel#docs/templates/pm2/}"
            ;;
        docs/Parallel_Agents_Safety_Protocol_v3_1_0.md)
            printf '%s\n' "$SAFETY_DOC_SRC"
            ;;
        *) return 1 ;;
    esac
    return 0
}

# 후보 소스 경로가 속한 최상위 소스 디렉토리(SCRIPT_DIR 바로 아래)를 돌려준다.
# 그 디렉토리가 없으면 "소스에서 사라졌다" 고 결론지을 수 없다.
# 후보 소스가 속한 "카테고리 디렉토리" 를 돌려준다.
#
# 최상위(global/)만 보면 부족하다 — `global/` 은 있는데 `global/skills/` 만 빠진
# 사본에서 설치된 스킬 19개가 전부 삭제됐다(실측). 반대로 너무 깊이 보면 업스트림이
# 실제로 지운 디렉토리까지 "판단 보류" 가 되어 stale 정리가 영영 안 된다.
# 두 성분(예: global/skills, docs/<번들>)이 균형점이다.
source_root_of() {
    local c="$1" rel first second
    rel="${c#"$SCRIPT_DIR"/}"
    if [ "$rel" = "$c" ]; then
        printf '%s' "$(dirname "$c")"
        return 0
    fi
    first="${rel%%/*}"
    rel="${rel#*/}"
    case "$rel" in
        */*) second="${rel%%/*}" ;;
        *)   printf '%s/%s' "$SCRIPT_DIR" "$first"; return 0 ;;
    esac
    printf '%s/%s/%s' "$SCRIPT_DIR" "$first" "$second"
}

sweep_removed_assets() {
    local root="$1" scope="$2" label="$3"
    local manifest="${root}/.manifest"
    [ -f "$manifest" ] || return 0

    local snap cands rel hash target cur alive c root_missing
    snap="$(mktemp)" || return 0
    cp "$manifest" "$snap"

    while IFS="$(printf '\t')" read -r rel hash; do
        [ -n "$rel" ] || continue
        cands="$(manifest_source_candidates "$scope" "$rel")" || continue
        alive=false
        root_missing=false
        while IFS= read -r c; do
            [ -n "$c" ] || continue
            if [ -e "$c" ]; then alive=true; break; fi
            # 후보가 없다고 곧바로 "업스트림에서 삭제됨" 이라고 결론지으면 안 된다.
            # 그 후보가 속한 **소스 루트 자체가 없으면**(불완전한 체크아웃·패키징
            # 사본) 판단 근거가 없는 것이다. 실측: docs/ 만 빠져도 설치된 문서
            # 21개 중 20개가 지워지고 exit 0 이었다.
            [ -d "$(source_root_of "$c")" ] || root_missing=true
        done <<EOF
$cands
EOF
        $alive && continue
        if $root_missing; then
            log_warn "소스 루트 없음 — stale 판단 보류: ${label}/${rel}"
            continue
        fi

        # 루트 스윕은 **일반 설치** 중에 돈다. 여기가 뚫리면 설치만 해도 관리 루트
        # 밖 파일이 지워진다(실측 확인). uninstall 경로와 같은 검증을 건다.
        if ! manifest_path_safe "$rel"; then
            log_warn "manifest 경로 거부(루트 이탈): ${label}/${rel}"
            continue
        fi
        target="${root}/${rel}"
        # 설치 이후 관리 디렉토리가 링크로 바뀌었을 수 있다. 해싱·삭제 직전에
        # 다시 검사한다 — 링크 너머 파일의 해시가 우연히 일치하면 밖을 지운다.
        if [ -L "$target" ] || ! managed_path_safe "$target"; then
            log_warn "SKIPPED (심볼릭 링크 경로 — 삭제하지 않음): ${label}/${rel}"
            continue
        fi
        if [ ! -e "$target" ]; then
            if ! $DRY_RUN; then
                rb_track "$manifest"
                manifest_remove "$manifest" "$rel"
            fi
            continue
        fi
        cur="$(manifest_hash_file "$target")"
        if [ "$cur" != "$hash" ]; then
            log_warn "PRESERVED (사용자 수정, 업스트림에서 제거됨): ${label}/${rel}"
            SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
            continue
        fi
        if $DRY_RUN; then
            log_info "[DRY RUN] Would remove (업스트림에서 제거됨): ${label}/${rel}"
        else
            rb_track "$target"
            rb_track "$manifest"
            rm -f "$target"
            manifest_remove "$manifest" "$rel"
            prune_empty_parents "$root" "$target"
            log_warn "REMOVED (업스트림에서 제거됨): ${label}/${rel}"
        fi
        REMOVED_COUNT=$((REMOVED_COUNT + 1))
    done < "$snap"
    rm -f "$snap"
}

# ──────────────────────────────────────────────────────
# 제거(uninstall) — installer 가 소유한 것만 되돌린다
#
# 정책 (설치 정책의 정확한 역연산):
#   파일     : manifest 기록 해시 == 현재 해시일 때만 제거.
#              사용자가 수정했거나(해시 상이) manifest 에 없는(사용자 추가·
#              install_user_file 로 깐 CLAUDE.md 등) 파일은 손대지 않는다.
#   settings : .settings-manifest 가 기록한 hooks/permissions identity 만 제거.
#              사용자 훅·사용자 allow·그 밖의 최상위 키는 전부 보존된다.
#   디렉토리 : 제거 결과로 "빈" 디렉토리만 정리한다.
#   백업     : *.bak 은 남긴다 — 복구 수단을 제거가 지우면 안 된다.
#   위임분   : system-setup / advisor 번들이 깐 파일은 이 manifest 밖이라
#              제거 대상이 아니다(각 번들의 책임).
# 재실행은 멱등이다 — 두 번째 --uninstall 은 아무것도 바꾸지 않는다.
# ──────────────────────────────────────────────────────
uninstall_manifest_root() {
    local root="$1" label="$2"
    local manifest="${root}/.manifest"
    if [ ! -f "$manifest" ]; then
        log_info "manifest 없음 — 제거할 소유 파일 없음: ${label}"
        return 0
    fi
    # manifest 는 루프 안에서 갱신되므로 스냅샷을 떠서 순회한다
    local snap
    snap="$(mktemp)" || return 1
    cp "$manifest" "$snap"

    local rel hash target cur
    while IFS="$(printf '\t')" read -r rel hash; do
        [ -n "$rel" ] || continue
        if ! manifest_path_safe "$rel"; then
            log_warn "manifest 경로 거부(루트 이탈): ${label}/${rel}"
            continue
        fi
        target="${root}/${rel}"
        # 설치 이후 관리 디렉토리가 링크로 바뀌었을 수 있다. 해싱·삭제 직전에
        # 다시 검사한다 — 링크 너머 파일의 해시가 우연히 일치하면 밖을 지운다.
        if [ -L "$target" ] || ! managed_path_safe "$target"; then
            log_warn "SKIPPED (심볼릭 링크 경로 — 삭제하지 않음): ${label}/${rel}"
            continue
        fi
        if [ ! -e "$target" ]; then
            if ! $DRY_RUN; then
                rb_track "$manifest"
                manifest_remove "$manifest" "$rel"
            fi
            continue
        fi
        cur="$(manifest_hash_file "$target")"
        if [ "$cur" != "$hash" ]; then
            log_warn "PRESERVED (사용자 수정): ${label}/${rel}"
            PRESERVED_COUNT=$((PRESERVED_COUNT + 1))
            continue
        fi
        if $DRY_RUN; then
            log_info "[DRY RUN] Would remove: ${label}/${rel}"
        else
            rb_track "$target"
            rb_track "$manifest"
            rm -f "$target"
            manifest_remove "$manifest" "$rel"
            prune_empty_parents "$root" "$target"
        fi
        REMOVED_COUNT=$((REMOVED_COUNT + 1))
    done < "$snap"
    rm -f "$snap"

    # 남은 항목이 없으면 manifest 파일 자체를 정리한다
    # 사용자가 링크로 관리하는 기록 파일은 지우지 않는다 — 비었다고 링크를
    # 지우면 dotfile 관리가 끊긴다. 내용만 빈 채로 둔다.
    if ! $DRY_RUN && [ ! -L "$manifest" ] && [ -f "$manifest" ] && [ ! -s "$manifest" ]; then
        rb_track "$manifest"
        rm -f "$manifest"
    fi
}

uninstall_settings() {
    local settings="$1" label="$2"
    local smanifest
    smanifest="$(settings_manifest_for "$settings")"
    if [ ! -f "$smanifest" ] || [ ! -f "$settings" ]; then
        log_info "settings 소유 기록 없음 — 스킵: ${label}"
        return 0
    fi
    if $DRY_RUN; then MERGE_DRY_RUN=1; else MERGE_DRY_RUN=0; fi
    MERGE_MANIFEST="$smanifest"
    if ! $DRY_RUN; then
        rb_track "$settings"
        rb_track "$smanifest"
        # unmerge 도 백업을 만들며 소유 색인에 줄을 덧붙인다. 저널에 없으면 뒤
        # 단계 실패 시 색인의 새 줄만 남아, 나중에 그 경로에 생길 사용자 파일이
        # "우리 것" 으로 오인돼 정리 대상이 된다.
        rb_track "$(msf_backup_index)"
        rb_track "$(msf_backup_path "$settings")"
        rb_track_backups "$settings"
    fi

    # 소유 fragment id 목록을 기록에서 직접 뽑는다 — 하드코딩하면 더 이상
    # 배포하지 않는 옛 조각의 소유분이 영원히 남는다.
    local ids
    ids="$(awk -F '\t' 'NF >= 2 { print $1 }' "$smanifest" | sort -u)"
    # `for id in $ids` 는 공백에서 쪼개지고 글로브가 확장된다 — 그런 id 가 소유한
    # 훅·권한이 영원히 남는다. 줄 단위로 읽는다.
    local id
    while IFS= read -r id; do
        [ -n "$id" ] || continue
        if ! unmerge_settings_fragment "$settings" "$id"; then
            log_error "settings 제거 실패: ${label} <- ${id}"
            exit 1
        fi
        case "$MERGE_STATUS" in
            merged)
                log_ok "REMOVED: ${label} (-${id})"
                REMOVED_COUNT=$((REMOVED_COUNT + 1))
                ;;
            *)
                log_ok "UNCHANGED: ${label} (-${id})"
                UNCHANGED_COUNT=$((UNCHANGED_COUNT + 1))
                ;;
        esac
    done <<UNINSTALL_IDS_EOF
${ids}
UNINSTALL_IDS_EOF
    # 사용자가 링크로 관리하는 기록 파일은 지우지 않는다 — 비었다고 링크를
    # 지우면 dotfile 관리가 끊긴다. 내용만 빈 채로 둔다.
    if ! $DRY_RUN && [ ! -L "$smanifest" ] && [ -f "$smanifest" ] && [ ! -s "$smanifest" ]; then
        rb_track "$smanifest"
        rm -f "$smanifest"
    fi
}

# 배포가 끝난 조각(소스에서 사라진 fragment)이 settings 에 남긴 hooks/permissions 를
# 정리한다. 파일 스윕은 `.manifest` 만 훑기 때문에, 조각 파일이 사라져도 그 조각이
# 이미 병합해 둔 훅은 settings 에 남아 계속 실행된다.
sweep_removed_fragments() {
    local settings="$1" frag_dir="$2" label="$3"
    local smanifest; smanifest="$(settings_manifest_for "$settings")"
    [ -f "$smanifest" ] || return 0
    [ -f "$settings" ] || return 0
    # 조각 디렉토리 자체가 없으면(불완전한 체크아웃) 판단 근거가 없다 — 보류.
    [ -d "$frag_dir" ] || { log_warn "조각 디렉토리 없음 — settings stale 판단 보류: ${label}"; return 0; }

    if $DRY_RUN; then MERGE_DRY_RUN=1; else MERGE_DRY_RUN=0; fi
    MERGE_MANIFEST="$smanifest"
    local ids id
    ids="$(awk -F '\t' 'NF >= 2 { print $1 }' "$smanifest" | sort -u)"
    # 줄 단위 읽기 — 공백·글로브가 든 조각 이름도 그대로 다룬다.
    while IFS= read -r id; do
        [ -n "$id" ] || continue
        [ -f "${frag_dir}/${id}" ] && continue      # 아직 배포 중
        if ! $DRY_RUN; then
            rb_track "$settings"
            rb_track "$smanifest"
            rb_track "$(msf_backup_index)"
            rb_track "$(msf_backup_path "$settings")"
            rb_track_backups "$settings"
        fi
        if ! unmerge_settings_fragment "$settings" "$id"; then
            log_error "사라진 조각 정리 실패: ${label} <- ${id}"
            exit 1
        fi
        case "$MERGE_STATUS" in
            merged)
                log_warn "REMOVED (조각이 더 이상 배포되지 않음): ${label} (-${id})"
                REMOVED_COUNT=$((REMOVED_COUNT + 1))
                ;;
        esac
    done <<SWEEP_IDS_EOF
${ids}
SWEEP_IDS_EOF
}

run_uninstall() {
    log_info "제거 모드 — installer 소유 자산만 되돌립니다 (사용자 내용 보존)"
    echo ""
    uninstall_settings "${CLAUDE_HOME}/settings.json" "~/.claude/settings.json"
    uninstall_manifest_root "$CLAUDE_HOME" "~/.claude"
    if [ -n "$PROJECT_DIR" ]; then
        echo ""
        uninstall_settings "${PROJECT_DIR}/.claude/settings.json" ".claude/settings.json"
        uninstall_manifest_root "$PROJECT_DIR" "$PROJECT_DIR"
    fi
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Uninstall Summary"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  REMOVED: ${REMOVED_COUNT} | PRESERVED(사용자): ${PRESERVED_COUNT} | UNCHANGED: ${UNCHANGED_COUNT}"
    echo "  백업(*.bak)과 위임 설치기(system-setup / advisor) 산출물은 그대로 둡니다."
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# ──────────────────────────────────────────────────────
# Project dir resolution — 유일한 TTY 예외 지점
# ──────────────────────────────────────────────────────
resolve_project_dir() {
    if $GLOBAL_ONLY; then
        PROJECT_DIR=""
        return 0
    fi
    if [ -z "$PROJECT_DIR" ]; then
        if ! $ANY_FLAG && [ -t 0 ]; then
            printf "프로젝트 설치 대상 경로 (비우면 글로벌만 설치): "
            read -r PROJECT_DIR
            PROJECT_DIR="${PROJECT_DIR/#\~/$HOME}"
        else
            log_info "--project 미지정(비TTY 또는 플래그 실행) — 프로젝트 단계를 스킵합니다."
        fi
        if [ -z "$PROJECT_DIR" ]; then
            return 0
        fi
    fi
    if [ -d "$PROJECT_DIR" ]; then
        PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd -P)"
    else
        # 제거 모드는 지울 것이 없으면 아무것도 하지 않는다 — 없는 프로젝트를
        # 새로 만들어 두는 것은 "제거" 가 파일시스템을 바꾸는 셈이다.
        if $UNINSTALL; then
            log_info "프로젝트 없음 — 제거할 것 없음: ${PROJECT_DIR}"
            PROJECT_DIR=""
            return 0
        fi
        if $DRY_RUN; then
            log_info "[DRY RUN] Would create: ${PROJECT_DIR}/"
        else
            mkdir -p "$PROJECT_DIR"
            PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd -P)"
        fi
    fi
}

# ──────────────────────────────────────────────────────
# Step 1: Global (~/.claude/rules, ~/.claude/skills, ~/.claude/docs) — 관리 파일 정책
# ──────────────────────────────────────────────────────

# docs/ 하위 디렉토리명 → 설치 대상 디렉토리명 정규화
# (bash 3.2 호환: 연관배열 대신 case)
normalize_docs_dirname() {
    case "$1" in
        "Claude code system setup") printf '%s' "system-setup" ;;
        *)                          printf '%s' "$1" ;;
    esac
}

# docs/ 하위의 모든 *.md 를 ~/.claude/docs/claude-code-setup/<정규화명>/ 에 설치.
# *.md 만 대상으로 하므로 docs/*/install.sh 2종은 구조적으로 제외된다 — 의도된 제외다:
#   (1) 설치기이지 문서가 아니고, (2) ~/.claude 아래 사본이 실행될 여지를 없애며,
#   (3) 두 번들의 정본(SSOT)은 리포의 원본 install.sh 이므로 사본은 드리프트만 만든다.
# 하위 경로는 그대로 보존한다(재귀). 디렉토리 생성은 install_managed_file 에 맡긴다
# (여기서 mkdir 하면 --dry-run 쓰기 0건 계약이 깨진다).
install_global_docs() {
    local d name norm f rel
    if [ ! -d "$DOCS_SRC_DIR" ]; then
        log_warn "docs 소스 없음, 스킵: ${DOCS_SRC_DIR}"
        SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
        return 0
    fi
    for d in "${DOCS_SRC_DIR}/"*/; do
        [ -d "$d" ] || continue
        d="${d%/}"
        name="$(basename "$d")"
        norm="$(normalize_docs_dirname "$name")"
        # 파이프 대신 프로세스 치환 — 파이프는 서브셸을 만들어 카운터가 유실된다.
        while IFS= read -r -d '' f; do
            rel="${f#"$d"/}"
            install_managed_file "$f" "${DOCS_DST_DIR}/${norm}/${rel}" \
                "~/.claude/docs/claude-code-setup/${norm}/${rel}"
        done < <(find "$d" -type f -name '*.md' -print0 2>/dev/null)
    done
}

# ~/.claude/settings.json 조각 병합 — skillOverrides 안전망.
#
# skillOverrides 는 스킬 description 의 컨텍스트 주입을 끄는 유일한 스위치다
# (2026-08-17 실측: 50개 항목이 약 15k 토큰의 주입을 차단하고 있었다). 그런데 이
# 조각을 두기 전까지 어떤 스크립트도 그 값을 소유하지 않아, 글로벌 settings.json 이
# 유실되면 복구 경로가 없고 토큰만 조용히 되돌아왔다 — 발화 신호가 없는 회귀다.
#
# 병합 계약(lib/merge-settings.sh)상 "기타 최상위 키 = 기존 값 우선"이므로:
#   - skillOverrides 가 살아 있으면 이 조각은 무시된다(사용자가 나중에 더한 항목 보존)
#   - **최상위 키 자체가 없을 때만** 스냅샷이 복원된다
# 따라서 재실행은 멱등이고 사용자 편집과 충돌하지 않는다.
#
# 범위 한계: 판정은 키 존재 여부(has) 한 번이다. 항목 일부만 지워진 "부분 유실"은
#   키가 남아 있으므로 복원되지 않는다. 이는 의도된 트레이드오프다 — 항목 단위로
#   병합하면 사용자가 일부러 지운 override 가 설치할 때마다 되살아난다.
#
# 조각 갱신(설정을 바꿨으면 이 명령으로 스냅샷을 다시 내보낼 것):
#   jq '{skillOverrides}' ~/.claude/settings.json \
#     > global/settings-fragments/skill-overrides.json
#
# 주의 1: 조각에 model 키를 절대 넣지 않는다 (Step 2b 의 불변식과 동일).
# 주의 2: 목록에 없는 스킬에 대한 override 는 무해하므로, 해당 스킬이 설치되지 않은
#         머신에 복원돼도 문제되지 않는다.
install_global_settings() {
    merge_fragment_into "${CLAUDE_HOME}/settings.json" \
        "${GLOBAL_FRAGMENTS_DIR}/skill-overrides.json" \
        "~/.claude/settings.json <- skill-overrides.json"
}

install_global() {
    log_info "글로벌 설치: ${CLAUDE_HOME}/"
    local f d name
    for f in "${SCRIPT_DIR}/global/rules/"*.md; do
        [ -f "$f" ] || continue
        name="$(basename "$f")"
        install_managed_file "$f" "${CLAUDE_HOME}/rules/${name}" "~/.claude/rules/${name}"
    done
    for d in "${SCRIPT_DIR}/global/skills/"*/; do
        [ -d "$d" ] || continue
        name="$(basename "$d")"
        install_managed_dir "$d" "${CLAUDE_HOME}/skills/${name}" "~/.claude/skills/${name}/"
    done
    install_global_docs
    install_global_settings
    sweep_removed_fragments "${CLAUDE_HOME}/settings.json" "$GLOBAL_FRAGMENTS_DIR" \
        "~/.claude/settings.json"
    # 업스트림에서 통째로 사라진 글로벌 자산 정리 (스킬 디렉토리 삭제, rules 삭제 등)
    sweep_removed_assets "$CLAUDE_HOME" "global" "~/.claude"
    echo ""
}

# ──────────────────────────────────────────────────────
# Step 2a: Project assets (skills/agents/commands + 사용자 소유 파일)
# ──────────────────────────────────────────────────────
install_project_assets() {
    local claude_dir="${PROJECT_DIR}/.claude"
    local f d name
    log_info "프로젝트 설치: ${claude_dir}/"
    for d in "${SCRIPT_DIR}/project/skills/"*/; do
        [ -d "$d" ] || continue
        name="$(basename "$d")"
        install_managed_dir "$d" "${claude_dir}/skills/${name}" ".claude/skills/${name}/"
    done
    for f in "${SCRIPT_DIR}/project/agents/"*.md; do
        [ -f "$f" ] || continue
        name="$(basename "$f")"
        install_managed_file "$f" "${claude_dir}/agents/${name}" ".claude/agents/${name}"
    done
    for f in "${SCRIPT_DIR}/project/commands/"*.md; do
        [ -f "$f" ] || continue
        name="$(basename "$f")"
        install_managed_file "$f" "${claude_dir}/commands/${name}" ".claude/commands/${name}"
    done
    install_user_file "${SCRIPT_DIR}/CLAUDE.md.template" "${PROJECT_DIR}/CLAUDE.md" "CLAUDE.md (템플릿)"
    install_user_file "${SCRIPT_DIR}/project/skill-rules.json" "${claude_dir}/skill-rules.json" ".claude/skill-rules.json"
}

# ──────────────────────────────────────────────────────
# Step 2a-2: 실행형 훅 스크립트 (.claude/hooks/*.sh) — 관리 파일 정책 + chmod +x
#   파일은 항상 설치한다(배선과 무관). settings.json 배선은 옵트인 플래그가 결정:
#   stop-self-check/build-checker → --with-verify-hooks, PM2 2종 → --with-pm2.
#   system-setup 위임분(skill-activator.sh, pre-compact-reminder.sh)과 이름이
#   겹치지 않으며, 그쪽도 파일 단위로 쓰므로 서로 덮어쓰지 않는다.
# ──────────────────────────────────────────────────────
install_project_hooks() {
    local claude_dir="${PROJECT_DIR}/.claude"
    local f name dst
    if [ ! -d "$HOOKS_SRC_DIR" ]; then
        log_warn "project/hooks 소스 없음 — 스킵"
        SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
        return 0
    fi
    for f in "${HOOKS_SRC_DIR}/"*.sh; do
        [ -f "$f" ] || continue
        name="$(basename "$f")"
        dst="${claude_dir}/hooks/${name}"
        install_managed_file "$f" "$dst" ".claude/hooks/${name}"
        # dry-run 은 파일을 만들지 않으므로 chmod 를 시도하면 set -e 로 전체가 죽는다.
        # 또한 installer 소유·미변경일 때만 권한을 손댄다 — 사용자가 수정해 보존된
        # 훅에 chmod +x 를 걸면 "보존" 계약을 내용이 아니라 권한 쪽에서 깬다.
        if ! $DRY_RUN && [ -f "$dst" ]; then
            mf_resolve "$dst"
            if [ -n "$MF_FILE" ] && \
               [ "$(manifest_get "$MF_FILE" "$MF_REL")" = "$(manifest_hash_file "$dst")" ]; then
                rb_track "$dst"
                chmod +x "$dst"
            fi
        fi
    done
}

# ──────────────────────────────────────────────────────
# Step 2b: settings.json fragment 병합
# 주의: settings.json 을 이 단계(위임 이전)에서 먼저 생성/병합해 두므로,
#       Step 3 의 system-setup install.sh 는 "기존 settings 존재" 경로
#       (이벤트 단위 딥머지)만 타게 되고, 그쪽 신규 생성 템플릿의 "model" 키
#       주입이 구조적으로 발생하지 않는다.
#       (이 설치기의 fragment 들에는 model 키를 절대 넣지 않는다.)
#       guardrails.json 의 PreToolUse 훅 2종은 python3 로 실행된다 —
#       python3 가 없으면 병합만 스킵한다(하드 실패 아님).
#       cli-orchestration.json 은 python3 무관이라 항상 병합되므로,
#       위 "settings 를 위임 이전에 먼저 만든다" 불변식은 그대로 유지된다.
# ──────────────────────────────────────────────────────
install_project_settings() {
    local claude_dir="${PROJECT_DIR}/.claude"
    local settings="${claude_dir}/settings.json"
    if command -v python3 >/dev/null 2>&1; then
        merge_fragment_into "$settings" "${FRAGMENTS_DIR}/guardrails.json" \
            ".claude/settings.json <- guardrails.json"
    else
        GUARDRAILS_SKIPPED=true
        log_warn "python3 없음 — guardrails 훅 병합 스킵"
        SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
    fi
    merge_fragment_into "$settings" "${FRAGMENTS_DIR}/cli-orchestration.json" \
        ".claude/settings.json <- cli-orchestration.json"
    if $INSTALL_VERIFY_FRAGMENT; then
        install_managed_file "${FRAGMENTS_DIR}/verification-hooks.json" \
            "${claude_dir}/settings-fragments/verification-hooks.json" \
            ".claude/settings-fragments/verification-hooks.json"
    fi
    if $WITH_VERIFY_HOOKS; then
        merge_fragment_into "$settings" "${FRAGMENTS_DIR}/verification-hooks.json" \
            ".claude/settings.json <- verification-hooks.json"
    fi
    # PM2 훅 배선: --with-pm2 를 명시했을 때만 (--full 만으로는 배선하지 않는다)
    if $PM2_HOOKS_MERGE; then
        merge_fragment_into "$settings" "${FRAGMENTS_DIR}/pm2-hooks.json" \
            ".claude/settings.json <- pm2-hooks.json"
    fi
    sweep_removed_fragments "$settings" "$FRAGMENTS_DIR" ".claude/settings.json"
}

# ──────────────────────────────────────────────────────
# Step 2c: 기타 프로젝트 산출물 (mcp example, 안전 프로토콜 문서,
#          dev/ gitkeep, 메모리 시드)
# ──────────────────────────────────────────────────────
install_project_extras() {
    if [ -f "${SCRIPT_DIR}/project/mcp.json.example" ]; then
        install_user_file "${SCRIPT_DIR}/project/mcp.json.example" \
            "${PROJECT_DIR}/.mcp.json.example" ".mcp.json.example"
    fi
    install_managed_file "$SAFETY_DOC_SRC" \
        "${PROJECT_DIR}/docs/Parallel_Agents_Safety_Protocol_v3_1_0.md" \
        "docs/Parallel_Agents_Safety_Protocol_v3_1_0.md"
    ensure_gitkeep "${PROJECT_DIR}/dev/active/.gitkeep"
    ensure_gitkeep "${PROJECT_DIR}/dev/completed/.gitkeep"
    # 메모리 시드: slug = 프로젝트 절대경로의 '/' 와 '.' 을 '-' 로 치환
    local slug
    slug="$(printf '%s' "$PROJECT_DIR" | tr '/.' '--')"
    install_user_content "${CLAUDE_HOME}/projects/${slug}/memory/MEMORY.md" \
        "~/.claude/projects/${slug}/memory/MEMORY.md" <<'MEM_EOF'
# Auto Memory

(프로젝트 메모리 시드 — Claude Code 세션에서 얻은 학습·결정·함정을 여기에 축적하세요.)
MEM_EOF
}

# ──────────────────────────────────────────────────────
# Step 3: system-setup 설치기 위임
# ──────────────────────────────────────────────────────
delegate_system_setup() {
    if [ ! -f "$SYSTEM_SETUP_INSTALLER" ]; then
        log_error "system-setup 설치기 없음: ${SYSTEM_SETUP_INSTALLER}"
        exit 1
    fi
    if $DRY_RUN; then
        log_info "[DRY RUN] Would delegate: bash \"${SYSTEM_SETUP_INSTALLER}\" \"${PROJECT_DIR}\""
        return 0
    fi
    log_info "system-setup 설치기 위임: ${SYSTEM_SETUP_INSTALLER}"
    bash "$SYSTEM_SETUP_INSTALLER" "$PROJECT_DIR"
    echo ""
}

# ──────────────────────────────────────────────────────
# Step 4: advisor-worker 번들 위임 (--with-advisor / --full)
# ──────────────────────────────────────────────────────
delegate_advisor() {
    if [ ! -f "$ADVISOR_INSTALLER" ]; then
        log_warn "advisor 설치기 없음, 스킵: ${ADVISOR_INSTALLER}"
        SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
        return 0
    fi
    if [ -f "${CLAUDE_HOME}/CLAUDE.md" ] && \
       ! grep -q '<!-- codex-advisor-worker-bundle:start' "${CLAUDE_HOME}/CLAUDE.md"; then
        log_warn "~/.claude/CLAUDE.md 에 번들 마커가 없습니다 — 번들 설치 시 기존 개인 내용은 백업으로 이동됩니다."
    fi
    if $DRY_RUN; then
        log_info "[DRY RUN] Would delegate: bash \"${ADVISOR_INSTALLER}\""
        return 0
    fi
    log_info "advisor-worker 번들 설치기 위임: ${ADVISOR_INSTALLER}"
    bash "$ADVISOR_INSTALLER"
    echo ""
}

# ──────────────────────────────────────────────────────
# Step 5: examples 자산 (--with-examples / --full) — 관리 파일 정책
# ──────────────────────────────────────────────────────
install_examples() {
    local claude_dir="${PROJECT_DIR}/.claude"
    local f d name found=false
    for d in "${SCRIPT_DIR}/examples/skills/"*/; do
        [ -d "$d" ] || continue
        found=true
        name="$(basename "$d")"
        install_managed_dir "$d" "${claude_dir}/skills/${name}" ".claude/skills/${name}/ (example)"
    done
    for f in "${SCRIPT_DIR}/examples/agents/"*.md; do
        [ -f "$f" ] || continue
        found=true
        name="$(basename "$f")"
        install_managed_file "$f" "${claude_dir}/agents/${name}" ".claude/agents/${name} (example)"
    done
    if ! $found; then
        log_warn "examples/skills, examples/agents 에 설치할 자산 없음 — 스킵"
        SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
    fi
}

# ──────────────────────────────────────────────────────
# Step 6: PM2 템플릿 (--with-pm2 / --full) — 비파괴 템플릿 복사
# ──────────────────────────────────────────────────────
install_pm2_templates() {
    if [ ! -d "${SCRIPT_DIR}/templates/pm2" ]; then
        log_warn "templates/pm2 소스 없음 — 스킵"
        SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
        return 0
    fi
    install_managed_dir "${SCRIPT_DIR}/templates/pm2" \
        "${PROJECT_DIR}/docs/templates/pm2" "docs/templates/pm2/"
}

# ──────────────────────────────────────────────────────
# Step 7: POST-INSTALL 체크리스트
# ──────────────────────────────────────────────────────
print_checklist() {
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  POST-INSTALL 체크리스트 (세션/수동 단계)"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  1. Codex 플러그인은 Claude Code 세션 안에서 설치:"
    echo "       /plugin marketplace add openai/codex"
    echo "       /plugin install codex@codex"
    echo "     이후 터미널에서: codex login"
    echo "  2. MCP: .mcp.json.example 을 .mcp.json 으로 리네임하고 시크릿(토큰/키)을 주입"
    echo "  3. PM2(--with-pm2): docs/templates/pm2/ 커스터마이징 후 로그 로테이션 설정:"
    echo "       pm2 install pm2-logrotate"
    echo "       pm2 set pm2-logrotate:max_size 10M"
    echo "       pm2 set pm2-logrotate:retain 14"
    echo "       pm2 set pm2-logrotate:compress true"
    echo "  4. verify-hooks: .claude/settings-fragments/verification-hooks.json 은"
    echo "     --with-verify-hooks 명시 시에만 settings.json 에 병합됩니다"
    echo "     (tsc/lint 자동 훅 — 프로젝트 스택에 맞게 명령 조정 권장)."
    echo "  5. GSD / Gstack 은 별도 마켓플레이스에서 설치 (본 설치기 범위 밖)."
    echo "  6. 실행형 훅 4종은 .claude/hooks/ 에 항상 설치됩니다(파일만):"
    echo "       stop-self-check.sh / build-checker.sh  -> --with-verify-hooks 로 배선"
    echo "       post-tool-failure.sh / service-health-check.sh -> --with-pm2 로 배선"
    echo "     전부 advisory(항상 exit 0)이며 jq(PM2 훅은 pm2)가 없으면 무동작합니다."
    if $GUARDRAILS_SKIPPED; then
        echo "  7. guardrails 훅(위험 Bash 차단·보호 파일 쓰기 차단)은 python3 가 없어"
        echo "     settings.json 병합을 스킵했습니다 — python3 설치 후 재실행하면 자동 병합됩니다."
    fi
    echo ""
}

print_summary() {
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Installation Summary"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  INSTALLED: ${INSTALLED_COUNT} | UNCHANGED: ${UNCHANGED_COUNT} | BACKED_UP: ${BACKED_UP_COUNT} | SKIPPED: ${SKIPPED_COUNT}"
    echo "  (위임 설치기 system-setup / advisor-worker 의 상세는 각자의 요약 출력 참조)"
    echo ""
    echo "  Global: ~/.claude/rules/ + ~/.claude/skills/ + ~/.claude/docs/claude-code-setup/"
    echo "          + ~/.claude/settings.json (skillOverrides — 부재 시에만 복원)"
    if [ -n "$PROJECT_DIR" ]; then
        echo "  Project: ${PROJECT_DIR}/.claude/"
    fi
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# ──────────────────────────────────────────────────────
# Main Flow (순서가 곧 충돌 해소 수단 — 임의 재배열 금지)
#   1) 글로벌 → 2) 프로젝트 자산+settings 병합 → 3) system-setup 위임
#   → 4) advisor 위임 → 5) examples → 6) pm2 → 7) 체크리스트
# ──────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Claude Code Universal Environment Setup"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if $DRY_RUN; then
    log_warn "DRY RUN MODE - No files will be modified"
    echo ""
fi

check_prereqs
rb_init
# INT/TERM 은 exit 로 EXIT 트랩에 합류시킨다 — 롤백 경로를 하나로 유지한다.
trap 'exit 130' INT
trap 'exit 143' TERM
trap rb_finish EXIT
resolve_project_dir

if $UNINSTALL; then
    run_uninstall
    INSTALL_COMPLETE=true
    exit 0
fi

install_global

if ! $GLOBAL_ONLY && [ -n "$PROJECT_DIR" ]; then
    install_project_assets
    install_project_hooks
    install_project_settings
    install_project_extras
    echo ""
    delegate_system_setup
fi

if $WITH_ADVISOR; then
    delegate_advisor
fi

if $WITH_EXAMPLES; then
    if ! $GLOBAL_ONLY && [ -n "$PROJECT_DIR" ]; then
        install_examples
    else
        log_warn "--with-examples 는 프로젝트 대상 옵션 — 프로젝트 미지정으로 스킵"
        SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
    fi
fi

if $WITH_PM2; then
    if ! $GLOBAL_ONLY && [ -n "$PROJECT_DIR" ]; then
        install_pm2_templates
    else
        log_warn "--with-pm2 는 프로젝트 대상 옵션 — 프로젝트 미지정으로 스킵"
        SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
    fi
fi

# 프로젝트 스윕은 examples/pm2 까지 끝난 뒤에 한다 — 그 전에 돌리면 아직 설치되지
# 않은 옵션 자산을 "소스는 있는데 목적지에 없음" 으로 훑게 되어 순서 의존이 생긴다.
if ! $GLOBAL_ONLY && [ -n "$PROJECT_DIR" ]; then
    sweep_removed_assets "$PROJECT_DIR" "project" "$PROJECT_DIR"
fi

echo ""
print_checklist
print_summary
INSTALL_COMPLETE=true
