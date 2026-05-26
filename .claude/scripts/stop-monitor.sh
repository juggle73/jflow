#!/usr/bin/env bash
# Stop hook: two independent checks, each fires at most once per "burst":
#   1) Context threshold (60% / 75%) — nudge toward /jhandoff before /clear.
#   2) Stale-state detector — if state.md hasn't been touched in N minutes
#      while a task is active, nudge to save progress.
#
# Both checks dedupe via marker files in /tmp.

set -euo pipefail

_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$_SCRIPT_DIR/_lib.sh"

cat > /dev/null 2>&1 || true

# Opt-out
if [ "${JFLOW_STRICT:-1}" = "0" ]; then
  exit 0
fi

cwd="$(jflow_project_dir)"
hash="$(jflow_hash "$cwd")"
bridge="$(jflow_bridge_path "$cwd")"

# --- Check 1: context threshold ---
if [ -f "$bridge" ]; then
  context_pct=$(jq -r '.context_percent // 0' "$bridge" 2>/dev/null || echo 0)
  ctx_int=${context_pct%.*}
  ctx_int=${ctx_int:-0}

  if [ "$ctx_int" -ge 75 ] 2>/dev/null; then
    current_level="critical"
  elif [ "$ctx_int" -ge 60 ] 2>/dev/null; then
    current_level="warning"
  else
    current_level="ok"
  fi

  if [ "$current_level" != "ok" ]; then
    warn_file="/tmp/jflow-last-warn-${hash}"
    last_level=""
    [ -f "$warn_file" ] && last_level=$(cat "$warn_file" 2>/dev/null || true)

    if [ "$current_level" != "$last_level" ]; then
      echo "$current_level" > "$warn_file"
      if [ "$current_level" = "warning" ]; then
        echo "Контекст: ${ctx_int}%. Запланируй /jhandoff в ближайшее время — он сохранит state и подготовит к /clear."
      elif [ "$current_level" = "critical" ]; then
        echo "Контекст: ${ctx_int}%. Критический уровень. Выполни /jhandoff сейчас, затем /clear и /jnext."
      fi
    fi
  fi
fi

# --- Check 2: stale state detector ---
# Fires when:
#   - there is an active task
#   - state.md hasn't been touched in >= STALE_THRESHOLD_MIN minutes
#   - we haven't already warned in this stale burst (cleared when state.md is re-saved)
STALE_THRESHOLD_MIN="${JFLOW_STALE_MIN:-30}"

task_file="$cwd/.claude/current-task"
[ ! -f "$task_file" ] && exit 0
task_id=$(cat "$task_file" 2>/dev/null | tr -d '[:space:]')
[ -z "$task_id" ] && exit 0

state_file="$cwd/.claude/tasks/$task_id/state.md"
[ ! -f "$state_file" ] && exit 0

now_epoch=$(date +%s)
case "$JFLOW_OS" in
  macos)  state_epoch=$(stat -f %m "$state_file" 2>/dev/null || echo "$now_epoch") ;;
  *)      state_epoch=$(stat -c %Y "$state_file" 2>/dev/null || echo "$now_epoch") ;;
esac

age_min=$(( (now_epoch - state_epoch) / 60 ))

if [ "$age_min" -lt "$STALE_THRESHOLD_MIN" ]; then
  exit 0
fi

# Dedup: only warn once per stale burst. Burst ends when state.md is touched again.
stale_marker="/tmp/jflow-stale-warn-${hash}"
if [ -f "$stale_marker" ]; then
  case "$JFLOW_OS" in
    macos)  marker_epoch=$(stat -f %m "$stale_marker" 2>/dev/null || echo 0) ;;
    *)      marker_epoch=$(stat -c %Y "$stale_marker" 2>/dev/null || echo 0) ;;
  esac
  # If marker is newer than the state save, we already warned in this burst.
  if [ "$marker_epoch" -gt "$state_epoch" ]; then
    exit 0
  fi
fi

# Touch marker (mtime = now) and emit.
: > "$stale_marker"

echo "jflow: задача '${task_id}' активна, но state.md не обновлялся ${age_min} минут. Если велась работа — выполни /jhandoff (или хотя бы /jstep), чтобы прогресс не потерялся при /clear или закрытии сессии."
