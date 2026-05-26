#!/usr/bin/env bash
set -euo pipefail

_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$_SCRIPT_DIR/_lib.sh"

input=$(cat 2>/dev/null || true)
[ -z "$input" ] && exit 0

context_pct=$(echo "$input" | jq -r '.context_window.used_percentage // 0' 2>/dev/null || echo 0)
total_in=$(echo "$input" | jq -r '.total_input_tokens // 0' 2>/dev/null || echo 0)
total_out=$(echo "$input" | jq -r '.total_output_tokens // 0' 2>/dev/null || echo 0)
model=$(echo "$input" | jq -r '.model.display_name // "unknown"' 2>/dev/null || echo "unknown")
cwd=$(echo "$input" | jq -r '.workspace.current_dir // ""' 2>/dev/null || echo "")
cost=$(echo "$input" | jq -r '.total_cost_usd // 0' 2>/dev/null || echo 0)

[ -z "$cwd" ] && cwd="$(jflow_project_dir)"

bridge="$(jflow_bridge_path "$cwd")"

cat > "$bridge" <<EOJSON
{"context_percent":${context_pct},"total_input_tokens":${total_in},"total_output_tokens":${total_out},"updated_at":"$(jflow_iso_now)"}
EOJSON

branch=$(git -C "$cwd" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "no-git")
cost_fmt=$(printf '$%.2f' "$cost" 2>/dev/null || echo '$0.00')

status="${model}  |  ${branch}  |  ctx:${context_pct}%  |  ${cost_fmt}"

ctx_int=${context_pct%.*}
ctx_int=${ctx_int:-0}

if [ "$ctx_int" -ge 75 ] 2>/dev/null; then
  status="${status}  ⚠️ /jhandoff"
elif [ "$ctx_int" -ge 60 ] 2>/dev/null; then
  status="${status}  🟡 /jhandoff soon"
fi

echo "$status"
