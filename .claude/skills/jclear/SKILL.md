---
description: "Checkpoint current jflow task state, then instruct user to /clear"
disable-model-invocation: true
---

# /jclear

Safely prepare for context clearing: save state, then instruct the user to run `/clear`.

**Important:** This skill does NOT call `/clear` itself — that is impossible from a skill. It only prepares the state and instructs the user.

## Instructions

1. Compute the bridge file path:
   - `hash` = first 8 chars of `echo -n "$CLAUDE_PROJECT_DIR" | shasum`
   - `bridge` = `/tmp/jflow-ctx-<hash>.json`
2. Read the bridge file. Extract `context_percent`. If the file doesn't exist, assume `context_percent = 0`.
3. Read `$CLAUDE_PROJECT_DIR/.claude/current-task` → `task-id` (may be empty/missing).
4. **Branch A** — `context_percent < 60` AND `task-id` is empty:
   - Say: "Context is low (<N>%), no active task. You can run `/clear` without preparation."
   - Stop.
5. **Branch B** — otherwise:
   - Execute the `/jhandoff` logic (see jhandoff skill): read `state.md`, write a meaningful updated summary, preserve `Done` entries, write `Context for resume`.
   - Append to `TASK_DIR/events.jsonl`:
     ```json
     {"ts":"<ISO-now>","type":"jclear","task":"<task-id>","context_pct":<N>,"handoff_done":true}
     ```
   - Output:
     ```
     Handoff saved to .claude/tasks/<task-id>/state.md
     Context: <N>%
     
     Next steps:
     1. Run /clear to reset context.
     2. Then type "Continue" or a specific task.
     
     SessionStart hook will automatically load the summary into the new context.
     ```
