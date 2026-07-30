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
#   --with-verify-hooks  verification-hooks fragment 를 settings.json 에 병합
#   -h, --help           도움말
#
# 대화형 프롬프트 없음. 유일한 예외: 플래그 없이 실행 + stdin 이 TTY 일 때만
# 프로젝트 경로를 질문한다 (비TTY 는 프로젝트 단계 스킵 안내).
#
# 파일 정책:
#   - 관리 파일: 내용 동일 시 스킵(UNCHANGED), 변경 시 .bak(.bak.1...) 백업 후 갱신
#   - 관리 디렉토리: 동일 시 스킵, 다르면 백업 후 "교체" — 소스에 없는 파일은
#     목적지에서 제거된다(사용자가 넣은 파일은 .bak 에 보존)
#   - 사용자 소유 파일(CLAUDE.md, skill-rules.json, .mcp.json.example): skip-if-exists
#   - 요약에 INSTALLED / UNCHANGED / BACKED_UP / SKIPPED 카운트 출력
#
# 제약: bash 3.2 호환(연관배열·소문자변환 금지), 모든 경로 인용(공백 경로 지원)
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_HOME="${HOME}/.claude"
SYSTEM_SETUP_INSTALLER="${SCRIPT_DIR}/docs/Claude code system setup/install.sh"
ADVISOR_INSTALLER="${SCRIPT_DIR}/docs/codex-advisor-worker-bundle/install.sh"
SAFETY_DOC_SRC="${SCRIPT_DIR}/docs/Claude code system setup/Parallel Agents Safety Protocol v3.1.0.md"
FRAGMENTS_DIR="${SCRIPT_DIR}/project/settings-fragments"

# 공용 병합 엔진
# shellcheck source=lib/merge-settings.sh
. "${SCRIPT_DIR}/lib/merge-settings.sh"

DRY_RUN=false
GLOBAL_ONLY=false
PROJECT_DIR=""
FULL=false
WITH_ADVISOR=false
WITH_EXAMPLES=false
WITH_PM2=false
WITH_VERIFY_HOOKS=false
INSTALL_VERIFY_FRAGMENT=false
ANY_FLAG=false
GUARDRAILS_SKIPPED=false

INSTALLED_COUNT=0
UNCHANGED_COUNT=0
BACKED_UP_COUNT=0
SKIPPED_COUNT=0

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
    echo "  --with-pm2           Copy PM2 templates to <project>/docs/templates/pm2/"
    echo "  --with-verify-hooks  Merge verification-hooks fragment into settings.json"
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
        --with-pm2)          WITH_PM2=true; ANY_FLAG=true; shift ;;
        --with-verify-hooks) WITH_VERIFY_HOOKS=true; ANY_FLAG=true; shift ;;
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
backup_path() {
    local f="$1"
    if [ ! -e "$f.bak" ]; then
        printf '%s' "$f.bak"
        return
    fi
    local i=1
    while [ -e "$f.bak.$i" ]; do
        i=$((i + 1))
    done
    printf '%s' "$f.bak.$i"
}

# 관리 파일: 동일→UNCHANGED, 다름→백업 후 갱신, 없음→설치
install_managed_file() {
    local src="$1" dst="$2" label="$3"
    if [ ! -f "$src" ]; then
        log_warn "소스 없음, 스킵: ${src}"
        SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
        return 0
    fi
    if [ -f "$dst" ] && cmp -s "$src" "$dst"; then
        log_ok "UNCHANGED: ${label}"
        UNCHANGED_COUNT=$((UNCHANGED_COUNT + 1))
        return 0
    fi
    if [ -f "$dst" ]; then
        local bak
        bak="$(backup_path "$dst")"
        if $DRY_RUN; then
            log_info "[DRY RUN] Would backup: ${dst} -> ${bak}"
        else
            cp -p "$dst" "$bak"
            log_warn "BACKED_UP: ${dst} -> ${bak}"
        fi
        BACKED_UP_COUNT=$((BACKED_UP_COUNT + 1))
    fi
    if $DRY_RUN; then
        log_info "[DRY RUN] Would install: ${label}"
    else
        mkdir -p "$(dirname "$dst")"
        cp "$src" "$dst"
        log_ok "INSTALLED: ${label}"
    fi
    INSTALLED_COUNT=$((INSTALLED_COUNT + 1))
}

