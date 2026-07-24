#!/usr/bin/env bash
set -euo pipefail

SOURCE="/Users/billy/Desktop/ProductNow/scripts/seed-rtfm/seed-rtfm.sh"
TARGET="$HOME/Desktop/pn-tools/plugins/seed-rtfm/scripts/seed-rtfm.sh"

if [[ ! -f "$TARGET" ]]; then
  echo "FAIL: $TARGET does not exist yet" >&2
  exit 1
fi

DIFF_LINES="$(diff "$SOURCE" "$TARGET" | grep -c '^[<>]' || true)"
if [[ "$DIFF_LINES" != "4" ]]; then
  echo "FAIL: expected exactly two changed lines (4 diff lines: two < two >), got $DIFF_LINES diff lines" >&2
  diff "$SOURCE" "$TARGET" >&2 || true
  exit 1
fi

if ! grep -q '^MCP_SERVER="productnow"$' "$TARGET"; then
  echo "FAIL: $TARGET does not default MCP_SERVER to \"productnow\"" >&2
  exit 1
fi

if ! grep -q 'default productnow)' "$TARGET"; then
  echo "FAIL: $TARGET help text does not contain updated default (default productnow)" >&2
  exit 1
fi

if grep -q 'default productnow-staging)' "$TARGET"; then
  echo "FAIL: $TARGET help text still contains stale default (default productnow-staging)" >&2
  exit 1
fi

if [[ ! -x "$TARGET" ]]; then
  echo "FAIL: $TARGET is not executable" >&2
  exit 1
fi

echo "PASS: migrated script matches source except for the two expected changes (MCP_SERVER default and help text), and is executable"
