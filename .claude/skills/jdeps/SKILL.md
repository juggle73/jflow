---
description: "View and manage dependencies between jflow tasks"
disable-model-invocation: true
---

# /jdeps [add <task-id> [--type depends-on|blocks|related]] [remove <task-id>]

Manage the `deps.md` file for the current task.

## Instructions

1. Read `$CLAUDE_PROJECT_DIR/.claude/current-task` → `task-id`. If missing, say "No active task." and stop.
2. Set `TASK_DIR` = `$CLAUDE_PROJECT_DIR/.claude/tasks/<task-id>`.
3. Parse arguments:

### No arguments — show deps
- Read `TASK_DIR/deps.md`. If empty or missing, say "No dependencies for `<task-id>`."
- Otherwise display the contents.

### `add <target-task-id> [--type <type>]`
- Default type is `depends-on`.
- Valid types: `depends-on`, `blocks`, `related`.
- Check that `$CLAUDE_PROJECT_DIR/.claude/tasks/<target-task-id>` exists. If not, error: "Task `<target-task-id>` not found."
- Check that the dependency doesn't already exist in `deps.md`. If it does, say so and stop.
- Append to `TASK_DIR/deps.md`:
  ```
  <type>: <target-task-id>
  ```
- **Symmetry:** If type is `depends-on`, append to the target task's `deps.md`:
  ```
  blocks: <task-id>
  ```
  If type is `blocks`, append to the target task's `deps.md`:
  ```
  depends-on: <task-id>
  ```
  If type is `related`, append to the target task's `deps.md`:
  ```
  related: <task-id>
  ```
- Confirm: "Added `<type>: <target-task-id>` to `<task-id>` deps."

### `remove <target-task-id>`
- Remove all lines mentioning `<target-task-id>` from `TASK_DIR/deps.md`.
- Also remove symmetric entries from the target task's `deps.md`.
- Confirm: "Removed dependency on `<target-task-id>` from `<task-id>`."
