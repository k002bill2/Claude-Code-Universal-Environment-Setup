---
description: Code review for recent changes using code-reviewer skill
---

Perform a comprehensive code review of recent changes:

1. **Identify Changes**
   Run `git diff --stat` and `git diff` to see all modified files.

2. **Load Review Skill**
   Use the code-reviewer skill checklist for structured review.

3. **Review Each File**
   For each changed file, check:
   - Code quality and readability
   - Security implications
   - Performance impact
   - Test coverage
   - Documentation updates needed

4. **Generate Report**
   Format output as:
   ```
   ## Code Review Report

   ### Summary
   Status: [Approved / Needs Changes]
   Files Reviewed: [count]
   Risk Level: [Low / Medium / High]

   ### Findings
   [Categorized findings with file:line references]

   ### Recommendations
   [Actionable improvement suggestions]
   ```

5. **Suggest Fixes**
   For any issues found, provide specific code suggestions.
