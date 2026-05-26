---
description: "Start a new jflow task; Claude drafts the spec interactively from a free-text description"
disable-model-invocation: true
---

# /jnew [id <task-id>] [<task description...>] [--from <source-task-id>]

Create a new task. All arguments are **optional**:

- `id <task-id>` — explicit kebab-case identifier. If omitted, Claude proposes one from the description.
- `<task description>` — free-text description of what to do. If omitted, Claude asks the user.
- `--from <source-task-id>` — copy `deps.md` from another existing task.

Examples:
- `/jnew` — Claude asks "what do you want to do?"
- `/jnew Build a CSV → Parquet converter` — auto-derive ID, draft spec
- `/jnew id csv-tool` — fixed ID, Claude asks for description
- `/jnew id csv-tool Build a CSV → Parquet converter` — both supplied

## Instructions

### 1. Parse arguments

Treat the literal token `id` as a flag **only if it is the very first token** of the arguments. If so, the next token is `<task-id>` and the remainder is the description. Otherwise, the whole argument string is the description. Same for `--from <source-task-id>` — extract and remove from the description string.

### 2. Obtain the description

If after parsing the description is empty, ask the user — **in the language they have been using in this conversation**. Default phrasings:
- Russian conversation: «Что вы хотите сделать?»
- English conversation: "What do you want to do?"
- Other languages: phrase the question naturally in that language.

Wait for their reply, then continue.

### 3. Draft the spec interactively

Internally outline a working spec with:
- **Problem** — what we're solving and why.
- **Goals** — concrete, measurable.
- **Non-goals** — explicit scope cuts.
- **Success criteria** — how we'll know it's done.

Identify any *genuinely* ambiguous points: technology/stack choices that materially affect implementation, scope boundaries that could double the work, hard constraints (performance, memory, latency, deadlines), integration boundaries (which systems must this talk to).

Ask the user **1–3 focused clarifying questions** — never more. Skip questions where a sensible default exists; don't bikeshed. If the description is already specific enough, skip clarification entirely and go straight to drafting.

### 4. Decide the task ID

If `id <task-id>` was supplied, use it.

Otherwise, propose a kebab-case ID derived from the description: 3–5 meaningful words, under 40 chars, no stopwords ("a", "the", "и", "для" etc.). Show it briefly: «ID: `<proposed-id>` — OK?» and proceed unless the user pushes back.

### 5. Create files

After ID and spec content are settled:

1. Set `TASK_DIR` = `$CLAUDE_PROJECT_DIR/.claude/tasks/<task-id>`. If it already exists, propose `<id>-2`, `<id>-3`, … and confirm with the user.
2. Create `TASK_DIR`.
3. Copy every file from `$CLAUDE_PROJECT_DIR/.claude/skills/_templates/` into `TASK_DIR`.
4. **Overwrite** `TASK_DIR/00-spec.md` with the actual drafted spec (Problem / Goals / Non-goals / Success criteria filled in). Set the `**Created:**` line to today's ISO date and the title to the task ID. **No placeholder `<...>` markers should remain.**
5. In `TASK_DIR/state.md`, substitute `<task-id>` with the actual ID and `<date>` with today's ISO date.
6. Write `<task-id>` into `$CLAUDE_PROJECT_DIR/.claude/current-task` (overwrite).
7. Create empty `TASK_DIR/events.jsonl` and `TASK_DIR/deps.md`.
8. If `--from <source-task-id>` was given and `$CLAUDE_PROJECT_DIR/.claude/tasks/<source-task-id>/deps.md` exists, copy its contents into the new `deps.md`.
9. Append to `events.jsonl`:
   ```json
   {"ts":"<ISO-now>","type":"task_created","task":"<task-id>"}
   ```

### 6. Report

Output a compact summary in the user's language. Example (Russian):

```
✅ Задача создана: <task-id>
Этап: spec (готов)

Кратко:
<2-4 строки: проблема + ключевые цели>

Файлы: .claude/tasks/<task-id>/
```

English variant:

```
✅ Task created: <task-id>
Stage: spec (drafted)

Brief:
<2-4 line recap: problem + key goals>

Files: .claude/tasks/<task-id>/
```

**Do NOT end with phrases like «заполните спецификацию» or «теперь выполните /jstage design».** The spec is already drafted, and the user decides what to do next conversationally. The summary is enough.

## Acceptance criteria

- All arguments are optional; the skill is usable as bare `/jnew`.
- If description is missing, the question is asked in the conversation language.
- `00-spec.md` has **no placeholder `<...>` markers** when the skill finishes — the spec is fully drafted.
- Clarifying questions are bounded at 1–3 total, not per turn.
- The final report does not push the user to `/jstage design` or to fill anything in.
