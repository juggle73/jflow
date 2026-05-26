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

10. Pick the next single item: the first from `In progress` if non-empty, otherwise the first from `Next`. Call this the **chosen item**.

11. **Special-case: stage transition.** If the chosen item describes a stage transition — anything matching patterns like «перейти к этапу X», «switch to <stage>», «move to <stage>», «start <stage>», «→ <stage>», or otherwise clearly meaning "go to the next stage" — do **NOT** perform the transition yourself. Instead, output:

    > Next step is a stage transition: `<prev>` → `<new>`. Run `/jstage <new>` to switch — it enforces the open-questions gate and runs the auto-review of `<prev>`.

    Then stop. Do not edit `state.md`, do not write the next stage file, do not start working on the new stage.

12. **General case.** Otherwise, act on the **chosen item** — and only that one item. If the chosen item is genuinely ambiguous (multiple valid paths), ask one short clarifying question before acting.

13. **Maintain the stage file as you work.** While in any stage, update its file as a work log:
    - In `impl` stage: see the `Maintenance rule for Claude` banner at the top of `03-impl.md`. Append to `What was built` / `Files changed` / `Notes for review` as the chosen item progresses. Two milestones without updates = doing it wrong.
    - In other stages: similarly keep the stage file current with the work being done; don't leave it blank.

14. **Stop after one item.** When the chosen item is complete, output a short report:

    > ✅ Done: <one-line summary of what changed>
    > Files touched: <list>
    > Next would naturally be: <one-line forecast — but do not act on it>

    Then **wait**. Do NOT auto-chain into the next item. The user will run `/jnext` again to continue, or give different direction, or run `/jstage <new>` when ready to transition.

## Acceptance criteria

- Reads `state.md` and the current stage file fully; does not load future stages.
- Always logs a `resume` event.
- Recap is compact (≤ 25 lines).
- Acts on **exactly one** item per invocation. Never walks multiple Next-items in one run.
- Stage transitions are **never** performed directly — always routed through `/jstage`.
- In impl stage, `03-impl.md` is updated as work happens, never left as template.
