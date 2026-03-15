#!/bin/bash
set -euo pipefail

# Claude Code Universal Environment Setup - Installer
# Usage:
#   ./install.sh                    # Interactive install
#   ./install.sh --global-only      # Global settings only
#   ./install.sh --project /path    # Install to specific project
#   ./install.sh --dry-run          # Preview changes

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_HOME="${HOME}/.claude"
DRY_RUN=false
GLOBAL_ONLY=false
PROJECT_DIR=""

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

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)    DRY_RUN=true; shift ;;
        --global-only) GLOBAL_ONLY=true; shift ;;
        --project)    PROJECT_DIR="$2"; shift 2 ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --global-only    Install global settings (~/.claude/) only"
            echo "  --project PATH   Install project settings to specified directory"
            echo "  --dry-run        Preview changes without modifying files"
            echo "  -h, --help       Show this help"
            exit 0
            ;;
        *) log_error "Unknown option: $1"; exit 1 ;;
    esac
done

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Claude Code Universal Environment Setup"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if $DRY_RUN; then
    log_warn "DRY RUN MODE - No files will be modified"
    echo ""
fi

# ──────────────────────────────────────────────────────
# Step 1: Install Global Settings
# ──────────────────────────────────────────────────────
install_global() {
    log_info "Installing global settings to ${CLAUDE_HOME}/"

    # Rules
    local rules_dir="${CLAUDE_HOME}/rules"
    if $DRY_RUN; then
        log_info "[DRY RUN] Would create: ${rules_dir}/"
    else
        mkdir -p "$rules_dir"
    fi

    local rules_count=0
    for rule_file in "${SCRIPT_DIR}/global/rules/"*.md; do
        [ -f "$rule_file" ] || continue
        local filename=$(basename "$rule_file")
        local target="${rules_dir}/${filename}"

        if [ -f "$target" ]; then
            if diff -q "$rule_file" "$target" > /dev/null 2>&1; then
                log_ok "Rule unchanged: ${filename}"
                continue
            else
                log_warn "Rule exists (different): ${filename}"
                if ! $DRY_RUN; then
                    read -p "  Overwrite? [y/N] " -n 1 -r
                    echo
                    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                        log_info "Skipped: ${filename}"
                        continue
                    fi
                fi
            fi
        fi

        if $DRY_RUN; then
            log_info "[DRY RUN] Would install: rules/${filename}"
        else
            cp "$rule_file" "$target"
            log_ok "Installed: rules/${filename}"
        fi
        ((rules_count++))
    done
    log_info "Rules: ${rules_count} installed"

    # Skills
    local skills_dir="${CLAUDE_HOME}/skills"
    if $DRY_RUN; then
        log_info "[DRY RUN] Would create: ${skills_dir}/"
    else
        mkdir -p "$skills_dir"
    fi

    local skills_count=0
    for skill_dir in "${SCRIPT_DIR}/global/skills/"*/; do
        [ -d "$skill_dir" ] || continue
        local skill_name=$(basename "$skill_dir")
        local target_dir="${skills_dir}/${skill_name}"

        if [ -d "$target_dir" ]; then
            if [ -f "${target_dir}/SKILL.md" ] && diff -q "${skill_dir}/SKILL.md" "${target_dir}/SKILL.md" > /dev/null 2>&1; then
                log_ok "Skill unchanged: ${skill_name}"
                continue
            else
                log_warn "Skill exists (different): ${skill_name}"
                if ! $DRY_RUN; then
                    read -p "  Overwrite? [y/N] " -n 1 -r
                    echo
                    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                        log_info "Skipped: ${skill_name}"
                        continue
                    fi
                fi
            fi
        fi

        if $DRY_RUN; then
            log_info "[DRY RUN] Would install: skills/${skill_name}/"
        else
            mkdir -p "$target_dir"
            cp -r "${skill_dir}"* "$target_dir/"
            log_ok "Installed: skills/${skill_name}"
        fi
        ((skills_count++))
    done
    log_info "Skills: ${skills_count} installed"
    echo ""
}

