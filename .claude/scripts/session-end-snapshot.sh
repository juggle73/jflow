#!/usr/bin/env bash
set -euo pipefail

_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$_SCRIPT_DIR/_lib.sh"

input=$(cat 2>/dev/null || true)
[ -z "$input" ] && exit 0

session_id=$(echo "$input" | jq -r '.session_id // "unknown"' 2>/dev/null || echo "unknown")
transcript_path=$(echo "$input" | jq -r '.transcript_path // ""' 2>/dev/null || echo "")
cwd=$(echo "$input" | jq -r '.cwd // ""' 2>/dev/null || echo "")
reason=$(echo "$input" | jq -r '.reason // "unknown"' 2>/dev/null || echo "unknown")

[ -z "$cwd" ] && cwd="$(jflow_project_dir)"

task_file="$cwd/.claude/current-task"
[ ! -f "$task_file" ] && exit 0

task_id=$(cat "$task_file" 2>/dev/null || true)
[ -z "$task_id" ] && exit 0

task_dir="$cwd/.claude/tasks/$task_id"
state_file="$task_dir/state.md"
events_file="$task_dir/events.jsonl"

[ ! -d "$task_dir" ] && exit 0

ts="$(jflow_iso_now)"

if [ -f "$state_file" ] && grep -q "Session ${session_id}" "$state_file" 2>/dev/null; then
  exit 0
fi

tool_summary=""
files_touched=""
duration=""
tokens=""

if [ -n "$transcript_path" ] && [ -f "$transcript_path" ]; then
  tool_summary=$(jq -r '
    [.[] | select(.type == "tool_use") | .name // "unknown"] |
    group_by(.) | map("\(.[0])×\(length)") | join(", ")
  ' "$transcript_path" 2>/dev/null || echo "n/a")

  files_touched=$(jq -r '
    [.[] | select(.type == "tool_use") |
     select(.name == "Read" or .name == "Write" or .name == "Edit") |
     .input.file_path // .input.path // empty] |
    unique | join(", ")
  ' "$transcript_path" 2>/dev/null || echo "n/a")

  first_ts=$(jq -r '[.[] | .timestamp // empty] | first // ""' "$transcript_path" 2>/dev/null || echo "")
  last_ts=$(jq -r '[.[] | .timestamp // empty] | last // ""' "$transcript_path" 2>/dev/null || echo "")
  if [ -n "$first_ts" ] && [ -n "$last_ts" ]; then
    start_epoch="$(jflow_iso_to_epoch "$first_ts")"
    end_epoch="$(jflow_iso_to_epoch "$last_ts")"
    if [ "$start_epoch" -gt 0 ] && [ "$end_epoch" -gt 0 ] 2>/dev/null; then
      dur_min=$(( (end_epoch - start_epoch) / 60 ))
      duration="${dur_min}m"
    fi
  fi

  last_usage=$(jq -r '[.[] | select(.usage) | .usage] | last // {}' "$transcript_path" 2>/dev/null || echo "{}")
  in_tok=$(echo "$last_usage" | jq -r '.input_tokens // "n/a"' 2>/dev/null || echo "n/a")
  out_tok=$(echo "$last_usage" | jq -r '.output_tokens // "n/a"' 2>/dev/null || echo "n/a")
  tokens="${in_tok}/${out_tok}"
fi

[ -z "$tool_summary" ] && tool_summary="n/a"
[ -z "$files_touched" ] && files_touched="n/a"
[ -z "$duration" ] && duration="n/a"
[ -z "$tokens" ] && tokens="n/a"

snapshot_block="
### Session ${session_id} ended at ${ts} (reason: ${reason})
- Tools used: ${tool_summary}
- Files touched: ${files_touched}
- Duration: ${duration}
- Tokens: ${tokens}"

if grep -q "## Auto-snapshot" "$state_file" 2>/dev/null; then
  echo "$snapshot_block" >> "$state_file"
else
  printf "\n---\n\n## Auto-snapshot\n%s\n" "$snapshot_block" >> "$state_file"
fi

echo "{\"ts\":\"${ts}\",\"type\":\"session_end\",\"task\":\"${task_id}\",\"reason\":\"${reason}\",\"session\":\"${session_id}\"}" >> "$events_file"
