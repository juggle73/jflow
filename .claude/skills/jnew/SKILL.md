---
description: "Create a new jflow task with all stage files from templates"
disable-model-invocation: true
---

# /jnew <task-id> [--from <source-task-id>]

Create a new task directory under `.claude/tasks/<task-id>/` with all stage templates.

## Instructions

1. Parse arguments: first arg is `<task-id>` (required). Optional `--from <source-task-id>` to copy deps.
2. If no `<task-id>` provided, ask the user for one.
3. Set variables:
   - `TASK_DIR` = `$CLAUDE_PROJECT_DIR/.claude/tasks/<task-id>`
   - `TEMPLATES` = `$CLAUDE_PROJECT_DIR/.claude/skills/_templates`
4. If `TASK_DIR` already exists, report error and stop: "Task `<task-id>` already exists at `TASK_DIR`."
5. Create `TASK_DIR`.
6. Copy all files from `TEMPLATES` into `TASK_DIR`:
   - `00-spec.md`, `01-design.md`, `02-plan.md`, `03-impl.md`, `04-test.md`, `05-release.md`, `state.md`
7. In `00-spec.md`: replace `<task-name>` with `<task-id>` and `<date>` with today's ISO date.
8. In `state.md`: replace `<task-id>` with the actual task ID and `<date>` with today's ISO date.
9. Write `<task-id>` into `$CLAUDE_PROJECT_DIR/.claude/current-task` (overwrite).
10. Create empty file `TASK_DIR/events.jsonl`.
11. Create empty file `TASK_DIR/deps.md`.
12. If `--from <source-task-id>` was given and the source task exists, copy its `deps.md` content.
13. Append to `events.jsonl`:
    ```json
    {"ts":"<ISO-now>","type":"task_created","task":"<task-id>"}
    ```
14. Report to the user:
    ```
    Task created: <task-id>
    Path: TASK_DIR/00-spec.md
    
    Please fill in the spec, then use /jstage design to proceed.
    ```
