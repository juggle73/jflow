---
description: "Write a meaningful session summary into the active jflow task's state.md"
disable-model-invocation: true
---

# /jhandoff

Finalize current session work by writing a meaningful summary into `state.md`.

## Instructions

1. Read `$CLAUDE_PROJECT_DIR/.claude/current-task` → `task-id`. If missing, say "No active task." and stop.
2. Set `TASK_DIR` = `$CLAUDE_PROJECT_DIR/.claude/tasks/<task-id>`.
3. Read `TASK_DIR/state.md` fully — note existing content in all sections, especially `Done` (cumulative).
4. **You (Claude) must write** an updated `state.md` with these sections. This is a thoughtful summary, NOT an automated dump:
   - `**Stage:**` — current stage
   - `**Last update:**` — current ISO date
   - `**Status:**` — active/blocked/done
   - `## Done` — cumulative list of completed items. **Preserve all previous entries** and add new ones.
   - `## In progress` — what's currently being worked on.
   - `## Open questions` — unresolved questions.
   - `## Next` — next steps.
   - `## Context for resume` — 5-10 lines of distilled context: key decisions, what someone needs to know to continue this work without the original transcript. This is the most important section for session continuity.
5. Keep the `## Auto-snapshot` section and everything after `---` separator intact — do not modify or remove it.
6. Write the updated `state.md`.
7. Read the bridge file `/tmp/jflow-ctx-<hash>.json` (where hash = first 8 chars of `shasum` of `$CLAUDE_PROJECT_DIR`) to get `tokens_used` if available.
8. Append to `TASK_DIR/events.jsonl`:
   ```json
   {"ts":"<ISO-now>","type":"handoff","task":"<task-id>","stage":"<stage>","tokens_used":<from bridge or null>}
   ```
9. Report: "Handoff saved to `TASK_DIR/state.md`."
