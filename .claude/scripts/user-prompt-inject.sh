#!/usr/bin/env bash
# UserPromptSubmit hook: inject jflow context before every user message so
# Claude stays on the workflow even when the user types free-text instead
# of /j* commands.
#
# Behavior:
#   - If no active task → exit silently (no overhead).
#   - If JFLOW_STRICT=0 → exit silently (opt-out).
#   - If context >= 60% → compact one-liner (save tokens near compact).
#   - Otherwise → full reminder block.

set -euo pipefail

_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$_SCRIPT_DIR/_lib.sh"

# Drain stdin — Claude already has the user's prompt; we don't need to parse it.
cat > /dev/null 2>&1 || true

# Opt-out
if [ "${JFLOW_STRICT:-1}" = "0" ]; then
  exit 0
fi

cwd="$(jflow_project_dir)"
task_file="$cwd/.claude/current-task"

# No active task → nothing to inject.
[ ! -f "$task_file" ] && exit 0
task_id=$(cat "$task_file" 2>/dev/null | tr -d '[:space:]')
[ -z "$task_id" ] && exit 0

state_file="$cwd/.claude/tasks/$task_id/state.md"
[ ! -f "$state_file" ] && exit 0

# Extract stage and status from state.md.
stage=$(grep -m1 '^\*\*Stage:\*\*' "$state_file" 2>/dev/null | sed 's/\*\*Stage:\*\* //' | tr -d '[:space:]')
status=$(grep -m1 '^\*\*Status:\*\*' "$state_file" 2>/dev/null | sed 's/\*\*Status:\*\* //' | tr -d '[:space:]')
stage="${stage:-unknown}"
status="${status:-unknown}"

# Compute "minutes since last state save".
now_epoch=$(date +%s)
case "$JFLOW_OS" in
  macos)  state_epoch=$(stat -f %m "$state_file" 2>/dev/null || echo "$now_epoch") ;;
  *)      state_epoch=$(stat -c %Y "$state_file" 2>/dev/null || echo "$now_epoch") ;;
esac
state_age_min=$(( (now_epoch - state_epoch) / 60 ))

# Read bridge for context_percent.
bridge="$(jflow_bridge_path "$cwd")"
context_pct=0
if [ -f "$bridge" ]; then
  context_pct=$(jq -r '.context_percent // 0' "$bridge" 2>/dev/null || echo 0)
fi
ctx_int=${context_pct%.*}
ctx_int=${ctx_int:-0}

# Map stage to its file name (for the work-log reminder).
case "$stage" in
  spec)    stage_file="00-spec.md" ;;
  design)  stage_file="01-design.md" ;;
  plan)    stage_file="02-plan.md" ;;
  impl)    stage_file="03-impl.md" ;;
  test)    stage_file="04-test.md" ;;
  release) stage_file="05-release.md" ;;
  *)       stage_file="<stage>.md" ;;
esac

# Compact mode near context limit — save tokens.
if [ "$ctx_int" -ge 60 ] 2>/dev/null; then
  printf '[jflow: %s / %s | state saved %sm ago | /jhandoff soon]\n\n' \
    "$task_id" "$stage" "$state_age_min"
  exit 0
fi

# Full reminder block.
cat <<EOF
[jflow context: task=$task_id | stage=$stage | status=$status | state saved ${state_age_min}m ago]

You are working on a jflow-tracked task. Workflow reminders for the message below:
- This is the \`$stage\` stage. Keep \`.claude/tasks/$task_id/$stage_file\` updated cumulatively as work happens — do not leave it as a template.
- Stage transitions go through \`/jstage <new>\` (open-questions gate + auto-review). Never edit \`Stage:\` in state.md directly or skip ahead by writing the next stage's file.
- After finishing a meaningful chunk: suggest \`/jstep "<note>"\` to log it.
- Before \`/clear\` or session pause: run \`/jhandoff\` so the next session can resume cleanly.
- If the user implies a stage transition in their message, propose \`/jstage\` rather than performing it inline.

--- User message follows:
EOF
