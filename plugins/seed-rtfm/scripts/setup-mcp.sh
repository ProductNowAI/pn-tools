#!/usr/bin/env bash
# Registers ProductNow's MCP server once, using the key the user pasted into
# this plugin's userConfig at install/enable time. Safe to run on every
# SessionStart: a no-op once the server is registered.
set -euo pipefail

SERVER_NAME="productnow"
SERVER_URL="https://api.productnow-prod.com/mcp"

if claude mcp get "$SERVER_NAME" >/dev/null 2>&1; then
  exit 0
fi

if [[ -z "${CLAUDE_PLUGIN_OPTION_MCP_KEY:-}" ]]; then
  echo "seed-rtfm: no ProductNow MCP key captured yet. Run 'claude plugin enable seed-rtfm' to be prompted, or 'claude plugin uninstall seed-rtfm' and reinstall." >&2
  exit 0
fi

claude mcp add --transport http "$SERVER_NAME" "$SERVER_URL" \
  --header "Authorization: Bearer ${CLAUDE_PLUGIN_OPTION_MCP_KEY}"