# ──────────────────────────────────────────────────────
# Step 2: Install Project Settings
# ──────────────────────────────────────────────────────
install_project() {
    local target_dir="$1"

    if [ ! -d "$target_dir" ]; then
        log_error "Directory not found: ${target_dir}"
        exit 1
    fi

    log_info "Installing project settings to ${target_dir}/.claude/"
    local claude_dir="${target_dir}/.claude"

    if $DRY_RUN; then
        log_info "[DRY RUN] Would create: ${claude_dir}/"
    else
        mkdir -p "${claude_dir}/skills" "${claude_dir}/agents" "${claude_dir}/commands"
    fi

    # Project Skills
    local count=0
    for skill_dir in "${SCRIPT_DIR}/project/skills/"*/; do
        [ -d "$skill_dir" ] || continue
        local skill_name=$(basename "$skill_dir")
        local target="${claude_dir}/skills/${skill_name}"

        if $DRY_RUN; then
            log_info "[DRY RUN] Would install: skills/${skill_name}"
        else
            mkdir -p "$target"
            cp -r "${skill_dir}"* "$target/"
            log_ok "Installed: skills/${skill_name}"
        fi
        ((count++))
    done
    log_info "Project skills: ${count} installed"

    # Agents
    count=0
    for agent_file in "${SCRIPT_DIR}/project/agents/"*.md; do
        [ -f "$agent_file" ] || continue
        local filename=$(basename "$agent_file")

        if $DRY_RUN; then
            log_info "[DRY RUN] Would install: agents/${filename}"
        else
            cp "$agent_file" "${claude_dir}/agents/${filename}"
            log_ok "Installed: agents/${filename}"
        fi
        ((count++))
    done
    log_info "Agents: ${count} installed"

    # Commands
    count=0
    for cmd_file in "${SCRIPT_DIR}/project/commands/"*.md; do
        [ -f "$cmd_file" ] || continue
        local filename=$(basename "$cmd_file")

        if $DRY_RUN; then
            log_info "[DRY RUN] Would install: commands/${filename}"
        else
            cp "$cmd_file" "${claude_dir}/commands/${filename}"
            log_ok "Installed: commands/${filename}"
        fi
        ((count++))
    done
    log_info "Commands: ${count} installed"

    # Hooks
    if [ -f "${SCRIPT_DIR}/project/hooks.json" ]; then
        local hooks_target="${claude_dir}/hooks.json"
        if [ -f "$hooks_target" ]; then
            log_warn "hooks.json already exists"
            if ! $DRY_RUN; then
                read -p "  Overwrite? [y/N] " -n 1 -r
                echo
                if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                    log_info "Skipped: hooks.json"
                else
                    cp "${SCRIPT_DIR}/project/hooks.json" "$hooks_target"
                    log_ok "Installed: hooks.json"
                fi
            fi
        else
            if $DRY_RUN; then
                log_info "[DRY RUN] Would install: hooks.json"
            else
                cp "${SCRIPT_DIR}/project/hooks.json" "$hooks_target"
                log_ok "Installed: hooks.json"
            fi
        fi
    fi

    # CLAUDE.md template
    local claudemd_target="${target_dir}/CLAUDE.md"
    if [ ! -f "$claudemd_target" ]; then
        if $DRY_RUN; then
            log_info "[DRY RUN] Would create: CLAUDE.md from template"
        else
            cp "${SCRIPT_DIR}/CLAUDE.md.template" "$claudemd_target"
            log_ok "Created: CLAUDE.md (from template - edit to customize)"
        fi
    else
        log_warn "CLAUDE.md already exists - skipping (see CLAUDE.md.template for reference)"
    fi

    echo ""
}

# ──────────────────────────────────────────────────────
# Main Flow
# ──────────────────────────────────────────────────────

# Always install global
install_global

# Project install
if ! $GLOBAL_ONLY; then
    if [ -n "$PROJECT_DIR" ]; then
        install_project "$PROJECT_DIR"
    else
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "  Project Setup"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        read -p "Install project settings to a directory? [y/N] " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            read -p "Project directory path: " PROJECT_DIR
            if [ -n "$PROJECT_DIR" ]; then
                # Expand ~ if present
                PROJECT_DIR="${PROJECT_DIR/#\~/$HOME}"
                install_project "$PROJECT_DIR"
            fi
        fi
    fi
fi

# Summary
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Installation Complete"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  Global settings: ~/.claude/rules/ + ~/.claude/skills/"
if [ -n "$PROJECT_DIR" ]; then
    echo "  Project settings: ${PROJECT_DIR}/.claude/"
fi
echo ""
echo "  Next steps:"
echo "  1. Edit CLAUDE.md to match your project"
echo "  2. Customize rules in ~/.claude/rules/ (language, etc.)"
echo "  3. Add project-specific skills as needed"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
