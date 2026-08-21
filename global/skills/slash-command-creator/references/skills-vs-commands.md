# Skills vs Slash Commands

## Quick Comparison

| Aspect | Slash Commands | Agent Skills |
|--------|---------------|--------------|
| **Complexity** | Simple prompts | Complex capabilities |
| **Structure** | Single `.md` file | Directory with `SKILL.md` + resources |
| **Discovery** | Explicit invocation (`/command`) | Automatic (based on context) |
| **Files** | One file only | Multiple files, scripts, templates |
| **Scope** | Project or personal | Project or personal |
| **Sharing** | Via git | Via git |
| **Programmatic** | Via `SlashCommand` tool | Auto-loaded by matching |
| **Model override** | `model` frontmatter | N/A (inherits) |

## When to Use Slash Commands

**Quick, frequently-used prompts**:
- Simple prompt snippets you use often
- Explicit-trigger workflows (user types `/command`)
- Templates with argument substitution

**Examples**:
- `/review` - "Review this code for bugs and suggest improvements"
- `/commit-push-pr` - Git commit + push + PR creation pipeline
- `/check-health` - Run type check + lint + test + build

## When to Use Skills

**Comprehensive capabilities with structure**:
- Complex workflows with multiple steps
- Capabilities requiring reference docs or scripts
- Knowledge organized across multiple files
- Auto-discovery based on task context

**Examples**:
- `react-web-development` - React/TypeScript/Tailwind patterns, Zustand store guidance
- `hook-creator` - Hook creation with event reference, examples, templates
- `test-automation` - Vitest test generation with coverage analysis

## Example Comparison

### As a Slash Command

```
.claude/commands/review.md
```

```markdown
---
description: Quick code review
---

Review this code for:
- Security vulnerabilities
- Performance issues
- Code style violations
```

Usage: `/review` (explicit invocation only)

### As a Skill

```
.claude/skills/code-review/
├── SKILL.md          # Overview and workflows
├── references/
│   ├── security.md   # Security checklist
│   ├── performance.md # Performance patterns
│   └── style.md      # Style guide
└── scripts/
    └── run-linters.sh
```

Usage: "Can you review this code?" (automatic discovery)

The Skill provides richer context, validation scripts, and organized reference material.

## Decision Guide

```
Is it a single prompt you type explicitly?
  → Slash Command

Does it need multiple reference files?
  → Skill

Should Claude discover it automatically?
  → Skill

Do you need argument substitution ($1, $2)?
  → Slash Command

Does it chain with other skills/hooks?
  → Skill

Is it a quick template < 50 lines?
  → Slash Command
```

## Coexistence

Both can work together. Common pattern in AOS:

1. **Skill** (`verification-loop`) - defines the verification methodology
2. **Command** (`/verify-app`) - triggers the verification with one keystroke
3. **Command** (`/check-health`) - lighter-weight health check variant

The skill provides knowledge; the commands provide quick access points.
