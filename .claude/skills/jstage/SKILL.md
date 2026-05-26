---
description: "Switch focus to a specific stage of the current jflow task"
disable-model-invocation: true
---

# /jstage <stage>

Switch to a specific stage of the current task and load relevant context.

Valid stages: `spec`, `design`, `plan`, `impl`, `test`, `release`.

Stage-to-file mapping: `spec`→`00-spec.md`, `design`→`01-design.md`, `plan`→`02-plan.md`, `impl`→`03-impl.md`, `test`→`04-test.md`, `release`→`05-release.md`.

## Instructions

1. Parse `<stage>` argument. If missing or invalid, list valid stages and stop.
2. Read `$CLAUDE_PROJECT_DIR/.claude/current-task` → `task-id`. If missing, tell user to run `/jnew` first.
3. Set `TASK_DIR` = `$CLAUDE_PROJECT_DIR/.claude/tasks/<task-id>`.
4. Read `TASK_DIR/state.md` to get current state.
5. Determine the stage file for the requested stage.
6. Read the target stage file **in full**.
7. For each **earlier** stage (by number), read its last 30 lines as a summary. Do NOT load stages that come after the target stage.
8. Read `TASK_DIR/deps.md` — if it has content, load it fully.
9. Update `state.md`:
   - Set `**Stage:**` to the new stage name.
   - Set `**Last update:**` to current ISO date.
10. Append to `TASK_DIR/events.jsonl`:
    ```json
    {"ts":"<ISO-now>","type":"stage_changed","task":"<task-id>","to_stage":"<stage>"}
    ```
11. Report:
    ```
    Stage switched to: <stage>
    Loaded: <list of files read>
    ```
