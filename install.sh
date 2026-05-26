#!/usr/bin/env bash
# Install jflow into a target project's .claude/ directory.
#
# Local usage (run from a checkout of the jflow repo):
#   ./install.sh [TARGET_DIR]
#
# Remote usage (one-liner, runs from any machine):
#   curl -fsSL https://raw.githubusercontent.com/juggle73/jflow/main/install.sh | bash
#   curl -fsSL https://raw.githubusercontent.com/juggle73/jflow/main/install.sh | bash -s -- /path/to/target
#
# To target a fork or branch, override via env vars:
#   curl -fsSL .../install.sh | JFLOW_REPO=myuser/jflow JFLOW_BRANCH=dev bash
#
# Behavior:
#   - Idempotent: re-running does not duplicate hooks in settings.json.
#   - Preserves existing .claude/tasks/ data and existing settings entries.
#   - Backs up settings.json before merging.
#   - Hybrid delivery: tries `git clone` first, falls back to tarball if no git.
#
# Requirements:
#   bash, jq, (git OR curl/wget), shasum or sha1sum.
#   Windows: run from Git Bash, WSL, or Cygwin.

set -euo pipefail

# ====== CONFIGURATION ======
# Override via JFLOW_REPO / JFLOW_BRANCH env vars to install from a fork.
JFLOW_REPO="${JFLOW_REPO:-juggle73/jflow}"
JFLOW_BRANCH="${JFLOW_BRANCH:-main}"
# ===========================

# Detect piped invocation (curl | bash): BASH_SOURCE[0] is empty.
# In that case do NOT pick up any local .claude/ — always go remote.
if [ -z "${BASH_SOURCE[0]:-}" ]; then
  PIPED=1
  SCRIPT_DIR=""
else
  PIPED=0
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || pwd)"
fi

color_red()   { printf '\033[31m%s\033[0m\n' "$1"; }
color_green() { printf '\033[32m%s\033[0m\n' "$1"; }
color_yel()   { printf '\033[33m%s\033[0m\n' "$1"; }
info()        { echo "  $1"; }
step()        { echo ""; echo "==> $1"; }

# Parse target dir from first positional arg (default: current dir).
TARGET="${1:-$(pwd)}"
TARGET="$(cd "$TARGET" 2>/dev/null && pwd)" || { color_red "Target dir '$1' does not exist"; exit 1; }
TARGET_CLAUDE="$TARGET/.claude"

# ====== DEPENDENCIES ======
step "Checking dependencies"
missing=()
for cmd in bash jq; do
  command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
done
if ! command -v shasum >/dev/null 2>&1 && ! command -v sha1sum >/dev/null 2>&1; then
  missing+=("shasum-or-sha1sum")
fi
if ! command -v git >/dev/null 2>&1 \
  && ! command -v curl >/dev/null 2>&1 \
  && ! command -v wget >/dev/null 2>&1; then
  missing+=("git-or-curl-or-wget")
fi
if [ ${#missing[@]} -gt 0 ]; then
  color_red "Missing dependencies: ${missing[*]}"
  echo "Install them via your package manager and retry."
  exit 1
fi

case "$(uname -s 2>/dev/null)" in
  Darwin*)              OS_LABEL="macOS" ;;
  Linux*)               OS_LABEL="Linux" ;;
  MINGW*|MSYS*|CYGWIN*) OS_LABEL="Windows (POSIX shell)" ;;
  *)                    OS_LABEL="unknown" ;;
esac
info "OS: $OS_LABEL"

# ====== SOURCE RESOLUTION ======
if [ "$PIPED" -eq 1 ] || [ -z "$SCRIPT_DIR" ]; then
  SOURCE_DIR=""
else
  SOURCE_DIR="$SCRIPT_DIR/.claude"
fi
REMOTE_TMP=""
cleanup() { [ -n "$REMOTE_TMP" ] && [ -d "$REMOTE_TMP" ] && rm -rf "$REMOTE_TMP"; }
trap cleanup EXIT

if [ -z "$SOURCE_DIR" ] || [ ! -d "$SOURCE_DIR" ]; then
  step "No local .claude/ source — running in REMOTE mode"
  info "Repo: $JFLOW_REPO (branch: $JFLOW_BRANCH)"

  REMOTE_TMP="$(mktemp -d)"
  fetched=0

  if command -v git >/dev/null 2>&1; then
    info "Trying git clone https://github.com/${JFLOW_REPO}.git (branch: ${JFLOW_BRANCH})"
    if git clone --depth 1 --branch "$JFLOW_BRANCH" \
        "https://github.com/${JFLOW_REPO}.git" "$REMOTE_TMP/repo" >/dev/null 2>&1; then
      SOURCE_DIR="$REMOTE_TMP/repo/.claude"
      fetched=1
      info "Cloned via git."
    else
      color_yel "  git clone failed, falling back to tarball."
    fi
  fi

  if [ "$fetched" -eq 0 ]; then
    tarball_url="https://github.com/${JFLOW_REPO}/archive/refs/heads/${JFLOW_BRANCH}.tar.gz"
    info "Downloading tarball: $tarball_url"
    mkdir -p "$REMOTE_TMP/repo"
    if command -v curl >/dev/null 2>&1; then
      curl -fsSL "$tarball_url" | tar -xz -C "$REMOTE_TMP/repo" --strip-components=1
    elif command -v wget >/dev/null 2>&1; then
      wget -qO- "$tarball_url" | tar -xz -C "$REMOTE_TMP/repo" --strip-components=1
    else
      color_red "Need git, curl, or wget to fetch sources."
      exit 1
    fi
    SOURCE_DIR="$REMOTE_TMP/repo/.claude"
    if [ ! -d "$SOURCE_DIR" ]; then
      color_red "Tarball did not contain .claude/ — check JFLOW_REPO and JFLOW_BRANCH."
      exit 1
    fi
    info "Tarball extracted."
  fi
