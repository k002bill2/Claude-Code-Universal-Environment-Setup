---
description: Resume work from Dev Docs after session restart or compaction
---

Resume the current task by loading context from Dev Docs:

1. **Find Active Task**
   List all directories in `dev/active/` to find current tasks.

2. **Load Context**
   Read all three files for the active task:
   - `*-plan.md` - Understand the overall plan
   - `*-context.md` - Get current state and decisions
   - `*-tasks.md` - See what's done and what's next

3. **Identify Next Work**
   From the tasks file, find the first unchecked item `- [ ]`.

4. **Summarize Status**
   Report:
   - Task name and purpose
   - Overall progress (X/Y tasks complete)
   - Last session's work
   - What to work on next
   - Any known blockers

5. **Continue Work**
   Start working on the next unchecked task.

Remember: Always update Dev Docs periodically during the session.
