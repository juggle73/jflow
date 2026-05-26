#!/usr/bin/env bash
set -euo pipefail

_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$_SCRIPT_DIR/_lib.sh"

cat > /dev/null 2>&1 || true

cwd="$(jflow_project_dir)"
task_file="$cwd/.claude/current-task"

[ ! -f "$task_file" ] && exit 0

task_id=$(cat "$task_file" 2>/dev/null || true)
[ -z "$task_id" ] && exit 0

state_file="$cwd/.claude/tasks/$task_id/state.md"
[ ! -f "$state_file" ] && exit 0

stage=$(grep -m1 '^\*\*Stage:\*\*' "$state_file" 2>/dev/null | sed 's/\*\*Stage:\*\* //' || echo "unknown")
status=$(grep -m1 '^\*\*Status:\*\*' "$state_file" 2>/dev/null | sed 's/\*\*Status:\*\* //' || echo "unknown")

extract_section() {
  local file="$1" section="$2" max_lines="${3:-0}"
  local in_section=0
  local lines=""
  while IFS= read -r line; do
    if echo "$line" | grep -q "^## ${section}$"; then
      in_section=1
      continue
    fi
    if [ "$in_section" -eq 1 ]; then
      if echo "$line" | grep -q "^## \|^---$"; then
        break
      fi
      [ -n "$line" ] && lines="${lines}${line}
"
    fi
  done < "$file"
  if [ "$max_lines" -gt 0 ] && [ -n "$lines" ]; then
    echo "$lines" | tail -n "$max_lines"
  else
    echo "$lines"
  fi
}

in_progress=$(extract_section "$state_file" "In progress" 5)
next_steps=$(extract_section "$state_file" "Next" 5)
context_resume=$(extract_section "$state_file" "Context for resume" 0)

output="## Активная задача: ${task_id}
Этап: ${stage} | Статус: ${status}"

if [ -n "$in_progress" ]; then
  output="${output}

В работе:
${in_progress}"
fi

if [ -n "$next_steps" ]; then
  output="${output}
Следующие шаги:
${next_steps}"
fi

if [ -n "$context_resume" ]; then
  output="${output}
Контекст для возобновления:
${context_resume}"
fi

output="${output}
Чтобы продолжить — /jnext. Сменить задачу — /jstatus и /jstage."

echo "$output"
