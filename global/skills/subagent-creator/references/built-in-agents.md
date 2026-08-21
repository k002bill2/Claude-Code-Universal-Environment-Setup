# Built-in Sub-agents

Claude Code includes three built-in sub-agents available out of the box.

## General-purpose Agent

A capable agent for complex, multi-step tasks requiring both exploration and action.

| Property | Value |
|----------|-------|
| **Model** | Sonnet |
| **Tools** | All tools (read + write + execute) |
| **Mode** | Full access - can modify files, execute commands |

### When Used

- Task requires both exploration and modification
- Complex reasoning needed to interpret search results
- Multiple strategies may be needed if initial approaches fail
- Multi-step tasks with dependencies between steps

### Example

```
User: Find all authentication handlers and update them to use the new token format

Claude → [Invokes general-purpose agent]
  → Searches for auth-related code across codebase
  → Reads and analyzes multiple files
  → Makes necessary edits
  → Returns detailed writeup of changes made
```

## Plan Agent

Specialized for research during plan mode. Used automatically when Claude is in plan mode and needs to explore the codebase.

| Property | Value |
|----------|-------|
| **Model** | Sonnet |
| **Tools** | Read, Glob, Grep, Bash (read-only exploration) |
| **Mode** | Read-only - cannot modify files |

### When Used

- Claude is in plan mode (via `EnterPlanMode`)
- Needs to understand codebase before creating a plan
- Gathers context for architectural decisions

### How It Works

1. User enters plan mode or Claude auto-enters for complex tasks
2. Claude needs to research the codebase
3. Plan agent is delegated to explore files, grep for patterns, read code
4. Returns findings to Claude for plan formulation
5. Prevents infinite nesting (subagents cannot spawn other subagents)

### Example

```
User: [In plan mode] Help me refactor the authentication module

Claude → Let me research your authentication implementation first...
  → [Invokes Plan agent to explore auth-related files]
  → [Plan agent searches codebase and returns findings]
Claude → Based on my research, here's my proposed plan...
```

## Explore Agent

Fast, lightweight agent optimized for searching and analyzing codebases. Strictly read-only.

| Property | Value |
|----------|-------|
| **Model** | Haiku (fast, low-latency) |
| **Tools** | Glob, Grep, Read, Bash (read-only only) |
| **Mode** | Strictly read-only |

### Available Bash Commands (Read-only)

`ls`, `git status`, `git log`, `git diff`, `find`, `cat`, `head`, `tail`

### Thoroughness Levels

| Level | Description | Use When |
|-------|-------------|----------|
| **Quick** | Basic searches, fastest results | Simple lookups, known patterns |
| **Medium** | Moderate exploration, balanced | General code discovery |
| **Very thorough** | Comprehensive analysis, multiple locations | Target in unexpected places |

### When Used

- Need to search/understand code without making changes
- More efficient than main agent running multiple search commands
- Content found during exploration doesn't bloat main conversation

### Example

```
User: Where are errors from the client handled?

Claude → [Invokes Explore agent with "medium" thoroughness]
  → Uses Grep to search for error handling patterns
  → Uses Read to examine promising files
  → Returns findings with absolute file paths
Claude → Client errors are handled in src/services/process.ts:712...
```

## Comparison

| Aspect | General-purpose | Plan | Explore |
|--------|----------------|------|---------|
| **Model** | Sonnet | Sonnet | Haiku |
| **Can modify files** | Yes | No | No |
| **Speed** | Medium | Medium | Fast |
| **Context isolation** | Yes | Yes | Yes |
| **Auto-invocation** | Task matching | Plan mode only | Search tasks |
| **Best for** | Complex tasks | Pre-planning research | Quick searches |
