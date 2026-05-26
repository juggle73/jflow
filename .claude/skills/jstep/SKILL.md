---
description: "Record a progress step within the current stage of the active jflow task"
disable-model-invocation: true
---

# /jstep <message>

Record a short progress note within the current stage.

## Instructions

1. Parse `<message>` from arguments. If empty, ask the user what to record.
2. Read `$CLAUDE_PROJECT_DIR/.claude/current-task` → `task-id`. If missing, tell user to run `/jnew` first.
3. Set `TASK_DIR` = `$CLAUDE_PROJECT_DIR/.claude/tasks/<task-id>`.
4. Read `TASK_DIR/state.md` → extract current stage from `**Stage:**` line.
5. Map stage to file: `spec`→`00-spec.md`, `design`→`01-design.md`, `plan`→`02-plan.md`, `impl`→`03-impl.md`, `test`→`04-test.md`, `release`→`05-release.md`.
6. Append to the stage file:
   ```markdown
   
   ### Step <ISO-timestamp>
   <message>
   ```
7. Append to `TASK_DIR/events.jsonl`:
   ```json
   {"ts":"<ISO-now>","type":"step","task":"<task-id>","stage":"<stage>","message":"<message>"}
   ```
8. Confirm: "Step recorded in `<stage-file>` for task `<task-id>`."
