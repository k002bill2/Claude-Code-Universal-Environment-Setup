---
description: Update Dev Docs before context compaction or session end
---

Find and update all active Dev Docs in `dev/active/`:

1. **context.md** updates:
   - Update "Last Updated" timestamp
   - Add any new decisions made this session
   - Update "Current Issues" section
   - Revise "Next Steps" based on progress
   - Add/remove relevant files

2. **tasks.md** updates:
   - Mark completed items with `[x]`
   - Add any new tasks discovered during implementation
   - Update completion counts per section
   - Reorder by priority if needed
   - Note any blocked items

3. **Add session summary** at the bottom of context.md:
   ```
   ## Session Summary - [timestamp]
   - Completed: [list of completed items]
   - In Progress: [current work]
   - Blockers: [any blocking issues]
   - Next Priority: [what to do next]
   ```

Keep updates concise but comprehensive. This is Claude's memory for the next session.
