# SlashCommand Tool Reference

The `SlashCommand` tool allows Claude to execute custom slash commands programmatically during a conversation - without user explicitly typing the command.

## How It Works

1. Claude sees all available command metadata (name, args, description) in its context
2. When a task matches a command's purpose, Claude invokes it via the `SlashCommand` tool
3. The command runs with the same permissions as if the user typed it

## Requirements for Commands

A command must meet **all** of these criteria to be available via `SlashCommand`:

- **User-defined** (not built-in). Built-in commands like `/compact`, `/init` are NOT supported.
- **Has `description` frontmatter field**. The description is used for context matching.
- **Not disabled**: `disable-model-invocation` must be `false` (default) or absent.

## Triggering SlashCommand

To encourage Claude to use a specific command, reference it by name in your instructions:

```markdown
# In CLAUDE.md or system prompt:
Run /verify-app after implementing any feature.
Use /commit-push-pr when code changes are ready.
Always run /check-health before creating a PR.
```

## Permission Rules

Configure which commands Claude can invoke programmatically:

```
# In permissions configuration:

# Allow specific command (no arguments)
SlashCommand:/commit

# Allow command with any arguments (prefix match)
SlashCommand:/review-pr:*

# Allow all slash commands
SlashCommand

# Deny all slash commands
# Add "SlashCommand" to deny rules
```

### Permission Patterns

| Pattern | Matches | Example |
|---------|---------|---------|
| `SlashCommand:/commit` | Exact match, no args | `/commit` only |
| `SlashCommand:/review-pr:*` | Prefix match with args | `/review-pr 123`, `/review-pr 456 high` |
| `SlashCommand` | All custom commands | Any custom command |

## Disabling SlashCommand Tool

### Globally (remove from context)

```bash
/permissions
# Add to deny rules: SlashCommand
```

This removes both the tool and all command descriptions from context.

### Per-command

Add to the command's frontmatter:

```yaml
---
disable-model-invocation: true
description: Dangerous admin operation
---
```

This removes only this command's metadata from context.

## Character Budget

Command metadata consumes context tokens. The budget controls how many commands fit:

- **Default**: 15,000 characters
- **Custom**: `SLASH_COMMAND_TOOL_CHAR_BUDGET` environment variable

Budget includes each command's: name + argument hint + description.

### Debugging

```bash
# See which commands are loaded
claude --debug

# Check context usage
/context
```

When budget is exceeded, `/context` shows "M of N commands" warning.

## AOS Project Example

```markdown
# CLAUDE.md instruction:
Run /verify-app after implementing features.
Use /commit-push-pr when changes are ready for review.
Run /check-health as a pre-PR validation step.
```

This causes Claude to automatically invoke these commands at appropriate points in the workflow.
