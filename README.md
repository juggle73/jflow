# jflow

**Multi-stage task management for Claude Code — minimize context, survive auto-compact, resume seamlessly across sessions.**

`jflow` is a lightweight system of skills, hooks and helper scripts that lives entirely inside your project's `.claude/` directory. It organizes long-running work into discrete stages, keeps only relevant context in memory, and reliably restores state after `/clear` or session restarts.

---

## Why

LLM-assisted engineering on non-trivial tasks runs into three recurring problems:

1. **Context bloat.** The longer you work, the more irrelevant material fills the window, until output quality degrades or auto-compact wipes useful state.
2. **Lost state across sessions.** Restarting a session means re-explaining where you were, what was decided, and what's next.
3. **No structure for multi-day work.** Spec, design, plan, implementation, tests, release — all collapse into one rolling chat.

`jflow` addresses these by enforcing a stage-based workflow with explicit save points, a hybrid (manual + automatic) state persistence model, and bridge files for cross-hook coordination.

---

## Core principles

1. **Stage decomposition.** Every task flows through `spec → design → plan → impl → test → release`. Each stage is its own markdown file with explicit inputs and outputs.
2. **Minimal context loading.** Switching stage loads only that stage's file in full, plus brief 30-line summaries of earlier closed stages and any declared dependencies.
3. **Hybrid state save.** State is written two ways: an automatic raw dump from the transcript (reliable) and a meaningful summary Claude writes on demand (substantive). Both coexist in the same `state.md` without conflict.
4. **Project-scoped.** Everything lives in `.claude/` inside the project, addressed via `$CLAUDE_PROJECT_DIR`. No machine-wide config, no hardcoded paths.
5. **Opt-in.** Skills never auto-activate. All commands require an explicit user invocation.
6. **Lightweight hooks.** Hooks do only the bare minimum (threshold checks, snapshot dumps). All heavy work happens in user-invoked skills.

---

## Installation

### One-liner (recommended)

```bash
curl -fsSL https://raw.githubusercontent.com/juggle73/jflow/main/install.sh | bash
```

Install into a specific directory:

```bash
curl -fsSL https://raw.githubusercontent.com/juggle73/jflow/main/install.sh | bash -s -- /path/to/project
```

Install from a fork or branch:

```bash
curl -fsSL https://raw.githubusercontent.com/juggle73/jflow/main/install.sh \
  | JFLOW_REPO=myuser/jflow JFLOW_BRANCH=dev bash
```

### Manual install (local clone)

```bash
git clone https://github.com/juggle73/jflow.git
cd /path/to/your/project
/path/to/jflow/install.sh
```

### What the installer does

- Checks dependencies (`bash`, `jq`, `git`, `shasum`/`sha1sum`).
- Detects OS (macOS / Linux / Windows-POSIX).
- Copies `scripts/`, `skills/` and `settings.json` into `<project>/.claude/`.
- If `.claude/settings.json` already exists, **merges** jflow hooks into it without duplicating existing entries (idempotent). The original is backed up to `settings.json.bak.<timestamp>`.
- Hybrid delivery: tries `git clone --depth 1` first, falls back to tarball via `curl`/`wget` if git is unavailable.

### Requirements

| Tool | Purpose |
|------|---------|
| `bash` 4.x+ | Runs scripts and hooks |
| `jq` | JSON parsing in scripts and settings merge |
| `git` | Branch detection (statusline), optional remote fetch |
| `curl` or `wget` | Tarball fallback for remote install |
| `shasum` or `sha1sum` | Hash of project path for bridge files |

### Platform support

| OS | Status |
|---|---|
| macOS | Native |
| Linux | Native |
| Windows (Git Bash, WSL, Cygwin) | Supported via POSIX shell |
| Windows native (PowerShell/cmd) | Not supported — bash scripts only |

---

## Commands

All commands are skills under `.claude/skills/`. They run only when invoked explicitly — Claude does not call them autonomously.

