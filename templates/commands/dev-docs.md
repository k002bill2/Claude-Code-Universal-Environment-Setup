---
description: Create Dev Docs (3-file system) for a new task
---

Based on the current task or approved plan, create three development documents:

1. Create `dev/active/$ARGUMENTS/$ARGUMENTS-plan.md`
   - Copy the full approved plan
   - Add timeline and phases
   - Include success metrics
   - Define scope boundaries

2. Create `dev/active/$ARGUMENTS/$ARGUMENTS-context.md`
   - List all relevant files that will be modified
   - Document key architectural decisions
   - Note any constraints or dependencies
   - Add "Current Issues" section
   - Add "Next Steps" section
   - Timestamp everything

3. Create `dev/active/$ARGUMENTS/$ARGUMENTS-tasks.md`
   - Convert plan into detailed checkbox list
   - Group by component/module
   - Use `- [ ]` format for tracking
   - Add completion counts per section
   - Order by implementation priority

Remember:
- Timestamp all documents
- Keep plan concise but comprehensive
- Tasks should be atomic (completable in one session)
- Each task should take 15-30 minutes max
