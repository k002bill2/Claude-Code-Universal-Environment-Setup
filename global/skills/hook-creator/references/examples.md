# Hook Examples

Complete, tested hook configurations for common use cases.

## Logging Hooks

### Log All Bash Commands

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "jq -r '\"\\(.tool_input.command) - \\(.tool_input.description // \"No description\")\"' >> ~/.claude/bash-command-log.txt"
          }
        ]
      }
    ]
  }
}
```

### Log All File Edits

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "jq -r '\"[\\(now | strftime(\"%Y-%m-%d %H:%M:%S\"))] \\(.tool_name): \\(.tool_input.file_path)\"' >> ~/.claude/edit-log.txt"
          }
        ]
      }
    ]
  }
}
```

## Auto-Formatting Hooks

### Format TypeScript/React Files (AOS Dashboard)

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "jq -r '.tool_input.file_path' | { read file_path; if echo \"$file_path\" | grep -qE '\\.(ts|tsx)$'; then npx prettier --write \"$file_path\" 2>/dev/null; fi; }"
          }
        ]
      }
    ]
  }
}
```

### Format Python Files with Ruff (AOS Backend)

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "jq -r '.tool_input.file_path' | { read f; [[ \"$f\" == *.py ]] && ruff format \"$f\" && ruff check --fix \"$f\" 2>/dev/null; exit 0; }"
          }
        ]
      }
    ]
  }
}
```

### Format Go Files

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "jq -r '.tool_input.file_path' | { read f; [[ \"$f\" == *.go ]] && gofmt -w \"$f\"; }"
          }
        ]
      }
    ]
  }
}
```

## Markdown Formatter Hook (Python Script)

Auto-fix markdown formatting issues using an external Python script:

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/markdown_formatter.py"
          }
        ]
      }
    ]
  }
}
```

Create `.claude/hooks/markdown_formatter.py`:

```python
#!/usr/bin/env python3
"""Markdown formatter - fixes missing language tags and spacing issues."""
import json
import sys
import re
import os

def detect_language(code):
    """Best-effort language detection from code content."""
    s = code.strip()

    if re.search(r'^\s*[{\[]', s):
        try:
            json.loads(s)
            return 'json'
        except:
            pass

    if re.search(r'^\s*def\s+\w+\s*\(', s, re.M) or \
       re.search(r'^\s*(import|from)\s+\w+', s, re.M):
        return 'python'

    if re.search(r'\b(function\s+\w+\s*\(|const\s+\w+\s*=)', s) or \
       re.search(r'=>|console\.(log|error)', s):
        return 'javascript'

    if re.search(r'^#!.*\b(bash|sh)\b', s, re.M):
        return 'bash'

    if re.search(r'\b(SELECT|INSERT|UPDATE|DELETE|CREATE)\s+', s, re.I):
        return 'sql'

    return 'text'

def format_markdown(content):
    def add_lang_to_fence(match):
        indent, info, body, closing = match.groups()
        if not info.strip():
            lang = detect_language(body)
            return f"{indent}```{lang}\n{body}{closing}\n"
        return match.group(0)

    fence_pattern = r'(?ms)^([ \t]{0,3})```([^\n]*)\n(.*?)(\n\1```)\s*$'
    content = re.sub(fence_pattern, add_lang_to_fence, content)
    content = re.sub(r'\n{3,}', '\n\n', content)
    return content.rstrip() + '\n'

try:
    input_data = json.load(sys.stdin)
    file_path = input_data.get('tool_input', {}).get('file_path', '')

    if not file_path.endswith(('.md', '.mdx')):
        sys.exit(0)

    if os.path.exists(file_path):
        with open(file_path, 'r', encoding='utf-8') as f:
            content = f.read()

        formatted = format_markdown(content)

        if formatted != content:
            with open(file_path, 'w', encoding='utf-8') as f:
                f.write(formatted)
            print(f"Fixed markdown formatting in {file_path}")

except Exception as e:
    print(f"Error formatting markdown: {e}", file=sys.stderr)
    sys.exit(1)
```

Make the script executable: `chmod +x .claude/hooks/markdown_formatter.py`

## File Protection Hooks

### Block Edits to Sensitive Files

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "python3 -c \"import json, sys; data=json.load(sys.stdin); path=data.get('tool_input',{}).get('file_path',''); blocked=['.env', 'package-lock.json', '.git/', 'secrets']; sys.exit(2 if any(p in path for p in blocked) else 0)\""
          }
        ]
      }
    ]
  }
}
```

