---
name: slash-command-creator
description: Guide for creating Claude Code slash commands. Use when the user wants to create a new slash command, update an existing slash command, or asks about slash command syntax, frontmatter options, or best practices.
---

# Slash Command Creator

Create custom slash commands for Claude Code to automate frequently-used prompts.

## Command Structure

Slash commands are Markdown files with optional YAML frontmatter:

```markdown
---
description: Brief description shown in /help
---

Your prompt instructions here.

$ARGUMENTS
```

### File Locations

| Scope | Path | Shown as |
|-------|------|----------|
| Project | `.claude/commands/` | (project) |
| Personal | `~/.claude/commands/` | (user) |

### Namespacing

Organize commands in subdirectories:
- `.claude/commands/frontend/component.md` -> `/component` shows "(project:frontend)"

## Features

### Arguments

- **All arguments**: `$ARGUMENTS`
- **Positional**: `$1`, `$2`, etc.

### Bash Execution

Execute shell commands with `!` prefix (requires `allowed-tools` in frontmatter):

```markdown
---
allowed-tools: Bash(git status:*), Bash(git diff:*)
---

Current status: !`git status`
```

### File References

Include file contents with `@` prefix:
```markdown
Review @src/utils/helpers.js for issues.
```

## Frontmatter Options

| Field | Purpose | Required |
|-------|---------|----------|
| `description` | Brief description for /help | Yes |
| `allowed-tools` | Tools the command can use | No |
| `argument-hint` | Expected arguments hint | No |
| `model` | Specific model to use | No |
