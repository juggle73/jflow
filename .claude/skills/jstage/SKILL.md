---
description: "Switch jflow task to a stage; gate on open questions, then auto-review the just-completed stage"
disable-model-invocation: true
---

# /jstage <stage>

Switch the current task to a specific stage. Before switching, all open questions from the current stage must be resolved with the user. After switching, a review agent automatically audits the just-completed stage.

Valid stages: `spec`, `design`, `plan`, `impl`, `test`, `release`.

Stage→file mapping: `spec`→`00-spec.md`, `design`→`01-design.md`, `plan`→`02-plan.md`, `impl`→`03-impl.md`, `test`→`04-test.md`, `release`→`05-release.md`.

## Instructions

### 1. Parse and locate

1. Parse `<stage>`. If missing or invalid, list valid stages and stop.
2. Read `$CLAUDE_PROJECT_DIR/.claude/current-task` → `task-id`. If missing, tell the user to run `/jnew` first.
3. Set `TASK_DIR` = `$CLAUDE_PROJECT_DIR/.claude/tasks/<task-id>`.
4. Read `TASK_DIR/state.md` and the current stage file. Extract current stage and `## Open questions` sections from both.

### 2. Resolve open questions (BLOCKING GATE)

**This step does not auto-skip.** Open questions from the current stage MUST be addressed before the switch — either answered or explicitly deferred with user consent. Claude never silently answers or defers on the user's behalf.

For each open question:

1. Present the question to the user.
2. Offer three explicit options:
   - **Answer now** — user gives the decision. Move the question from `## Open questions` into the relevant stage file's `## Key decisions` (or equivalent) section, with the question and answer joined: `Q: <question> → A: <answer>`. Remove from Open questions.
   - **Defer with rationale** — user explains *why* it cannot be answered now and *what event/condition* would unblock it. Rewrite the question in `## Open questions` as: `<question> _(deferred until <condition>: <reason>)_`. The question stays visible but is marked.
   - **Cancel transition** — abort `/jstage` without changes. Tell the user.

If the user picks "cancel" at any point, stop immediately. State and stage files must remain unchanged.

If the user picks "defer" for a question, **always** record the deferral marker in state.md and in the stage file. Both files must reflect the same status.

After this step, `## Open questions` either contains no items or contains only deferred items.

### 3. Load context for the new stage

- Read the target stage file in full.
- For each **earlier** stage (lower number), read the last 30 lines as a summary. Do NOT load future stages.
- Read `TASK_DIR/deps.md` if non-empty.

### 4. Update state

Update `state.md`:
- Set `**Stage:**` to the new stage.
- Set `**Last update:**` to today's ISO date.

Append to `TASK_DIR/events.jsonl`:
```json
{"ts":"<ISO-now>","type":"stage_changed","task":"<task-id>","from_stage":"<prev>","to_stage":"<new>"}
```

### 5. Auto-review the just-completed stage

After the switch, **spawn a review agent** using the `Agent` tool. This audits the artifact of the stage you just left.

Choose `subagent_type`:
- For `impl`→`test` transition: `code-review` if available, otherwise `general-purpose`.
- For all other transitions: `Plan` if available, otherwise `general-purpose`.

Use a stage-specific review prompt:

| Just-completed stage | Review prompt (paste with task ID interpolated) |
|---|---|
| `spec` | "Read `.claude/tasks/<task-id>/00-spec.md`. Check: (a) is the problem unambiguous? (b) are goals measurable? (c) are non-goals concrete cuts (not vague exclusions)? (d) are success criteria testable? Report gaps that would block design work. Be concise — bullet points only." |
| `design` | "Read `.claude/tasks/<task-id>/01-design.md` and `00-spec.md`. Check: (a) does the approach meet every spec goal? (b) are alternatives genuinely evaluated, not strawmen? (c) are key decisions justified against constraints? (d) are integration boundaries explicit? (e) any decisions that contradict the spec? Report concrete issues." |
| `plan` | "Read `.claude/tasks/<task-id>/02-plan.md`, `01-design.md`, `00-spec.md`. Check: (a) do milestones cover every design decision? (b) is the current focus actually actionable today? (c) are blockers identified? (d) is the order of work sensible? Report gaps." |
| `impl` | "Read `.claude/tasks/<task-id>/03-impl.md` and the files listed under 'Files changed'. Run a focused code review for correctness bugs, edge cases, security issues, and gaps versus the plan. Cite file:line where possible. Be concise." |
| `test` | "Read `.claude/tasks/<task-id>/04-test.md` and the test files referenced. Check: (a) does coverage map to every success criterion from 00-spec.md? (b) are edge cases tested (empty input, max size, concurrent, malformed)? (c) any untested error paths? Report concrete gaps." |
| `release` | (no review — final stage) |

Wait for the agent to return. **Surface the findings to the user verbatim** if they are short, or summarize with key points if very long. Do NOT auto-fix; the user decides what to do with the findings.

If the review reports critical issues, end your report with a clear recommendation: "Recommend addressing these before progressing in `<new-stage>`."

### 6. Report and confirm next-stage start

Output:

```
✅ Stage switched: <prev> → <new>
Loaded into context:
  - <list of files>

Review of <prev>:
<verbatim or summarized findings, or "no issues found">
```

Then, in the same turn, **explicitly ask the user** before doing any work in the new stage:

> Stage `<new>` is ready. How do we proceed?
> 1. Start working on it now (I'll act on the first item from its Next list)
> 2. Address review findings first
> 3. Pause — I'll wait for your direction

**Stop and wait for the user's answer.** Do NOT start working on the new stage in the same turn as the transition, even if the review reported zero issues. The transition is one logical step; starting work is a separate, user-initiated step.

If the new stage is `impl`, also include this reminder in the question:

> ⚠ In `impl` stage I must keep `03-impl.md` updated as work happens (see the banner at the top of that file). Two milestones without updates = doing it wrong.

## Acceptance criteria

- Cannot transition while any non-deferred open question exists.
- Deferred questions carry an explicit `(deferred until <condition>: <reason>)` marker, written by the user, not Claude.
- Review agent runs on every transition except from `release`.
- Review findings are surfaced, not silently swallowed.
- Cancellation leaves state.md and stage files byte-identical to pre-transition.
- After the transition, the skill **always stops and asks** before starting any work in the new stage. Auto-continuation is forbidden.
- When transitioning into `impl`, the confirmation prompt explicitly reminds about the `03-impl.md` work-log discipline.