### Block Modifications to Production Directory

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Edit|Write|Bash",
        "hooks": [
          {
            "type": "command",
            "command": "jq -r '.tool_input | .file_path // .command // \"\"' | grep -q '/prod/' && echo 'BLOCKED: Cannot modify production files' && exit 2 || exit 0"
          }
        ]
      }
    ]
  }
}
```

### AOS: Protect Infrastructure Files

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "python3 -c \"import json, sys; data=json.load(sys.stdin); path=data.get('tool_input',{}).get('file_path',''); protected=['docker-compose.yml', 'alembic.ini', '.github/workflows']; sys.exit(2 if any(p in path for p in protected) else 0)\""
          }
        ]
      }
    ]
  }
}
```

## Notification Hooks

### macOS Desktop Notification

```json
{
  "hooks": {
    "Notification": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "jq -r '.message' | xargs -I{} osascript -e 'display notification \"{}\" with title \"Claude Code\"'"
          }
        ]
      }
    ]
  }
}
```

### Linux Desktop Notification

```json
{
  "hooks": {
    "Notification": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "jq -r '.message' | xargs -I{} notify-send 'Claude Code' '{}'"
          }
        ]
      }
    ]
  }
}
```

### Sound Notification (macOS)

```json
{
  "hooks": {
    "Notification": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "afplay /System/Library/Sounds/Glass.aiff"
          }
        ]
      }
    ]
  }
}
```

## Validation Hooks

### Validate JSON Before Write

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Write",
        "hooks": [
          {
            "type": "command",
            "command": "jq -e '.tool_input | select(.file_path | endswith(\".json\")) | .content' | jq . > /dev/null 2>&1 || { echo 'Invalid JSON content'; exit 2; }"
          }
        ]
      }
    ]
  }
}
```

### Lint TypeScript Before Commit

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "jq -r '.tool_input.command' | grep -q 'git commit' && npx eslint . --max-warnings 0 || exit 0"
          }
        ]
      }
    ]
  }
}
```

## Permission Hooks

### Auto-approve Git Read Commands

```json
{
  "hooks": {
    "PermissionRequest": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "jq -r '.tool_input.command' | grep -qE '^git (status|log|diff|branch|show)' && exit 2 || exit 0"
          }
        ]
      }
    ]
  }
}
```

### Auto-deny Dangerous Commands

```json
{
  "hooks": {
    "PermissionRequest": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "jq -r '.tool_input.command' | grep -qE '(rm -rf|drop table|force push|--no-verify)' && echo 'DENIED: Dangerous command' && exit 1 || exit 0"
          }
        ]
      }
    ]
  }
}
```

## Session Hooks

### Initialize Environment on Session Start

```json
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "[ -f .claude-env ] && source .claude-env; exit 0"
          }
        ]
      }
    ]
  }
}
```

### Cleanup on Session End

```json
{
  "hooks": {
    "SessionEnd": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "rm -f /tmp/claude-session-* 2>/dev/null; exit 0"
          }
        ]
      }
    ]
  }
}
```

### Save Context Before Compact

```json
{
  "hooks": {
    "PreCompact": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "echo \"[$(date)] Compact triggered\" >> ~/.claude/compact-log.txt"
          }
        ]
      }
    ]
  }
}
```

## Combined Configuration Example

Multiple hooks working together (AOS project example):

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "python3 -c \"import json,sys; p=json.load(sys.stdin).get('tool_input',{}).get('file_path',''); sys.exit(2 if '.env' in p else 0)\""
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "jq -r '.tool_input.file_path' | { read f; [[ \"$f\" == *.py ]] && ruff format \"$f\" 2>/dev/null; [[ \"$f\" == *.ts || \"$f\" == *.tsx ]] && npx prettier --write \"$f\" 2>/dev/null; exit 0; }"
          }
        ]
      }
    ],
    "Notification": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "afplay /System/Library/Sounds/Glass.aiff"
          }
        ]
      }
    ],
    "SessionStart": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "echo 'Session started at '$(date) >> ~/.claude/session-log.txt"
          }
        ]
      }
    ]
  }
}
```
