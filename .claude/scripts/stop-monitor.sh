#!/usr/bin/env bash
set -euo pipefail

_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$_SCRIPT_DIR/_lib.sh"

cat > /dev/null 2>&1 || true

cwd="$(jflow_project_dir)"
hash="$(jflow_hash "$cwd")"
bridge="$(jflow_bridge_path "$cwd")"

[ ! -f "$bridge" ] && exit 0

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

[ "$current_level" = "ok" ] && exit 0

warn_file="/tmp/jflow-last-warn-${hash}"
last_level=""
[ -f "$warn_file" ] && last_level=$(cat "$warn_file" 2>/dev/null || true)

[ "$current_level" = "$last_level" ] && exit 0

echo "$current_level" > "$warn_file"

if [ "$current_level" = "warning" ]; then
  echo "Контекст: ${ctx_int}%. Запланируй /jhandoff в ближайшее время — он сохранит state и подготовит к /clear."
elif [ "$current_level" = "critical" ]; then
  echo "Контекст: ${ctx_int}%. Критический уровень. Выполни /jhandoff сейчас, затем /clear и /jnext."
fi
