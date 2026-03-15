---
name: subagent-creator
description: Create specialized Claude Code sub-agents with custom system prompts and tool configurations. Use when users ask to create a new sub-agent, custom agent, specialized assistant, or want to configure task-specific AI workflows for Claude Code.
---

# Sub-agent Creator

Create specialized AI sub-agents for Claude Code that handle specific tasks with customized prompts and tool access.

## Sub-agent File Format

Sub-agents are Markdown files with YAML frontmatter stored in:
- **Project**: `.claude/agents/` (highest priority)
- **User**: `~/.claude/agents/` (lowest priority)

### Structure

```markdown
---
name: subagent-name
description: When to use this subagent (include "use proactively" for auto-delegation)
tools: Tool1, Tool2, Tool3  # Optional - inherits all if omitted
model: sonnet               # Optional - sonnet/opus/haiku/inherit
permissionMode: default     # Optional
skills: skill1, skill2      # Optional - auto-load skills
---

System prompt goes here. Define role, responsibilities, and behavior.
```

### Configuration Fields

| Field | Required | Description |
|-------|----------|-------------|
| `name` | Yes | Lowercase with hyphens |
| `description` | Yes | Purpose and when to use |
| `tools` | No | Comma-separated tool list |
| `model` | No | `sonnet`, `opus`, `haiku`, or `inherit` |
| `permissionMode` | No | `default`, `acceptEdits`, `bypassPermissions`, `plan`, `ignore` |
| `skills` | No | Comma-separated skill names |

## Creation Workflow

1. **Gather requirements**: Ask about the sub-agent's purpose
2. **Choose scope**: Project or user level
3. **Define configuration**: Name, description, tools, model
4. **Write system prompt**: Clear role, responsibilities, output format
5. **Create file**: Write the `.md` file

## Writing Effective Sub-agents

### Description Best Practices

```yaml
# Good - specific triggers
description: Expert code reviewer. Use PROACTIVELY after writing or modifying code.

# Bad - too vague
description: Helps with code
```

### System Prompt Guidelines

1. Define role clearly: "You are a [specific expert role]"
2. List actions on invocation
3. Specify responsibilities
4. Include constraints and best practices
5. Define output format
