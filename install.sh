#!/bin/bash
# ============================================================
# Claude Code Universal Environment Setup
# ============================================================
# Version: 1.0.0
# Description: 범용 Claude Code 개발 환경 구축 설치 스크립트
# Usage: bash install.sh [target-directory]
# ============================================================

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Script directory (where templates live)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATES_DIR="${SCRIPT_DIR}/templates"

# ============================================================
# Helper Functions
# ============================================================

print_header() {
  echo ""
  echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${BOLD}  Claude Code Universal Environment Setup${NC}"
  echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""
}

print_step() {
  echo -e "${GREEN}[${1}]${NC} ${2}"
}

print_warn() {
  echo -e "${YELLOW}[WARN]${NC} ${1}"
}

print_error() {
  echo -e "${RED}[ERROR]${NC} ${1}"
}

print_info() {
  echo -e "${BLUE}[INFO]${NC} ${1}"
}

confirm() {
  local prompt="${1:-Continue?}"
  echo -en "${YELLOW}${prompt} [y/N]: ${NC}"
  read -r answer
  [[ "$answer" =~ ^[Yy]$ ]]
}

# ============================================================
# Pre-flight Checks
# ============================================================

preflight_check() {
  print_step "0/7" "Pre-flight checks..."

  # Check Node.js
  if ! command -v node &>/dev/null; then
    print_error "Node.js not found. Install Node.js v18+ first."
    print_info "  brew install node  OR  https://nodejs.org"
    exit 1
  fi

  local node_version
  node_version=$(node -v | sed 's/v//' | cut -d. -f1)
  if [ "$node_version" -lt 18 ]; then
    print_error "Node.js v18+ required. Current: $(node -v)"
    exit 1
  fi
  print_info "Node.js $(node -v) OK"

  # Check Git
  if ! command -v git &>/dev/null; then
    print_error "Git not found. Install Git first."
    exit 1
  fi
  print_info "Git $(git --version | awk '{print $3}') OK"

  # Check Claude Code CLI (optional)
  if command -v claude &>/dev/null; then
    print_info "Claude Code CLI found: $(claude --version 2>/dev/null || echo 'installed')"
  else
    print_warn "Claude Code CLI not found. Install with: npm install -g @anthropic-ai/claude-code"
  fi

  echo ""
}

# ============================================================
# Target Directory Setup
# ============================================================

setup_target() {
  local target="${1:-}"

  if [ -z "$target" ]; then
    echo -en "${CYAN}Target project directory (default: current dir): ${NC}"
    read -r target
    target="${target:-.}"
  fi

  # Resolve to absolute path
  TARGET_DIR="$(cd "$target" 2>/dev/null && pwd || echo "$target")"

  if [ ! -d "$TARGET_DIR" ]; then
    if confirm "Directory $TARGET_DIR does not exist. Create it?"; then
      mkdir -p "$TARGET_DIR"
    else
      print_error "Aborted."
      exit 1
    fi
  fi

  print_info "Target: ${TARGET_DIR}"
  echo ""
}

# ============================================================
# Project Type Selection
# ============================================================

select_project_type() {
  echo -e "${BOLD}Select project type:${NC}"
  echo "  1) Web Frontend (React/Next.js/Vue)"
  echo "  2) Backend API (Node.js/Python/Go)"
  echo "  3) Full-Stack (Frontend + Backend)"
  echo "  4) Data/ML (Python)"
  echo "  5) Mobile (React Native/Flutter)"
  echo "  6) DevOps/Infrastructure"
  echo "  7) Custom (minimal setup)"
  echo ""
  echo -en "${CYAN}Choice [1-7] (default: 3): ${NC}"
  read -r choice
  PROJECT_TYPE="${choice:-3}"

  case "$PROJECT_TYPE" in
    1) PROJECT_TYPE_NAME="web-frontend" ;;
    2) PROJECT_TYPE_NAME="backend-api" ;;
    3) PROJECT_TYPE_NAME="full-stack" ;;
    4) PROJECT_TYPE_NAME="data-ml" ;;
    5) PROJECT_TYPE_NAME="mobile" ;;
    6) PROJECT_TYPE_NAME="devops" ;;
    7) PROJECT_TYPE_NAME="custom" ;;
    *) PROJECT_TYPE_NAME="full-stack" ;;
  esac

  print_info "Project type: ${PROJECT_TYPE_NAME}"
  echo ""
}

