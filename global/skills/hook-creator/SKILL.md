---
name: hook-creator
description: Create and configure Claude Code hooks for customizing agent behavior. Use when the user wants to (1) create a new hook, (2) configure automatic formatting, logging, or notifications, (3) add file protection or custom permissions, (4) set up pre/post tool execution actions, or (5) asks about hook events like PreToolUse, PostToolUse, Notification, etc.
---

# Hook Creator

Create Claude Code hooks that execute shell commands at specific lifecycle events.

## Hook Configuration Structure

```json
{
  "hooks": {
    "<EventName>": [
      {
        "matcher": "<ToolPattern>",
        "hooks": [
          {
            "type": "command",
            "command": "<shell-command>"
          }
        ]
      }
    ]
  }
}
```

## Available Events

| Event | When | Input |
|-------|------|-------|
| `PreToolUse` | Before tool execution | tool_input |
| `PostToolUse` | After tool execution | tool_input, tool_result |
| `Notification` | On notification | message |
| `UserPromptSubmit` | User sends message | user_prompt |
| `SessionStart` | Session begins | - |
| `SessionEnd` | Session ends | session_data |
| `Stop` | Agent stops | session_data |
| `SubagentStart` | Subagent spawns | agent_data |
| `SubagentStop` | Subagent finishes | agent_data |
| `PreCompact` | Before compaction | - |

## Exit Codes for PreToolUse

- `0` - Allow the tool to proceed
- `2` - Block the tool and provide feedback

## Matcher Patterns

- `*` - Match all tools
- `Bash` - Match only Bash
- `Edit|Write` - Match Edit or Write
- `Read` - Match Read

## Quick Examples

**Auto-format TypeScript after edit:**
```bash
jq -r '.tool_input.file_path' | { read f; [[ "$f" == *.ts ]] && npx prettier --write "$f"; }
```

**Block edits to .env files:**
```bash
python3 -c "import json,sys; p=json.load(sys.stdin).get('tool_input',{}).get('file_path',''); sys.exit(2 if '.env' in p else 0)"
```

**macOS notification on completion:**
```bash
osascript -e 'display notification "Task completed" with title "Claude Code"'
```

## Storage Locations

- **Project**: `.claude/hooks.json`
- **User**: `~/.claude/settings.json` (hooks section)