| Command | Purpose |
|---------|---------|
| `/jnew [id <task-id>] [<description>]` | Start a new task. Both arguments are optional — if you skip the description, Claude asks you; if you skip the ID, Claude proposes one. The spec (`00-spec.md`) is drafted interactively, not left as a blank template. |
| `/jstage <stage>` | Switch to a stage (`spec`, `design`, `plan`, `impl`, `test`, `release`). **Gate:** every open question from the current stage must first be answered or explicitly deferred with rationale. **Auto-review:** after the switch, a review agent audits the just-completed stage and surfaces findings. Loads only the target stage in full plus 30-line summaries of earlier stages. |
| `/jstep <message>` | Record a short progress note inside the current stage. |
| `/jphase` | Read-only summary of the active task (stage, what's done, in progress, next). |
| `/jstatus` | Read-only table of all tasks with their stage, status, last-update. |
| `/jhandoff` | Save the current task's state into `state.md` (`Done`, `In progress`, `Open questions`, `Next`, `Context for resume`). Run before `/clear` or any session pause; final message tells you it's safe to clear. |
| `/jnext` | Resume work after `/clear` or a session restart. Loads the full current-stage file and prior context, then proceeds to the next actionable step. |
| `/jdeps [add\|remove] <task-id> [--type ...]` | Manage `deps.md` for the current task with automatic symmetric updates. |

---

## How state survives `/clear` and session restarts

```
You work in a session
  │
  ▼
/jstep "did X"            ← short notes during work
  │
  ▼
/jhandoff                 ← Claude writes meaningful summary into state.md
  │
  ▼
/clear (or /exit, Ctrl-D) ← SessionEnd hook appends Auto-snapshot
  │
  ▼
New session starts        ← SessionStart hook injects Context for resume
  │
  ▼
/jnext                    ← loads full stage file, picks up the next step
```

- **Meaningful summary** (Claude writes) — slow path, 100% reliable when you call `/jhandoff`.
- **Auto-snapshot** (SessionEnd hook) — fast path, captures tool counts, files touched, duration, tokens. Reliable for 99% of exits.
- **Resume** (SessionStart hook) — injects the active task's stage, in-progress items, next steps, and `Context for resume` block (max 50 lines) into the new session's context.

Together this means: even after a hard `/clear`, the new session opens with everything needed to continue.

---

## Stage transitions: gate + auto-review

Every `/jstage` switch enforces two things, in order:

1. **Open-questions gate.** Before the transition, every unresolved item in the current stage's `Open questions` is presented to the user, who must pick one of three options:
   - **Answer now** → the answer is recorded under `Key decisions` of the stage file, and the question is cleared from `Open questions`.
   - **Defer with rationale** → user writes the condition that would unblock the question and why it cannot be answered now. The item stays in `Open questions` marked `(deferred until <condition>: <reason>)`.
   - **Cancel** → `/jstage` aborts and changes nothing.

   Claude never silently answers or defers on the user's behalf.

2. **Auto-review of the just-completed stage.** After the transition, `/jstage` spawns a review agent (via the `Agent` tool) with a stage-specific prompt — checking measurability of spec goals, justification of design decisions, code-review of impl changes, coverage of tests, etc. Findings are surfaced to the user verbatim or summarized. The user decides what to do with them; nothing is auto-fixed.

3. **Explicit confirmation before starting the new stage.** Even with a clean review, `/jstage` does not begin work in the new stage in the same turn as the transition. It asks: «start now / address review findings first / pause». Starting work is a separate, user-initiated step. When the new stage is `impl`, the confirmation also reminds about the `03-impl.md` work-log discipline.

Result: by the time you're in a new stage, every prior decision is either explicitly made or explicitly parked with a known unblock condition, a second pair of eyes has audited the work you just finished, and you've consciously chosen to start the next phase. `/jnext` reinforces this — it acts on exactly one item per call and refuses to perform stage transitions itself.

---

## Statusline and context monitoring

The bundled `statusline.sh` shows:

```
Opus  |  main  |  ctx:42%  |  $0.55
Opus  |  main  |  ctx:65%  |  $1.10   /jhandoff soon
Opus  |  main  |  ctx:82%  |  $3.40   /jhandoff
```

It also writes the current context percentage to a per-project bridge file at `/tmp/jflow-ctx-<hash>.json`, which the `Stop` hook reads to gently nudge you to checkpoint when crossing 60% and 75% thresholds. The nudge fires only **once per threshold crossing**, not on every Stop.

---

## File layout (after installation)

```
<project>/
└── .claude/
    ├── settings.json                    # hooks + statusline config (merged if existed)
    ├── current-task                     # one-line: active task ID
    ├── scripts/
    │   ├── _lib.sh                      # cross-platform helpers (OS detect, hash, ISO dates)
    │   ├── statusline.sh                # statusline + bridge file writer
    │   ├── stop-monitor.sh              # throttled threshold warnings
    │   ├── session-end-snapshot.sh      # auto-dump on session end
    │   └── session-start-restore.sh     # state restore on session start
    ├── skills/
    │   ├── jnew/SKILL.md
    │   ├── jstage/SKILL.md
    │   ├── jstep/SKILL.md
    │   ├── jphase/SKILL.md
    │   ├── jstatus/SKILL.md
    │   ├── jhandoff/SKILL.md
    │   ├── jnext/SKILL.md
    │   ├── jdeps/SKILL.md
    │   └── _templates/                  # stage templates
    └── tasks/
        └── <task-id>/
            ├── 00-spec.md
            ├── 01-design.md
            ├── 02-plan.md
            ├── 03-impl.md
            ├── 04-test.md
            ├── 05-release.md
            ├── state.md                 # current task state
            ├── deps.md                  # task dependencies
            └── events.jsonl             # append-only event log
```

---

## Updating

Re-run the installer over an existing installation. It is idempotent:

```bash
curl -fsSL https://raw.githubusercontent.com/juggle73/jflow/main/install.sh | bash
```

- Scripts and skills are overwritten with the new versions.
- `settings.json` is merged (existing user hooks preserved, jflow hooks deduplicated).
- `tasks/` is never touched.

---

## Design notes

- **Bridge file isolation.** Parallel Claude Code sessions in different projects do not conflict because the bridge file path includes a hash of `$CLAUDE_PROJECT_DIR`.
- **Why we don't auto-run `/clear`.** `/clear` is a CLI-level command interpreted before reaching Claude. A skill cannot inject it. `/jhandoff` saves state and tells you it's safe to type `/clear` yourself — one keystroke, and you keep an explicit confirmation that the save happened.
- **Hooks are quiet by default.** The `Stop` hook only prints when crossing 60% or 75% context thresholds, and only once per crossing. No noise during normal work.
- **No external services.** Everything runs locally. No network calls outside the optional remote installer.

---

## License

MIT.
