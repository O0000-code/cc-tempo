#!/usr/bin/env bash
# cc-tempo uninstaller
# Removes the installed statusline scripts, the globally-linked CLI,
# and the /tmp runtime state. Does NOT edit ~/.claude/settings.json.

set -euo pipefail

CLAUDE_DIR="${CLAUDE_HOME:-$HOME/.claude}"

info() { printf '==> %s\n' "$*"; }

info "Removing $CLAUDE_DIR/statusline.sh and calc_active_time.py"
rm -f "$CLAUDE_DIR/statusline.sh" "$CLAUDE_DIR/calc_active_time.py"

if command -v npm >/dev/null 2>&1; then
  info "Unlinking claude-context-percentage CLI"
  npm uninstall -g claude-context-percentage 2>/dev/null || true
fi

info "Cleaning /tmp runtime state (statusline-time-*, statusline-spark-*)"
rm -f /tmp/statusline-time-* /tmp/statusline-spark-* 2>/dev/null || true

cat <<EOF

Done. Final step: remove the statusLine block from ~/.claude/settings.json
manually (this script will not edit your settings file).
EOF
