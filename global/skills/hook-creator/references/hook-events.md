# Hook Events Reference

## Event Overview

| Event | Trigger | Can Block | Typical Use |
|-------|---------|-----------|-------------|
| PreToolUse | Before tool execution | Yes (exit 2) | Validation, blocking |
| PostToolUse | After tool completion | No | Formatting, logging |
| PostToolUseFailure | After tool fails | No | Error handling |
| PermissionRequest | Permission dialog shown | Yes (exit 1/2) | Auto-allow/deny |
| UserPromptSubmit | User submits prompt | No | Pre-processing |
| Notification | Claude sends notification | No | Custom alerts |
| Stop | Claude finishes responding | No | Post-processing |
| SubagentStop | Subagent task completes | No | Subagent cleanup |
| SubagentStart | Subagent task starts | No | Subagent init |
| PreCompact | Before compact operation | No | Pre-compact save |
| SessionStart | Session starts/resumes | No | Initialization |
| SessionEnd | Session ends | No | Cleanup |
| Setup | First-time setup | No | Environment init |

## Hook Configuration

Hooks are stored in `settings.json` (user-level) or `.claude/settings.json` (project-level):

```json
{
  "hooks": {
    "<EventName>": [
      {
        "matcher": "ToolName|OtherTool",
        "hooks": [
          {
            "type": "command",
            "command": "your-shell-command"
          }
        ]
      }
    ]
  }
}
```

**Matcher**: Pipe-separated tool names (e.g., `Edit|Write`). Use `*` for all tools. Empty string `""` for events without tool context (Notification, Stop, etc.).

**Environment Variables available in hooks**:
- `$CLAUDE_PROJECT_DIR` - Project root directory
- Stdin receives JSON with event-specific data

## PreToolUse

Runs before tool calls. **Can block execution.**

**Input Schema (stdin):**
```json
{
  "tool_name": "Bash",
  "tool_input": {
    "command": "ls -la",
    "description": "List files"
  }
}
```

**Exit Codes:**
- `0` - Allow tool to proceed
- `2` - Block tool, stdout sent as feedback to Claude

**Common tool_input fields by tool:**
- `Bash`: `command`, `description`
- `Edit`: `file_path`, `old_string`, `new_string`
- `Write`: `file_path`, `content`
- `Read`: `file_path`
- `Glob`: `pattern`, `path`
- `Grep`: `pattern`, `path`

## PostToolUse

Runs after tool calls complete successfully.

**Input Schema (stdin):**
```json
{
  "tool_name": "Edit",
  "tool_input": {
    "file_path": "/path/to/file.ts"
  },
  "tool_response": "File edited successfully"
}
```

**Use Cases:**
- Auto-formatting edited files (ruff for `.py`, prettier for `.ts/.tsx`)
- Logging tool results
- Triggering dependent actions (build checks, lint)

## PostToolUseFailure

Runs after a tool call fails. Same input schema as PostToolUse but `tool_response` contains the error.

**Use Cases:**
- Error logging and alerting
- Cleanup after failed operations
- Retry logic coordination

## PermissionRequest

Runs when a permission dialog is about to be shown to the user.

**Input Schema (stdin):**
```json
{
  "tool_name": "Bash",
  "tool_input": {
    "command": "npm install"
  }
}
```

**Exit Codes:**
- `0` - Let user decide (show dialog)
- `1` - Auto-deny the permission
- `2` - Auto-approve the permission

**Use Cases:**
- Auto-approve known safe commands
- Auto-deny dangerous operations
- Policy-based permission management

## Notification

Runs when Claude sends notifications (e.g., waiting for input).

**Input Schema (stdin):**
```json
{
  "message": "Waiting for your input",
  "type": "input_required"
}
```

**Use Cases:**
- Custom desktop notifications (macOS `osascript`, Linux `notify-send`)
- Slack/Discord webhook alerts
- Sound notifications

## UserPromptSubmit

Runs when user submits a prompt, before Claude processes it.

**Input Schema (stdin):**
```json
{
  "prompt": "Help me fix this bug",
  "session_id": "abc123"
}
```

**Use Cases:**
- Prompt logging and analytics
- Context injection (append project state)
- Complexity analysis and routing

## Stop

Runs when Claude finishes responding.

**Input Schema (stdin):**
```json
{
  "stop_reason": "end_turn",
  "session_id": "abc123"
}
```

**Use Cases:**
- Session logging and metrics
- Trigger post-completion validation (auto-test execution)
- Cleanup tasks

## SubagentStart

Runs when a subagent task starts.

**Input Schema (stdin):**
```json
{
  "subagent_type": "general-purpose",
  "description": "Research authentication patterns"
}
```

## SubagentStop

Runs when subagent (Agent tool) tasks complete.

**Input Schema (stdin):**
```json
{
  "subagent_type": "Explore",
  "result": "Found 5 matching files"
}
```

## PreCompact

Runs before Claude compacts conversation context.

**Input Schema (stdin):**
```json
{
  "reason": "context_limit",
  "current_tokens": 50000
}
```

**Use Cases:**
- Save current context to dev-docs before compaction
- Log conversation state

## SessionStart

Runs when Claude Code starts a new session or resumes an existing session.

**Input Schema (stdin):**
```json
{
  "session_id": "abc123",
  "is_resume": false,
  "project_dir": "/path/to/project"
}
```

**Use Cases:**
- Environment setup and validation
- Display previous review results
- Loading project configuration
- Starting background services

## SessionEnd

Runs when Claude Code session ends.

**Input Schema (stdin):**
```json
{
  "session_id": "abc123",
  "end_reason": "user_exit"
}
```

**Use Cases:**
- Cleanup temp files and resources
- Save session state
- Stop background services

## Setup

Runs during first-time setup of Claude Code.

**Use Cases:**
- Initial environment configuration
- Dependency verification
- Welcome message or onboarding
