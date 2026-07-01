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

render() {
  local src="$1" dst="$2"
  mkdir -p "$(dirname "$dst")"
  sed \
    -e "s/__PROJECT__/$PROJECT/g" \
    -e "s/__PORT__/$PORT/g" \
    -e "s#__START_URL__#$START_URL#g" \
    "$src" > "$dst"
}

render "$SKILL_DIR/templates/scripts/launch-chrome.sh.tmpl" "$dst_script"
chmod +x "$dst_script"

render "$SKILL_DIR/templates/docs/chrome-mcp-setup.md.tmpl" "$dst_doc"

mkdir -p "$dst_probe_dir"
touch "$dst_probe_dir/.gitkeep"

echo "scaffolded: $dst_script"
echo "scaffolded: $dst_doc"
echo "created:    $dst_probe_dir/"
