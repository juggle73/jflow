---
description: "Show a summary of the current jflow task phase (read-only)"
disable-model-invocation: true
---

# /jphase

Display a compact summary of the active task: current stage, what's done, what's in progress, what's next.

## Instructions

This is a **read-only** command. Do NOT modify any files.

1. Read `$CLAUDE_PROJECT_DIR/.claude/current-task` → `task-id`. If missing, say "No active task. Use /jnew to create one."
2. Set `TASK_DIR` = `$CLAUDE_PROJECT_DIR/.claude/tasks/<task-id>`.
3. Read `TASK_DIR/state.md`. Extract:
   - `Stage`, `Status`, `Created`, `Last update`
   - `Done` section content
   - `In progress` section content
   - `Open questions` section content
   - `Next` section content
4. If `TASK_DIR/events.jsonl` exists, count events from the last 24 hours (compare timestamps).
5. Output a compact summary (max 30 lines):
   ```
   ## Task: <task-id>
   Stage: <stage> | Status: <status>
   Created: <date> | Last update: <date>

   ### Done
   <content or "nothing yet">

   ### In progress
   <content or "nothing yet">

   ### Open questions
   <content or "none">

   ### Next
   <content or "not defined">

   Activity (24h): <N> events
   ```
