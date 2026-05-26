#!/usr/bin/env bash
# Common helpers for jflow scripts. Source this from each script:
#   _SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#   . "$_SCRIPT_DIR/_lib.sh"

case "$(uname -s 2>/dev/null)" in
  Darwin*)              JFLOW_OS="macos" ;;
  Linux*)               JFLOW_OS="linux" ;;
  MINGW*|MSYS*|CYGWIN*) JFLOW_OS="windows" ;;
  *)                    JFLOW_OS="unknown" ;;
esac
export JFLOW_OS

# Short hash of an input string (8 hex chars). Used for /tmp bridge files.
jflow_hash() {
  local input="$1"
  if command -v shasum >/dev/null 2>&1; then
    printf '%s' "$input" | shasum | cut -c1-8
  elif command -v sha1sum >/dev/null 2>&1; then
    printf '%s' "$input" | sha1sum | cut -c1-8
  else
    printf '%s' "$input" | tr -c 'a-zA-Z0-9' '_' | cut -c1-8
  fi
}

# Current ISO-8601 UTC timestamp.
jflow_iso_now() {
  date -u +%Y-%m-%dT%H:%M:%SZ
}

# Convert an ISO-8601 timestamp (with optional fractional seconds and Z) to
# epoch seconds. Prints 0 on parse failure.
jflow_iso_to_epoch() {
  local iso="$1"
  [ -z "$iso" ] && { echo 0; return; }
  local clean="${iso%%.*}"
  clean="${clean%Z}"
  case "$JFLOW_OS" in
    macos)
      date -j -u -f "%Y-%m-%dT%H:%M:%S" "$clean" +%s 2>/dev/null || echo 0
      ;;
    *)
      # GNU date (Linux, Git Bash, WSL, Cygwin).
      date -u -d "$clean" +%s 2>/dev/null || echo 0
      ;;
  esac
}

# Resolve the project directory. Prefers $CLAUDE_PROJECT_DIR, falls back to cwd.
jflow_project_dir() {
  echo "${CLAUDE_PROJECT_DIR:-$(pwd)}"
}

# Bridge file path for a given project directory.
jflow_bridge_path() {
  local proj="$1"
  echo "/tmp/jflow-ctx-$(jflow_hash "$proj").json"
}
