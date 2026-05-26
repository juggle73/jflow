---
description: "List all jflow tasks with their current state (read-only)"
disable-model-invocation: true
---

# /jstatus

Display a table of all tasks in `.claude/tasks/` with their state.

## Instructions

This is a **read-only** command. Do NOT modify any files.

1. List all directories in `$CLAUDE_PROJECT_DIR/.claude/tasks/`. If none, say "No tasks found. Use /jnew to create one."
2. Read `$CLAUDE_PROJECT_DIR/.claude/current-task` to know which task is active (may not exist).
3. For each task directory, read its `state.md` and extract:
   - `Stage` (from `**Stage:**`)
   - `Status` (from `**Status:**`)
   - `Last update` (from `**Last update:**`)
4. Sort tasks by `Last update`, newest first.
5. Output a table:
   ```
   | Task | Stage | Status | Last update | Active |
   |------|-------|--------|-------------|--------|
   | <id> | <stage> | <status> | <date> | ← |
   ```
   Mark the current task with `←`.