# ============================================================
# Feature Selection
# ============================================================

select_features() {
  echo -e "${BOLD}Select features to install:${NC}"
  echo ""

  INSTALL_SKILLS=true
  INSTALL_AGENTS=true
  INSTALL_COMMANDS=true
  INSTALL_HOOKS=true
  INSTALL_DEVDOCS=true
  INSTALL_SKILL_ACTIVATION=true
  INSTALL_MCP=true
  INSTALL_PARALLEL_PROTOCOL=false

  if confirm "Install common Skills? (code-reviewer, test-runner, docs-generator)"; then
    INSTALL_SKILLS=true
  else
    INSTALL_SKILLS=false
  fi

  if confirm "Install Sub-agents? (frontend/backend/test specialists)"; then
    INSTALL_AGENTS=true
  else
    INSTALL_AGENTS=false
  fi

  if confirm "Install custom Commands? (dev-docs, verify, review)"; then
    INSTALL_COMMANDS=true
  else
    INSTALL_COMMANDS=false
  fi

  if confirm "Install Hook system? (auto-formatting, skill activation)"; then
    INSTALL_HOOKS=true
  else
    INSTALL_HOOKS=false
  fi

  if confirm "Install Dev Docs system? (3-file context management)"; then
    INSTALL_DEVDOCS=true
  else
    INSTALL_DEVDOCS=false
  fi

  if confirm "Install Skills auto-activation system? (Hook-based enforcement)"; then
    INSTALL_SKILL_ACTIVATION=true
  else
    INSTALL_SKILL_ACTIVATION=false
  fi

  if confirm "Install MCP server configuration?"; then
    INSTALL_MCP=true
  else
    INSTALL_MCP=false
  fi

  if confirm "Install Parallel Agents Protocol? (multi-agent coordination)"; then
    INSTALL_PARALLEL_PROTOCOL=true
  else
    INSTALL_PARALLEL_PROTOCOL=false
  fi

  echo ""
}

# ============================================================
# Directory Structure Creation
# ============================================================

create_directories() {
  print_step "1/7" "Creating directory structure..."

  local dirs=(
    ".claude"
    ".claude/skills"
    ".claude/agents"
    ".claude/agents/shared"
    ".claude/commands"
  )

  if [ "$INSTALL_HOOKS" = true ]; then
    dirs+=(".claude/hooks")
  fi

  if [ "$INSTALL_DEVDOCS" = true ]; then
    dirs+=("dev/active" "dev/completed")
  fi

  for dir in "${dirs[@]}"; do
    mkdir -p "${TARGET_DIR}/${dir}"
    print_info "  Created: ${dir}/"
  done

  echo ""
}

# ============================================================
# CLAUDE.md Generation
# ============================================================

generate_claude_md() {
  print_step "2/7" "Generating CLAUDE.md..."

  local claude_md="${TARGET_DIR}/CLAUDE.md"

  if [ -f "$claude_md" ]; then
    if ! confirm "CLAUDE.md already exists. Overwrite?"; then
      print_warn "Skipping CLAUDE.md generation."
      return
    fi
  fi

  # Get project info
  echo -en "${CYAN}Project name: ${NC}"
  read -r PROJECT_NAME
  PROJECT_NAME="${PROJECT_NAME:-My Project}"

  echo -en "${CYAN}Project purpose (one line): ${NC}"
  read -r PROJECT_PURPOSE
  PROJECT_PURPOSE="${PROJECT_PURPOSE:-A development project}"

  echo -en "${CYAN}Tech stack (comma separated): ${NC}"
  read -r TECH_STACK
  TECH_STACK="${TECH_STACK:-TypeScript, React, Node.js}"

  # Generate from template
  sed \
    -e "s|{{PROJECT_NAME}}|${PROJECT_NAME}|g" \
    -e "s|{{PROJECT_PURPOSE}}|${PROJECT_PURPOSE}|g" \
    -e "s|{{TECH_STACK}}|${TECH_STACK}|g" \
    -e "s|{{PROJECT_TYPE}}|${PROJECT_TYPE_NAME}|g" \
    "${TEMPLATES_DIR}/CLAUDE.md.template" > "$claude_md"

  print_info "  Generated: CLAUDE.md"
  echo ""
}

