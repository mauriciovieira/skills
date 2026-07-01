#!/usr/bin/env bash
# Scaffold Chrome DevTools MCP setup (launch script + usage doc) into a
# target project, for inspecting authenticated network traffic via CDP.
#
# Required env vars:
#   PROJECT     kebab-case slug - names the isolated Chrome profile dir
#               (~/.chrome-<PROJECT>-profile) and titles the doc
#   PORT        CDP remote-debugging port, e.g. 9222
#   START_URL   URL opened when the dedicated Chrome instance launches
#
# Optional:
#   TARGET_DIR  project root to scaffold into (default: .)
#   FORCE       1 to overwrite an existing launch-chrome.sh / chrome-mcp-setup.md
#
# Usage:
#   PROJECT=myapp PORT=9222 START_URL=https://app.example.com/login \
#     TARGET_DIR=. ~/.claude/skills/chrome-devtools-mcp/scripts/scaffold.sh

set -euo pipefail

require() {
  local var="$1"
  if [[ -z "${!var:-}" ]]; then
    echo "ERROR: required env var $var is empty" >&2
    exit 2
  fi
}

require PROJECT
require PORT
require START_URL

if ! [[ "$PROJECT" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]]; then
  echo "ERROR: PROJECT must be a kebab-case slug (lowercase letters, digits, hyphens), got: $PROJECT" >&2
  exit 2
fi

if ! [[ "$PORT" =~ ^[0-9]+$ ]] || (( PORT < 1 || PORT > 65535 )); then
  echo "ERROR: PORT must be a number between 1 and 65535, got: $PORT" >&2
  exit 2
fi

TARGET_DIR="${TARGET_DIR:-.}"
FORCE="${FORCE:-0}"
SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

dst_script="$TARGET_DIR/scripts/launch-chrome.sh"
dst_doc="$TARGET_DIR/docs/chrome-mcp-setup.md"
dst_probe_dir="$TARGET_DIR/scripts/probe"

if [[ "$FORCE" != "1" ]]; then
  for f in "$dst_script" "$dst_doc"; do
    if [[ -e "$f" ]]; then
      echo "ERROR: $f already exists (set FORCE=1 to overwrite)" >&2
      exit 3
    fi
  done
fi

# Escape a value for use as a sed replacement: backslash first (so later
# escapes aren't double-escaped), then & (sed expands unescaped & to the
# matched text). Pure bash substitution, so this never needs its own escaping.
escape_repl() {
  local s=$1
  s=${s//\\/\\\\}
  s=${s//&/\\&}
  printf '%s' "$s"
}

render() {
  local src="$1" dst="$2"
  mkdir -p "$(dirname "$dst")"
  # Delimiter is \x01 (unlikely in PROJECT/PORT/START_URL), not / or #, so a
  # URL or slug containing either can't break the sed command.
  local d=$'\x01'
  local project_esc port_esc url_esc
  project_esc=$(escape_repl "$PROJECT")
  port_esc=$(escape_repl "$PORT")
  url_esc=$(escape_repl "$START_URL")
  # Render to a temp file first and mv into place, so a failed sed (bad
  # template path, permission error) can never leave a truncated/empty file
  # at $dst.
  local tmp
  tmp=$(mktemp "${dst}.XXXXXX")
  # mktemp creates the file 0600; force the usual 644 before it replaces
  # $dst (not umask-derived - a fixed, predictable mode regardless of the
  # caller's umask). A later chmod +x (for the launch script) applies on
  # top of this, not on top of mktemp's restrictive mode.
  chmod 644 "$tmp"
  sed \
    -e "s${d}__PROJECT__${d}${project_esc}${d}g" \
    -e "s${d}__PORT__${d}${port_esc}${d}g" \
    -e "s${d}__START_URL__${d}${url_esc}${d}g" \
    "$src" > "$tmp"
  mv "$tmp" "$dst"
}

render "$SKILL_DIR/templates/scripts/launch-chrome.sh.tmpl" "$dst_script"
chmod +x "$dst_script"

render "$SKILL_DIR/templates/docs/chrome-mcp-setup.md.tmpl" "$dst_doc"

mkdir -p "$dst_probe_dir"
touch "$dst_probe_dir/.gitkeep"

echo "scaffolded: $dst_script"
echo "scaffolded: $dst_doc"
echo "created:    $dst_probe_dir/"
