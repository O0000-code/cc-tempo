#!/usr/bin/env bash
# cc-tempo installer
# Copies the statusline scripts into ~/.claude/ and installs the
# claude-context-percentage CLI globally via npm.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${CLAUDE_HOME:-$HOME/.claude}"

info() { printf '==> %s\n' "$*"; }
fail() { printf 'error: %s\n' "$*" >&2; exit 1; }

info "Checking dependencies"
missing=()
for cmd in jq bc python3 node npm git; do
  command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
done
if (( ${#missing[@]} > 0 )); then
  fail "missing: ${missing[*]} — on macOS try: brew install jq bc node git"
fi

info "Installing scripts to $CLAUDE_DIR"
mkdir -p "$CLAUDE_DIR"
install -m 0755 "$SCRIPT_DIR/bin/statusline.sh"       "$CLAUDE_DIR/statusline.sh"
install -m 0755 "$SCRIPT_DIR/bin/calc_active_time.py" "$CLAUDE_DIR/calc_active_time.py"

info "Building and linking claude-context-percentage CLI"
(
  cd "$SCRIPT_DIR/tools/context-percentage"
  npm install
  npm run build
  npm install -g .
)

cat <<EOF

Done.

Add the following to ~/.claude/settings.json (merge with any existing keys):

  {
    "statusLine": {
      "type": "command",
      "command": "bash $CLAUDE_DIR/statusline.sh",
      "padding": 2
    }
  }

Or merge automatically with jq:

  jq '.statusLine = {"type":"command","command":"bash $CLAUDE_DIR/statusline.sh","padding":2}' \\
     ~/.claude/settings.json > /tmp/settings.json && mv /tmp/settings.json ~/.claude/settings.json

Restart Claude Code to activate the status line.
EOF
