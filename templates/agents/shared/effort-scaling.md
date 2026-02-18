# Effort Scaling Guide

Determine appropriate resource allocation based on task complexity.

## Quick Tasks (1-2 files, < 30 min)
- Single agent
- Direct implementation
- No Dev Docs needed
- Examples: typo fix, add utility function, update config

## Medium Tasks (3-5 files, 30 min - 2 hours)
- Single agent with specialized skills
- Brief planning phase
- Optional Dev Docs
- Examples: add API endpoint, create component, fix complex bug

## Large Tasks (6+ files, 2+ hours)
- Consider multi-agent delegation
- Required: Planning Mode
- Required: Dev Docs (3-file system)
- Phase-based implementation
- Examples: new feature, refactor module, major integration

## Agent Selection
| Task Type | Recommended Agent | Model |
|-----------|------------------|-------|
| Simple edit | Main agent | haiku |
| UI work | frontend-specialist | sonnet |
| API work | backend-specialist | sonnet |
| Testing | test-engineer | sonnet |
| Architecture | Main agent | opus |
| Code review | Main agent + code-reviewer skill | sonnet |
