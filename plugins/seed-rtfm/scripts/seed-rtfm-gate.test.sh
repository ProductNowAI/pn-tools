#!/usr/bin/env bash
# Tests scripts/seed-rtfm.sh's default MCP_SERVER value, help text, executability,
# and its preflight MCP-registration gate, against a stubbed `claude` binary.
#
# This replaces the coverage seed-rtfm-migration.test.sh used to provide for
# this script (minus its now-obsolete cross-repo byte-identity check against a
# legacy script in a different repo), and adds real coverage of the preflight
# gate itself, which previously had none.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$SCRIPT_DIR/seed-rtfm.sh"
STUB_DIR="$(mktemp -d)"
SCRATCH_DIR="$(mktemp -d)"
trap 'rm -rf "$STUB_DIR" "$SCRATCH_DIR"' EXIT

# Case 1: MCP_SERVER defaults to "productnow" (not "productnow-staging" or anything else).
if ! grep -q '^MCP_SERVER="productnow"$' "$TARGET"; then
  echo "FAIL: $TARGET does not default MCP_SERVER to \"productnow\"" >&2
  exit 1
fi
echo "PASS: MCP_SERVER defaults to \"productnow\""

# Case 2: --help/usage text's default mention says productnow, not productnow-staging.
if ! grep -q 'default productnow)' "$TARGET"; then
  echo "FAIL: $TARGET help text does not contain expected default (default productnow)" >&2
  exit 1
fi
if grep -q 'default productnow-staging)' "$TARGET"; then
  echo "FAIL: $TARGET help text still contains stale default (default productnow-staging)" >&2
  exit 1
fi
echo "PASS: usage text default mentions productnow, not productnow-staging"

# Case 3: seed-rtfm.sh is executable.
if [[ ! -x "$TARGET" ]]; then
  echo "FAIL: $TARGET is not executable" >&2
  exit 1
fi
echo "PASS: seed-rtfm.sh is executable"

# Case 4: preflight gate — with `claude mcp get` failing, a real (non-dry-run) invocation
# exits non-zero and stderr mentions both the OAuth path and the key path.
cat > "$STUB_DIR/claude" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "mcp" && "$2" == "get" ]]; then
  exit 1
fi
exit 0
EOF
chmod +x "$STUB_DIR/claude"
# jq is a real dependency check earlier in the script; let it resolve normally
# from the ambient PATH by appending rather than replacing.
set +e
OUTPUT="$(cd "$SCRATCH_DIR" && PATH="$STUB_DIR:$PATH" "$TARGET" 2>&1 1>/dev/null)"
STATUS=$?
set -e
if [[ "$STATUS" == 0 ]]; then
  echo "FAIL: seed-rtfm.sh exited 0 despite the MCP server not being registered" >&2
  echo "$OUTPUT" >&2
  exit 1
fi
if ! grep -q "claude mcp add --transport http" <<<"$OUTPUT"; then
  echo "FAIL: gate message doesn't mention the OAuth (claude mcp add) path" >&2
  echo "$OUTPUT" >&2
  exit 1
fi
if ! grep -q "claude plugin enable seed-rtfm" <<<"$OUTPUT"; then
  echo "FAIL: gate message doesn't mention the key (claude plugin enable) path" >&2
  echo "$OUTPUT" >&2
  exit 1
fi
echo "PASS: preflight gate exits non-zero and mentions both OAuth and key paths"