# ============================================================
# Configuration Files
# ============================================================

install_config_files() {
  print_step "3/7" "Installing configuration files..."

  # .claudecode.json
  if [ ! -f "${TARGET_DIR}/.claudecode.json" ]; then
    cp "${TEMPLATES_DIR}/claudecode.json" "${TARGET_DIR}/.claudecode.json"
    print_info "  Installed: .claudecode.json"
  else
    print_warn "  .claudecode.json already exists, skipping."
  fi

  # .mcp.json
  if [ "$INSTALL_MCP" = true ] && [ ! -f "${TARGET_DIR}/.mcp.json" ]; then
    cp "${TEMPLATES_DIR}/mcp.json" "${TARGET_DIR}/.mcp.json"
    print_info "  Installed: .mcp.json"
  fi

  # skill-rules.json
  if [ "$INSTALL_SKILL_ACTIVATION" = true ]; then
    cp "${TEMPLATES_DIR}/skill-rules.json" "${TARGET_DIR}/skill-rules.json"
    print_info "  Installed: skill-rules.json"
  fi

  echo ""
}

# ============================================================
# Skills Installation
# ============================================================

install_skills() {
  if [ "$INSTALL_SKILLS" = false ]; then return; fi

  print_step "4/7" "Installing Skills..."

  local skills_dir="${TARGET_DIR}/.claude/skills"

  # Code Reviewer
  mkdir -p "${skills_dir}/code-reviewer"
  cp "${TEMPLATES_DIR}/skills/code-reviewer/SKILL.md" "${skills_dir}/code-reviewer/SKILL.md"
  print_info "  Installed: code-reviewer skill"

  # Test Runner
  mkdir -p "${skills_dir}/test-runner"
  cp "${TEMPLATES_DIR}/skills/test-runner/SKILL.md" "${skills_dir}/test-runner/SKILL.md"
  print_info "  Installed: test-runner skill"

  # Docs Generator
  mkdir -p "${skills_dir}/docs-generator"
  cp "${TEMPLATES_DIR}/skills/docs-generator/SKILL.md" "${skills_dir}/docs-generator/SKILL.md"
  print_info "  Installed: docs-generator skill"

  echo ""
}

# ============================================================
# Agents Installation
# ============================================================

