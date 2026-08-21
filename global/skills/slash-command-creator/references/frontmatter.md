# Slash Command Frontmatter Reference

## Required Fields

### `description`
Brief description of what the command does. Shown in `/help` output.

**Important**: Commands without `description` will NOT be available via the `SlashCommand` tool for programmatic invocation.

```yaml
description: Create a git commit with staged changes
```

## Optional Fields

### `allowed-tools`
Specifies which tools the command can use. Format: `ToolName(pattern:*)` or just `ToolName`.

```yaml
# Single tool
allowed-tools: Bash(git status:*)

# Multiple tools
allowed-tools: Bash(git add:*), Bash(git status:*), Bash(git commit:*)

# Tool without pattern
allowed-tools: Read, Write, Edit
```

Common tool patterns:
- `Bash(command:*)` - Allow specific bash commands
- `Read` - File reading
- `Write` - File writing
- `Edit` - File editing
- `Grep` - Content search
- `Glob` - File pattern matching

### `argument-hint`
Shows expected arguments when auto-completing the command.

```yaml
# Single argument
argument-hint: [message]

# Multiple arguments
argument-hint: [pr-number] [priority] [assignee]

# Alternative syntax
argument-hint: add [tagId] | remove [tagId] | list
```

### `model`
Specific model to use for this command. Accepts model aliases or full model IDs.

```yaml
# Model aliases
model: haiku
model: sonnet
model: opus

# Full model ID
model: claude-haiku-4-5-20251001
```

### `disable-model-invocation`
Prevents the `SlashCommand` tool from calling this command programmatically. When `true`, the command's metadata is also removed from Claude's context (saving tokens).

```yaml
disable-model-invocation: true
```

**Use for**: Commands that should only be invoked explicitly by the user (e.g., destructive operations, admin commands).

## `SLASH_COMMAND_TOOL_CHAR_BUDGET` Environment Variable

The `SlashCommand` tool includes a character budget to limit how many command descriptions are loaded into context.

- **Default limit**: 15,000 characters
- **Custom limit**: Set via `SLASH_COMMAND_TOOL_CHAR_BUDGET` environment variable

```bash
# Increase budget for projects with many commands
export SLASH_COMMAND_TOOL_CHAR_BUDGET=25000
```

When the budget is exceeded, Claude sees only a subset of available commands. Use `/context` to check - a warning will show "M of N commands" when truncated.

**Tips to stay within budget**:
- Keep descriptions concise (1 sentence)
- Use `disable-model-invocation: true` on commands that don't need programmatic access
- Prioritize frequently-used commands with shorter descriptions

## Complete Frontmatter Example

```yaml
---
allowed-tools: Bash(git add:*), Bash(git status:*), Bash(git commit:*)
argument-hint: [message]
description: Create a git commit with staged changes
model: haiku
---
```

## Advanced: Positional Arguments

```yaml
---
argument-hint: [pr-number] [priority] [assignee]
description: Review pull request
---

Review PR #$1 with priority $2 and assign to $3.
Focus on security, performance, and code style.
```

Access arguments: `$ARGUMENTS` (all), `$1`, `$2`, `$3` (positional).