else
  info "Source: $SOURCE_DIR (local)"
fi

# ====== VALIDATE SOURCE ======
step "Validating source"
for required in scripts/_lib.sh scripts/statusline.sh skills/_templates/state.md settings.json; do
  if [ ! -f "$SOURCE_DIR/$required" ]; then
    color_red "Missing source file: $SOURCE_DIR/$required"
    exit 1
  fi
done
info "Source OK"

# ====== INSTALL ======
step "Installing into $TARGET_CLAUDE"
mkdir -p "$TARGET_CLAUDE/scripts" "$TARGET_CLAUDE/skills" "$TARGET_CLAUDE/tasks"

info "Copying scripts..."
cp "$SOURCE_DIR/scripts/"*.sh "$TARGET_CLAUDE/scripts/"
chmod +x "$TARGET_CLAUDE/scripts/"*.sh

info "Copying skills..."
cp -R "$SOURCE_DIR/skills/." "$TARGET_CLAUDE/skills/"

# ====== SETTINGS MERGE ======
step "Configuring settings.json"
SRC_SETTINGS="$SOURCE_DIR/settings.json"
DST_SETTINGS="$TARGET_CLAUDE/settings.json"

if [ ! -f "$DST_SETTINGS" ]; then
  info "No existing settings.json — copying new one"
  cp "$SRC_SETTINGS" "$DST_SETTINGS"
else
  if ! jq empty "$DST_SETTINGS" >/dev/null 2>&1; then
    color_red "Existing settings.json is not valid JSON: $DST_SETTINGS"
    echo "Fix it manually, then re-run install.sh."
    exit 1
  fi
  backup="${DST_SETTINGS}.bak.$(date +%s)"
  cp "$DST_SETTINGS" "$backup"
  info "Backed up existing settings to $(basename "$backup")"

  tmp="${DST_SETTINGS}.tmp.$$"
  jq --slurpfile new "$SRC_SETTINGS" '
    . as $orig | $new[0] as $n |
    def merge_hook(existing; entry):
      (existing // []) as $cur |
      if $cur | any(.hooks[]?.command == entry.hooks[0].command)
      then $cur
      else $cur + [entry] end;
    $orig
    | .statusLine = (.statusLine // $n.statusLine)
    | .hooks = (.hooks // {})
    | .hooks.Stop         = merge_hook(.hooks.Stop;         $n.hooks.Stop[0])
    | .hooks.SessionEnd   = merge_hook(.hooks.SessionEnd;   $n.hooks.SessionEnd[0])
    | .hooks.SessionStart = merge_hook(.hooks.SessionStart; $n.hooks.SessionStart[0])
  ' "$DST_SETTINGS" > "$tmp"
  mv "$tmp" "$DST_SETTINGS"
  info "Merged jflow hooks into existing settings.json (idempotent)"
fi

# ====== VERIFY ======
step "Verifying installation"
errors=0
for f in scripts/_lib.sh scripts/statusline.sh scripts/stop-monitor.sh \
         scripts/session-end-snapshot.sh scripts/session-start-restore.sh \
         settings.json skills/jnew/SKILL.md skills/_templates/state.md; do
  if [ ! -f "$TARGET_CLAUDE/$f" ]; then
    color_red "  MISSING: $f"
    errors=$((errors+1))
  fi
done
for s in "$TARGET_CLAUDE/scripts/"*.sh; do
  if [ ! -x "$s" ]; then
    color_red "  NOT EXECUTABLE: $s"
    errors=$((errors+1))
  fi
done
if [ "$errors" -ne 0 ]; then
  color_red "Installation has $errors error(s)."
  exit 1
fi
info "All files present and executable."

test_output=$(echo '{"context_window":{"used_percentage":10},"total_input_tokens":0,"total_output_tokens":0,"model":{"display_name":"test"},"workspace":{"current_dir":"'"$TARGET"'"},"total_cost_usd":0}' \
  | "$TARGET_CLAUDE/scripts/statusline.sh" 2>&1) || true
if echo "$test_output" | grep -q "ctx:"; then
  info "Smoke test: statusline OK"
else
  color_yel "  Warning: statusline smoke test produced unexpected output:"
  echo "    $test_output"
fi

echo ""
color_green "jflow installed to $TARGET_CLAUDE"
echo ""
echo "Next steps:"
echo "  1. Open Claude Code in $TARGET"
echo "  2. Run /jstatus — should report 'No tasks found'"
echo "  3. Run /jnew <task-id> to create your first task"
echo ""
echo "Commands: /jnew /jstage /jstep /jphase /jstatus /jhandoff /jnext /jdeps"
