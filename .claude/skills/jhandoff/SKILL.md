---
description: "Save current task state into state.md and prepare for /clear (or just session pause)"
disable-model-invocation: true
---

# /jhandoff

Save the current task's state into `state.md` so the work can resume cleanly later — after `/clear`, a session restart, or simply a pause. Run this before any context wipe.

## Instructions

1. Compute `hash` = first 8 chars of `shasum` of `$CLAUDE_PROJECT_DIR`. Read `/tmp/jflow-ctx-<hash>.json` if it exists — extract `context_percent` and `total_input_tokens`. If the file is missing, treat both as `0`.

2. Read `$CLAUDE_PROJECT_DIR/.claude/current-task` → `task-id`.

3. **Fast-path:** if `task-id` is missing/empty AND `context_percent < 60`, say:
   > No active task; context is low (<N>%). `/clear` is safe whenever — nothing to save.
   and stop. Do not write any files.

4. If `task-id` is missing/empty but context is high (≥ 60%), say:
   > No active task to checkpoint. Context is at <N>% — consider `/clear` directly, or `/jnew` if you want to start tracking work.
   and stop.

5. Otherwise (active task present): set `TASK_DIR` = `$CLAUDE_PROJECT_DIR/.claude/tasks/<task-id>`. Read `TASK_DIR/state.md` fully — note existing content in all sections, especially `Done` (cumulative).

6. **You (Claude) must write** an updated `state.md` with these sections. This is a thoughtful summary, NOT an automated dump:
   - `**Stage:**` — current stage
   - `**Last update:**` — current ISO date
   - `**Status:**` — active / blocked / done
   - `## Done` — cumulative list of completed items. **Preserve all previous entries** and add new ones.
   - `## In progress` — what's currently being worked on.
   - `## Open questions` — unresolved questions.
   - `## Next` — next steps.
   - `## Context for resume` — 5-10 lines of distilled context: key decisions, what someone needs to know to continue this work without the original transcript. **Most important section for resume.**

7. Keep the `## Auto-snapshot` section and everything after the `---` separator intact — do not modify or remove it.

8. Write the updated `state.md`.

9. Append to `TASK_DIR/events.jsonl`:
   ```json
   {"ts":"<ISO-now>","type":"handoff","task":"<task-id>","stage":"<stage>","context_pct":<N>,"tokens_used":<total_input_tokens or null>}
   ```

10. Final output to the user:
    ```
    ✅ Handoff saved to .claude/tasks/<task-id>/state.md
    Context: <N>%

    Safe to /clear now. Resume in a new session with /jnext.
    ```

    If `## Open questions` is non-empty after the write, append a warning line
    before the «Safe to /clear» line:

    > ⚠ <N> open question(s) remain. They must be resolved (or explicitly
    > deferred with rationale) before `/jstage` will switch stages.

## Acceptance criteria

- Fast-path skips file writes when there's nothing to save.
- `Done` is cumulative — never overwrites prior entries.
- Always writes `Context for resume` — that's what `/jnext` and the SessionStart hook rely on.
- `## Auto-snapshot` block is preserved untouched.
- Final message tells the user the next concrete step.
