#!/bin/bash
# Post-Edit Check Hook
# Runs after file edits to provide quick feedback
#
# Usage: Called automatically by .claudecode.json PostToolUse hook
# Environment: $CLAUDE_FILE contains the edited file path

FILE="${CLAUDE_FILE:-}"

if [ -z "$FILE" ]; then
  exit 0
fi

EXTENSION="${FILE##*.}"

case "$EXTENSION" in
  ts|tsx)
    # Quick TypeScript check (non-blocking)
    if command -v npx &>/dev/null; then
      echo "[Check] TypeScript file modified: ${FILE}"
    fi
    ;;
  py)
    # Quick Python check
    if command -v python3 &>/dev/null; then
      echo "[Check] Python file modified: ${FILE}"
    fi
    ;;
  *)
    # No specific check for this file type
    ;;
esac
