---
description: "Read the active task's saved state and resume work from where it stopped"
disable-model-invocation: true
---

# /jnext

Resume work on the active task. Use after `/clear`, after a session restart, or any time you want to pick up where you left off without manually re-reading files.

Unlike the SessionStart hook (which injects only a short summary), `/jnext` loads the full stage file and prior context, then proceeds to the next actionable step.

## Instructions

1. Read `$CLAUDE_PROJECT_DIR/.claude/current-task` → `task-id`.
   If missing or empty, say:
   > No active task. Use `/jstatus` to see existing tasks or `/jnew` to create one.
   and stop.

2. Set `TASK_DIR` = `$CLAUDE_PROJECT_DIR/.claude/tasks/<task-id>`. If the directory does not exist, report the inconsistency and stop.

3. Read `TASK_DIR/state.md` in full. Extract:
   - `Stage` (from `**Stage:**`)
   - `Status` (from `**Status:**`)
   - `## Done`
   - `## In progress`
   - `## Open questions`
   - `## Next`
   - `## Context for resume`

4. Map the stage to its file:
   `spec`→`00-spec.md`, `design`→`01-design.md`, `plan`→`02-plan.md`,
   `impl`→`03-impl.md`, `test`→`04-test.md`, `release`→`05-release.md`.

5. Read the current stage file in full.

6. For each **earlier** stage (lower number), read its last 30 lines as a summary. Skip stages that come after the current one.

7. If `TASK_DIR/deps.md` exists and has content, read it in full.

8. Append to `TASK_DIR/events.jsonl`:
   ```json
   {"ts":"<ISO-now>","type":"resume","task":"<task-id>","stage":"<stage>"}
   ```

9. Output a compact recap to the user (≤ 25 lines):
   ```
   ▶ Resuming: <task-id>  |  stage: <stage>  |  status: <status>

   Done so far:
   <Done items, max 5 latest>

   Picked up at:
   <first In progress item, or first Next item if In progress is empty>

   Open questions to keep in mind:
   <Open questions, or "none">

   Loaded into context:
   - <current-stage-file> (full)
   - <list of earlier-stage summaries>
   - deps.md (if non-empty)
   ```

10. Then **continue working**: act on the first item from `In progress` (if any) or the first item from `Next`. Do not ask for confirmation — the user already invoked `/jnext` because they want to proceed. If the first item is genuinely ambiguous (multiple equally-valid paths), ask one short clarifying question before acting.

## Acceptance criteria

- Reads `state.md` and the current stage file fully; does not load future stages.
- Always logs a `resume` event.
- Recap is compact (≤ 25 lines).
- Proceeds to action without asking unless genuinely ambiguous.
