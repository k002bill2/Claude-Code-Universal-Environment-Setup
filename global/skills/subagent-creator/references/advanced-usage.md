# Advanced Sub-agent Usage

## CLI `--agents` Flag

Define sub-agents dynamically via CLI without creating files:

```bash
claude --agents '{
  "code-reviewer": {
    "description": "Expert code reviewer. Use proactively after code changes.",
    "prompt": "You are a senior code reviewer. Focus on code quality, security, and best practices.",
    "tools": ["Read", "Grep", "Glob", "Bash"],
    "model": "sonnet"
  }
}'
```

**Priority order**: Project agents > CLI agents > User agents

**Use cases**:
- Quick testing of agent configurations
- Session-specific agents
- Automation scripts with custom agents
- Sharing agent definitions in documentation

## Resumable Agents

Agents can be resumed to continue previous conversations, preserving full context.

### How It Works

1. Each agent execution gets a unique `agentId`
2. The conversation is stored in a transcript file: `agent-{agentId}.jsonl`
3. Resume via the `resume` parameter with the `agentId`
4. Agent continues with full prior context

### Example Workflow

**Initial invocation:**
```
> Use the code-analyzer agent to start reviewing the authentication module

[Agent completes initial analysis and returns agentId: "abc123"]
```

**Resume the agent:**
```
> Resume agent abc123 and now analyze the authorization logic as well

[Agent continues with full context from previous conversation]
```

### Programmatic Usage (Agent SDK)

```typescript
{
  "description": "Continue analysis",
  "prompt": "Now examine the error handling patterns",
  "subagent_type": "code-analyzer",
  "resume": "abc123"  // Agent ID from previous execution
}
```

### Use Cases

- **Long-running research**: Break large codebase analysis into multiple sessions
- **Iterative refinement**: Continue refining without losing context
- **Multi-step workflows**: Sequential related tasks with maintained context

### Technical Notes

- Transcripts stored in project directory
- Recording disabled during resume (no duplication)
- Both sync and async agents can be resumed
- Track agent IDs for tasks you may want to continue

## Agent Chaining

Chain multiple agents for complex workflows:

```
> First use the code-analyzer agent to find performance issues,
  then use the optimizer agent to fix them
```

Claude orchestrates the handoff automatically, passing relevant findings between agents.

### Common Chaining Patterns

| Pattern | Agents | Description |
|---------|--------|-------------|
| **Analyze → Fix** | Explore → General-purpose | Find issues, then implement fixes |
| **Review → Simplify** | Code-reviewer → Code-simplifier | Review quality, then refactor |
| **Plan → Implement** | Plan → General-purpose | Design approach, then execute |
| **Test → Fix → Test** | Test-runner → Debugger → Test-runner | Verify, fix failures, re-verify |

## Agent Isolation with Worktrees

For parallel agent execution that modifies files, use worktree isolation:

```typescript
{
  "description": "Implement feature X",
  "prompt": "...",
  "subagent_type": "general-purpose",
  "isolation": "worktree"
}
```

Each agent gets an isolated copy of the repository, preventing file conflicts.

## Best Practices

1. **Start with Claude-generated agents**: Use `/agents` → Create New Agent → Generate with Claude, then customize
2. **Focused responsibility**: One agent per task type (not one does-everything agent)
3. **Detailed prompts**: More guidance → better performance
4. **Minimal tools**: Only grant necessary tools for security and focus
5. **Version control**: Commit `.claude/agents/` files for team sharing
6. **Test before deploying**: Try agents on sample tasks before relying on them
