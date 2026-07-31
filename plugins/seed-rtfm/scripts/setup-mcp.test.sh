#!/usr/bin/env bash
# Tests scripts/setup-mcp.sh's idempotency and argument-passing logic against a stubbed `claude` binary.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETUP_SCRIPT="$SCRIPT_DIR/setup-mcp.sh"
STUB_DIR="$(mktemp -d)"
CALLS_LOG="$STUB_DIR/calls.log"
trap 'rm -rf "$STUB_DIR"' EXIT

write_stub() {
  local get_exit="$1"
  cat > "$STUB_DIR/claude" <<EOF
#!/usr/bin/env bash
echo "\$@" >> "$CALLS_LOG"
if [[ "\$1" == "mcp" && "\$2" == "get" ]]; then
  exit $get_exit
fi
exit 0
EOF
  chmod +x "$STUB_DIR/claude"
}

# Case 1: server already registered (claude mcp get succeeds) -> setup-mcp.sh must not call `claude mcp add`.
write_stub 0
: > "$CALLS_LOG"
PATH="$STUB_DIR:$PATH" CLAUDE_PLUGIN_OPTION_MCP_KEY="test-key" "$SETUP_SCRIPT"
if grep -q "^mcp add" "$CALLS_LOG"; then
  echo "FAIL: setup-mcp.sh called 'claude mcp add' even though the server was already registered" >&2
  exit 1
fi
echo "PASS: no-op when already registered"

# Case 2: server not registered (claude mcp get fails) and key present -> must call `claude mcp add` with the key.
write_stub 1
: > "$CALLS_LOG"
PATH="$STUB_DIR:$PATH" CLAUDE_PLUGIN_OPTION_MCP_KEY="test-key" "$SETUP_SCRIPT"
if ! grep -q "^mcp add --transport http productnow https://api.productnow-prod.com/mcp --header Authorization: Bearer test-key$" "$CALLS_LOG"; then
  echo "FAIL: setup-mcp.sh did not call 'claude mcp add' with the expected arguments" >&2
  cat "$CALLS_LOG" >&2
  exit 1
fi
echo "PASS: registers with the captured key when missing"

# Case 3: server not registered and no key present -> must not call `claude mcp add`, must exit 0.
write_stub 1
: > "$CALLS_LOG"
PATH="$STUB_DIR:$PATH" "$SETUP_SCRIPT"
if grep -q "^mcp add" "$CALLS_LOG"; then
  echo "FAIL: setup-mcp.sh called 'claude mcp add' with no key present" >&2
  exit 1
fi
echo "PASS: no-op when no key is present yet"

# Case 4: server not registered and no key present -> printed message must mention BOTH auth paths.
write_stub 1
: > "$CALLS_LOG"
OUTPUT="$(PATH="$STUB_DIR:$PATH" "$SETUP_SCRIPT" 2>&1)"
if ! grep -q "claude mcp add --transport http productnow" <<<"$OUTPUT"; then
  echo "FAIL: no-key message doesn't mention the OAuth (claude mcp add) path" >&2
  echo "$OUTPUT" >&2
  exit 1
fi
if ! grep -q "claude plugin enable seed-rtfm" <<<"$OUTPUT"; then
  echo "FAIL: no-key message doesn't mention the key (claude plugin enable) path" >&2
  echo "$OUTPUT" >&2
  exit 1
fi
echo "PASS: no-key message mentions both OAuth and key paths"