install_agents() {
  if [ "$INSTALL_AGENTS" = false ]; then return; fi

  print_step "5/7" "Installing Sub-agents..."

  local agents_dir="${TARGET_DIR}/.claude/agents"

  for agent_file in "${TEMPLATES_DIR}"/agents/*.md; do
    if [ -f "$agent_file" ]; then
      local basename
      basename=$(basename "$agent_file")
      cp "$agent_file" "${agents_dir}/${basename}"
      print_info "  Installed: ${basename}"
    fi
  done

  # Shared frameworks
  for shared_file in "${TEMPLATES_DIR}"/agents/shared/*.md; do
    if [ -f "$shared_file" ]; then
      local basename
      basename=$(basename "$shared_file")
      cp "$shared_file" "${agents_dir}/shared/${basename}"
      print_info "  Installed: shared/${basename}"
    fi
  done

  echo ""
}

# ============================================================
# Commands Installation
# ============================================================

install_commands() {
  if [ "$INSTALL_COMMANDS" = false ]; then return; fi

  print_step "6/7" "Installing Commands..."

  local commands_dir="${TARGET_DIR}/.claude/commands"

  for cmd_file in "${TEMPLATES_DIR}"/commands/*.md; do
    if [ -f "$cmd_file" ]; then
      local basename
      basename=$(basename "$cmd_file")
      cp "$cmd_file" "${commands_dir}/${basename}"
      print_info "  Installed: /${basename%.md}"
    fi
  done

  echo ""
}

# ============================================================
# Hooks & Parallel Protocol
# ============================================================

install_hooks_and_protocol() {
  print_step "7/7" "Installing Hooks & Protocols..."

  if [ "$INSTALL_HOOKS" = true ]; then
    local hooks_dir="${TARGET_DIR}/.claude/hooks"
    for hook_file in "${TEMPLATES_DIR}"/hooks/*; do
      if [ -f "$hook_file" ]; then
        local basename
        basename=$(basename "$hook_file")
        cp "$hook_file" "${hooks_dir}/${basename}"
        print_info "  Installed: hooks/${basename}"
      fi
    done
  fi

  if [ "$INSTALL_PARALLEL_PROTOCOL" = true ]; then
    cp "${TEMPLATES_DIR}/agents/shared/parallel-agents-protocol.md" \
       "${TARGET_DIR}/.claude/agents/shared/parallel-agents-protocol.md"
    print_info "  Installed: Parallel Agents Safety Protocol"
  fi

  echo ""
}

# ============================================================
# Post-install Summary
# ============================================================

print_summary() {
  echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${GREEN}${BOLD}  Setup Complete!${NC}"
  echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""
  echo -e "${BOLD}Installed structure:${NC}"
  echo ""

  # Show tree if available, fallback to find
  if command -v tree &>/dev/null; then
    tree -L 3 --dirsfirst "${TARGET_DIR}/.claude" 2>/dev/null || true
  else
    find "${TARGET_DIR}/.claude" -type f | sort | sed "s|${TARGET_DIR}/||"
  fi

  echo ""
  echo -e "${BOLD}Next steps:${NC}"
  echo -e "  1. ${CYAN}cd ${TARGET_DIR}${NC}"
  echo -e "  2. Review and customize ${CYAN}CLAUDE.md${NC}"
  echo -e "  3. Update ${CYAN}.claudecode.json${NC} permissions for your project"
  echo -e "  4. Customize ${CYAN}skill-rules.json${NC} trigger keywords"
  echo -e "  5. Run ${CYAN}claude${NC} to start coding!"
  echo ""
  echo -e "${BOLD}Key files:${NC}"
  echo -e "  ${CYAN}CLAUDE.md${NC}              - Project context (most important!)"
  echo -e "  ${CYAN}.claudecode.json${NC}       - Permissions & hooks config"
  echo -e "  ${CYAN}skill-rules.json${NC}       - Skills auto-activation rules"
  echo -e "  ${CYAN}.claude/skills/${NC}         - Agent Skills"
  echo -e "  ${CYAN}.claude/agents/${NC}         - Sub-agents"
  echo -e "  ${CYAN}.claude/commands/${NC}       - Custom slash commands"
  echo ""
  echo -e "${BOLD}Useful commands:${NC}"
  echo -e "  ${CYAN}/dev-docs${NC}              - Create Dev Docs for a task"
  echo -e "  ${CYAN}/update-dev-docs${NC}       - Update Dev Docs before compaction"
  echo -e "  ${CYAN}/verify${NC}                - Run type check + lint + test"
  echo -e "  ${CYAN}/review${NC}                - Code review with skill"
  echo ""
}

# ============================================================
# Main
# ============================================================

main() {
  print_header
  preflight_check
  setup_target "${1:-}"
  select_project_type
  select_features
  create_directories
  generate_claude_md
  install_config_files
  install_skills
  install_agents
  install_commands
  install_hooks_and_protocol
  print_summary
}

main "$@"