# 관리 디렉토리: 재귀 동일→UNCHANGED, 다름→디렉토리째 백업 후 "교체"
# (교체 의미론: 백업 → 목적지 비우기 → 소스 전체 복사.
#  복사만 하면 소스에서 삭제된 파일이 목적지에 잔존해 영구 diff + 매 실행 .bak 이 된다)
install_managed_dir() {
    local src="$1" dst="$2" label="$3"
    if [ ! -d "$src" ]; then
        log_warn "소스 없음, 스킵: ${src}"
        SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
        return 0
    fi
    if [ -d "$dst" ] && diff -rq "$src" "$dst" >/dev/null 2>&1; then
        log_ok "UNCHANGED: ${label}"
        UNCHANGED_COUNT=$((UNCHANGED_COUNT + 1))
        return 0
    fi
    if [ -d "$dst" ]; then
        local bak
        bak="$(backup_path "$dst")"
        if $DRY_RUN; then
            log_info "[DRY RUN] Would backup: ${dst} -> ${bak}"
        else
            cp -Rp "$dst" "$bak"
            log_warn "BACKED_UP: ${dst} -> ${bak}"
        fi
        BACKED_UP_COUNT=$((BACKED_UP_COUNT + 1))
    fi
    if $DRY_RUN; then
        log_info "[DRY RUN] Would install: ${label}"
    else
        # 백업은 위에서 이미 끝났다 — 여기서 목적지를 비우고 소스로 교체한다.
        if [ -n "$dst" ] && [ -d "$dst" ]; then
            rm -rf "$dst"
        fi
        mkdir -p "$dst"
        cp -R "${src}/." "$dst/"
        log_ok "INSTALLED: ${label}"
    fi
    INSTALLED_COUNT=$((INSTALLED_COUNT + 1))
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
        cat > "$dst"
        log_ok "INSTALLED: ${label}"
    fi
    INSTALLED_COUNT=$((INSTALLED_COUNT + 1))
}

ensure_gitkeep() {
    local path="$1"
    if [ -e "$path" ]; then
        log_ok "UNCHANGED: ${path}"
        UNCHANGED_COUNT=$((UNCHANGED_COUNT + 1))
        return 0
    fi
    if $DRY_RUN; then
        log_info "[DRY RUN] Would create: ${path}"
    else
        mkdir -p "$(dirname "$path")"
        touch "$path"
        log_ok "INSTALLED: ${path}"
    fi
    INSTALLED_COUNT=$((INSTALLED_COUNT + 1))
}

# settings fragment 병합 (lib/merge-settings.sh 위임 + 카운트 반영)
merge_fragment_into() {
    local settings="$1" fragment="$2" label="$3"
    if $DRY_RUN; then MERGE_DRY_RUN=1; else MERGE_DRY_RUN=0; fi
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
        PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"
    else
        if $DRY_RUN; then
            log_info "[DRY RUN] Would create: ${PROJECT_DIR}/"
        else
            mkdir -p "$PROJECT_DIR"
            PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"
        fi
    fi
}

# ──────────────────────────────────────────────────────
# Step 1: Global (~/.claude/rules, ~/.claude/skills) — 관리 파일 정책
# ──────────────────────────────────────────────────────
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
    echo "  6. 개념용 훅 4종(stop 자가검증·buildChecker·postToolUseFailure·serviceHealthCheck)은"
    echo "     실행형 소스가 docs 에 없어 v1 설치 범위 밖입니다 (문서 참조용)."
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
    echo "  Global: ~/.claude/rules/ + ~/.claude/skills/"
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
resolve_project_dir

install_global

if ! $GLOBAL_ONLY && [ -n "$PROJECT_DIR" ]; then
    install_project_assets
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

echo ""
print_checklist
print_summary
