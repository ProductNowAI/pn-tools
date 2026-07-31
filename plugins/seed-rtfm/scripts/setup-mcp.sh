#!/usr/bin/env bash
# Registers ProductNow's MCP server once. Defaults to OAuth (the user runs
# /mcp -> Authenticate); if a key was pasted into this plugin's userConfig at
# install/enable time, registers with that key instead. Safe to run on every
# SessionStart: a no-op once the server is registered.
set -euo pipefail

SERVER_NAME="productnow"
SERVER_URL="https://api.productnow-prod.com/mcp"

if claude mcp get "$SERVER_NAME" >/dev/null 2>&1; then
  exit 0
fi

if [[ -z "${CLAUDE_PLUGIN_OPTION_MCP_KEY:-}" ]]; then
  echo "seed-rtfm: ProductNow MCP server not yet connected. Choose one:" >&2
  echo "  - OAuth (recommended for interactive use): claude mcp add --transport http $SERVER_NAME $SERVER_URL" >&2
  echo "    then run /mcp in this session and choose Authenticate." >&2
  echo "  - MCP key (for non-interactive/CI setups): claude plugin enable seed-rtfm" >&2
  echo "    and paste your key from Settings -> MCP in the ProductNow app when prompted." >&2
  exit 0
fi

claude mcp add --transport http "$SERVER_NAME" "$SERVER_URL" \
  --header "Authorization: Bearer ${CLAUDE_PLUGIN_OPTION_MCP_KEY}"
