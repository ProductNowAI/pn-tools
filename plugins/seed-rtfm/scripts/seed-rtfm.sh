#!/usr/bin/env bash
# Seed a first-pass RTFM for the current repo into ProductNow.
# Run from the target repo's root. State lives in .rtfm-seed/ (resumable; delete to start over).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_DIR="$(pwd)/.rtfm-seed"
BRIEFS_DIR="$STATE_DIR/briefs"
LOGS_DIR="$STATE_DIR/logs"
PLAN_FILE="$STATE_DIR/rtfm-plan.json"
MANIFEST="$STATE_DIR/manifest.jsonl"
PROMPTS_DIR="$SCRIPT_DIR/prompts"

PARALLEL=3
REVIEW=0
DRY_RUN=0
FORCE=0
AUDIENCE=""
BASE_SHA=""
# ProductNow MCP server name as registered in the Claude Code config that applies
# to the invocation directory (user scope or that directory's project scope) —
# the same config `claude` would use interactively there. Must be enabled and
# OAuth'd there; tool allowlists are derived from this name.
MCP_SERVER="productnow"

usage() {
  cat <<'EOF'
Usage: seed-rtfm.sh [options]   (run from the target repo's root)

Options:
  --review        Stop after the plan phase so a human can edit .rtfm-seed/rtfm-plan.json; rerun to continue
  --mcp-server S  ProductNow MCP server name in your Claude Code config (default productnow)
  --parallel N    Concurrent doc workers (default 3)
  --audience STR  Override the default audience statement in all prompts
  --dry-run       Everything except ProductNow writes; briefs land on disk for inspection
  --force         Generate the overview even if some docs are missing from the manifest
  --base-sha SHA  Commit to stamp as lastProcessedSha in the published registry —
                  set this to the commit the seed run actually documented if HEAD
                  has moved since (default: current HEAD)
  -h, --help      Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --review) REVIEW=1; shift ;;
    --mcp-server) MCP_SERVER="$2"; shift 2 ;;
    --parallel) PARALLEL="$2"; shift 2 ;;
    --audience) AUDIENCE="$2"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    --force) FORCE=1; shift ;;
    --base-sha) BASE_SHA="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

[[ "$PARALLEL" =~ ^[1-9][0-9]*$ ]] || { echo "ERROR: --parallel requires a positive integer, got: $PARALLEL" >&2; exit 1; }

for dep in claude jq; do
  command -v "$dep" >/dev/null || { echo "ERROR: '$dep' not found on PATH" >&2; exit 1; }
done

# Real runs need the MCP server registered in the Claude Code config that applies
# here (dry runs never call MCP). This catches a missing/typo'd name up front;
# auth/enable problems still surface in the plan phase log.
if [[ "$DRY_RUN" != 1 ]]; then
  claude mcp get "$MCP_SERVER" >/dev/null 2>&1 || {
    echo "ERROR: MCP server '$MCP_SERVER' is not registered/authenticated (or pass --mcp-server <name> if it's under a different name)." >&2
    echo "  OAuth: claude mcp add --transport http $MCP_SERVER <url>, then /mcp -> Authenticate" >&2
    echo "  Key:   claude plugin enable seed-rtfm, then paste your key from Settings -> MCP" >&2
    exit 1
  }
fi
mkdir -p "$BRIEFS_DIR" "$LOGS_DIR"

# The ambient Claude Code config loads EVERY registered server, and an agent has
# been observed calling a same-product tool on the WRONG server (e.g. staging
# instead of dev) — auto-denied in headless mode, which it then fatally spun on.
# Derive a single-server strict config from the ambient registration: identical
# name+URL reuses the cached OAuth grant, but only this server's tools are
# visible to agents. Dry runs get an empty server set (they never call MCP).
MCP_STRICT_CONFIG="$STATE_DIR/mcp-config.json"
if [[ "$DRY_RUN" == 1 ]]; then
  printf '{"mcpServers":{}}\n' > "$MCP_STRICT_CONFIG"
else
  MCP_URL="$(claude mcp get "$MCP_SERVER" 2>/dev/null | sed -n 's/^[[:space:]]*URL: //p' | head -1)"
  MCP_TYPE="$(claude mcp get "$MCP_SERVER" 2>/dev/null | sed -n 's/^[[:space:]]*Type: //p' | head -1)"
  [[ -n "$MCP_URL" && -n "$MCP_TYPE" ]] || {
    echo "ERROR: could not read URL/type for MCP server '$MCP_SERVER' from 'claude mcp get' (stdio servers are not supported)." >&2
    exit 1
  }
  jq -n --arg name "$MCP_SERVER" --arg type "$MCP_TYPE" --arg url "$MCP_URL" \
    '{mcpServers: {($name): {type: $type, url: $url}}}' > "$MCP_STRICT_CONFIG"
fi

MCP_TOOLS="mcp__${MCP_SERVER}__list_folders,mcp__${MCP_SERVER}__create_folder,mcp__${MCP_SERVER}__create_document,mcp__${MCP_SERVER}__get_document,mcp__${MCP_SERVER}__switch_document_chat_edit_mode,mcp__${MCP_SERVER}__post_document_chat_message"
ALLOWED_TOOLS="Read,Glob,Grep,Write,Bash(git log:*),Bash(ls:*)"
if [[ "$DRY_RUN" != 1 ]]; then
  ALLOWED_TOOLS="$ALLOWED_TOOLS,$MCP_TOOLS"
fi

# Reads a fully assembled prompt on stdin, runs claude headless, prints the final
# message text on stdout. The agent's event stream is written incrementally to
# the log (tail -f it for live detail), and a heartbeat line goes to stderr
# every 30s — a growing event count means the agent is alive and working, not
# stuck. Cached OAuth applies via the derived single-server strict config.
invoke_claude() {
  local log_name="$1"
  local log_file="$LOGS_DIR/$log_name.json"
  local prompt_file="$LOGS_DIR/$log_name.prompt.md"
  local pid started tick events
  # Slurp the assembled prompt to a file: a backgrounded (&) command gets its
  # stdin rebound to /dev/null, so the pipe must be handed over explicitly.
  # Keeping the file also preserves each phase's exact prompt for debugging.
  cat > "$prompt_file"
  claude -p \
    --mcp-config "$MCP_STRICT_CONFIG" \
    --strict-mcp-config \
    --allowedTools "$ALLOWED_TOOLS" \
    --output-format stream-json \
    --verbose \
    --max-turns 150 \
    < "$prompt_file" \
    > "$log_file" &
  pid=$!
  started=$SECONDS
  tick=0
  while kill -0 "$pid" 2>/dev/null; do
    sleep 5
    tick=$((tick + 1))
    if (( tick % 6 == 0 )); then
      events="$(wc -l < "$log_file" | tr -d ' ')"
      echo "  [$log_name] still running — $((SECONDS - started))s elapsed, $events agent events (tail -f $log_file)" >&2
    fi
  done
  wait "$pid" || true
  jq -r 'select(.type == "result") | .result // empty' "$log_file" 2>/dev/null
}

# Appends the shared runtime-parameter lines (audience override, dry-run flag).
emit_common_params() {
  [[ -n "$AUDIENCE" ]] && echo "AUDIENCE OVERRIDE: $AUDIENCE"
  [[ "$DRY_RUN" == 1 ]] && echo "DRY RUN: yes"
  return 0
}

# Extracts the bare-JSON output contract from an agent's final message.
# Tries the whole message first, then falls back to scanning line-by-line
# (tolerates stray code fences or a stray preamble line).
extract_json() {
  local text="$1"
  local whole
  whole="$(jq -ce 'select(.slug != null)' <<<"$text" 2>/dev/null)" && { echo "$whole"; return 0; }
  printf '%s\n' "$text" | sed 's/^```.*$//' | jq -Rc 'fromjson? | select(.slug? != null)' | tail -1
}

manifest_has_slug() {
  local slug="$1"
  [[ -f "$MANIFEST" ]] && jq -e --arg s "$slug" -s 'map(select(.slug == $s)) | length > 0' "$MANIFEST" >/dev/null
}

phase_plan() {
  if [[ -f "$PLAN_FILE" ]]; then
    echo "== Phase 0: plan exists at $PLAN_FILE — skipping"
    return 0
  fi
  echo "== Phase 0: planning (shallow survey + ProductNow folders)"
  rm -f "$STATE_DIR/.plan-reviewed"
  {
    cat "$PROMPTS_DIR/plan.md"
    echo
    echo "## Runtime parameters"
    echo "PLAN_PATH: $PLAN_FILE"
    emit_common_params
  } | invoke_claude plan || true
  [[ -f "$PLAN_FILE" ]] || { echo "ERROR: plan agent did not write $PLAN_FILE (see $LOGS_DIR/plan.json)" >&2; exit 1; }
  echo "== Phase 0: planned $(jq '.docs | length' "$PLAN_FILE") docs"
}

validate_plan() {
  jq -e '.docs | length >= 2' "$PLAN_FILE" >/dev/null \
    || { echo "ERROR: $PLAN_FILE is invalid or has fewer than 2 docs" >&2; exit 1; }
  [[ "$(jq '[.docs[] | select(.deferred == true)] | length' "$PLAN_FILE")" == 1 ]] \
    || { echo "ERROR: plan must contain exactly one deferred overview doc" >&2; exit 1; }
  jq -e '.docs | map(.slug) | length == (unique | length)' "$PLAN_FILE" >/dev/null \
    || { echo "ERROR: plan contains duplicate slugs" >&2; exit 1; }
}

# A plan or manifest produced under --dry-run contains DRY-RUN placeholders and
# must never drive a real run (create_document would receive a garbage folderId).
check_dry_run_state() {
  [[ "$DRY_RUN" == 1 ]] && return 0
  local poisoned=0
  jq -e '.rootFolderId == "DRY-RUN" or ([.docs[].folderId] | index("DRY-RUN") != null)' "$PLAN_FILE" >/dev/null && poisoned=1
  [[ -f "$MANIFEST" ]] && jq -e -s 'map(select(.documentId == "DRY-RUN")) | length > 0' "$MANIFEST" >/dev/null && poisoned=1
  if [[ "$poisoned" == 1 ]]; then
    echo "ERROR: .rtfm-seed/ state was generated under --dry-run (DRY-RUN placeholders present)." >&2
    echo "Delete $STATE_DIR to start a real run, or rerun with --dry-run." >&2
    exit 1
  fi
  return 0
}

# Runs one doc worker. Invoked by xargs via an exported function, so it must only
# rely on exported globals. Appends exactly one line to the manifest on success.
run_worker() {
  local slug="$1"
  if manifest_has_slug "$slug"; then
    echo "[$slug] already in manifest — skipping"
    return 0
  fi
  local assignment
  assignment="$(jq -c --arg s "$slug" '.docs[] | select(.slug == $s)' "$PLAN_FILE")"
  [[ -n "$assignment" ]] || { echo "[$slug] ERROR: slug not found in plan" >&2; return 1; }
  echo "[$slug] exploring + publishing…"
  local result
  result="$({
    cat "$PROMPTS_DIR/worker.md"
    echo
    echo "## Runtime parameters"
    echo "BRIEF_PATH: $BRIEFS_DIR/$slug.md"
    emit_common_params
    echo
    echo "## Your assignment"
    echo "$assignment"
    echo
    echo "## Full corpus plan (for lane discipline and related-doc slugs)"
    cat "$PLAN_FILE"
  } | invoke_claude "worker-$slug")"
  local entry
  entry="$(extract_json "$result")"
  [[ -n "$entry" ]] || { echo "[$slug] ERROR: no valid JSON contract in worker output (see $LOGS_DIR/worker-$slug.json)" >&2; return 1; }
  [[ "$(jq -r '.slug' <<<"$entry")" == "$slug" ]] \
    || { echo "[$slug] ERROR: worker returned contract for wrong slug (see $LOGS_DIR/worker-$slug.json)" >&2; return 1; }
  # Single-line O_APPEND write: atomic for concurrent workers at this size.
  printf '%s\n' "$entry" >> "$MANIFEST"
  echo "[$slug] done → $(jq -r '.url' <<<"$entry")"
}

phase_workers() {
  echo "== Phase 1: doc workers (parallel=$PARALLEL)"
  export -f run_worker invoke_claude extract_json manifest_has_slug emit_common_params
  export STATE_DIR BRIEFS_DIR LOGS_DIR PLAN_FILE MANIFEST PROMPTS_DIR ALLOWED_TOOLS AUDIENCE DRY_RUN MCP_STRICT_CONFIG
  # `|| true`: a failed worker must not abort the run — phase_verify reports gaps,
  # and rerunning the script retries only the missing slugs.
  jq -r '.docs[] | select(.deferred != true) | .slug' "$PLAN_FILE" \
    | xargs -P "$PARALLEL" -I{} bash -c 'set -euo pipefail; run_worker "$@"' _ {} || true
}

phase_overview() {
  local overview_slug
  overview_slug="$(jq -r '.docs[] | select(.deferred == true) | .slug' "$PLAN_FILE")"
  if manifest_has_slug "$overview_slug"; then
    echo "== Phase 2: overview already in manifest — skipping"
    return 0
  fi
  local expected published
  expected="$(jq '[.docs[] | select(.deferred != true)] | length' "$PLAN_FILE")"
  published="$(jq -s --arg s "$overview_slug" 'map(select(.slug != $s)) | length' "$MANIFEST" 2>/dev/null || echo 0)"
  if (( published < expected )) && [[ "$FORCE" != 1 ]]; then
    echo "ERROR: only $published/$expected docs published — rerun to fill gaps, or pass --force" >&2
    exit 1
  fi
  echo "== Phase 2: generating Start Here overview ($published child docs)"
  local result
  result="$({
    cat "$PROMPTS_DIR/overview.md"
    echo
    echo "## Runtime parameters"
    emit_common_params
    echo
    echo "## Corpus plan"
    cat "$PLAN_FILE"
    echo
    echo "## Manifest (one JSON line per published doc)"
    cat "$MANIFEST"
  } | invoke_claude overview)"
  local entry
  entry="$(extract_json "$result")"
  [[ -n "$entry" ]] || { echo "ERROR: no valid JSON contract in overview output (see $LOGS_DIR/overview.json)" >&2; exit 1; }
  [[ "$(jq -r '.slug' <<<"$entry")" == "$overview_slug" ]] \
    || { echo "ERROR: overview agent returned contract for wrong slug (see $LOGS_DIR/overview.json)" >&2; exit 1; }
  printf '%s\n' "$entry" >> "$MANIFEST"
  echo "== Phase 2: overview → $(jq -r '.url' <<<"$entry")"
}

# Builds the machine-readable corpus registry from the plan + manifest. This is
# what scheduled update runs read from ProductNow to find and maintain the
# corpus — .rtfm-seed/ itself is disposable scratch once the registry is published.
build_registry_json() {
  local head_sha
  head_sha="${BASE_SHA:-$(git rev-parse HEAD 2>/dev/null || echo unknown)}"
  jq -n \
    --slurpfile plan "$PLAN_FILE" \
    --slurpfile manifest <(jq -s . "$MANIFEST") \
    --arg sha "$head_sha" \
    --arg date "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '
    ($plan[0]) as $p | ($manifest[0]) as $m |
    ($m | map({key: .slug, value: .}) | from_entries) as $bySlug |
    {
      version: 1,
      repo: $p.repo,
      seededAt: $date,
      lastProcessedSha: $sha,
      rootFolderId: $p.rootFolderId,
      overviewSlug: ($p.docs[] | select(.deferred == true) | .slug),
      changelogDocumentId: "CHANGELOG_DOCUMENT_ID",
      docs: [$p.docs[] | . as $d | ($bySlug[$d.slug]) as $entry |
        {
          slug: $d.slug,
          title: $d.title,
          documentId: ($entry.documentId // null),
          url: ($entry.url // null),
          folderId: $d.folderId,
          scope: $d.scope,
          entryPoints: ($d.entryPoints // []),
          relatedSlugs: ($d.relatedSlugs // []),
          status: "active"
        }]
    }'
}

phase_registry() {
  if [[ "$DRY_RUN" == 1 ]]; then
    echo "== Phase 3: registry skipped (dry run)"
    return 0
  fi
  local receipt="$STATE_DIR/registry-receipt.json"
  if [[ -f "$receipt" ]]; then
    echo "== Phase 3: registry receipt exists — skipping"
    return 0
  fi
  echo "== Phase 3: publishing changelog + registry docs"
  local registry_json result entry
  registry_json="$(build_registry_json)"
  result="$({
    cat "$PROMPTS_DIR/registry.md"
    echo
    echo "## Runtime parameters"
    echo "ROOT FOLDER ID: $(jq -r '.rootFolderId' "$PLAN_FILE")"
    emit_common_params
    echo
    echo "## Registry JSON (publish verbatim after substituting CHANGELOG_DOCUMENT_ID)"
    echo '```json'
    echo "$registry_json"
    echo '```'
  } | invoke_claude registry)"
  entry="$(extract_json "$result")"
  [[ -n "$entry" ]] || { echo "ERROR: no valid JSON contract in registry output (see $LOGS_DIR/registry.json)" >&2; exit 1; }
  [[ "$(jq -r '.verified' <<<"$entry")" == "true" ]] \
    || { echo "ERROR: registry round-trip verification failed (see $LOGS_DIR/registry.json)" >&2; exit 1; }
  printf '%s\n' "$entry" > "$receipt"
  echo "== Phase 3: registry published → $(jq -r '.registryDocumentId' <<<"$entry")"
}

phase_verify() {
  echo "== Phase 4: verify"
  local missing
  missing="$(comm -23 \
    <(jq -r '.docs[].slug' "$PLAN_FILE" | sort) \
    <(jq -r '.slug' "$MANIFEST" 2>/dev/null | sort))"
  if [[ -n "$missing" ]]; then
    echo "MISSING (rerun ./seed-rtfm.sh to retry these):" >&2
    printf '  %s\n' $missing >&2
    exit 1
  fi
  echo "All $(jq '.docs | length' "$PLAN_FILE") docs published:"
  jq -r '"  \(.slug)\t\(.url)"' "$MANIFEST"
}

main() {
  phase_plan
  validate_plan
  check_dry_run_state
  if [[ "$REVIEW" == 1 ]] && ! [[ -f "$STATE_DIR/.plan-reviewed" ]]; then
    touch "$STATE_DIR/.plan-reviewed"
    echo
    echo "Plan written to $PLAN_FILE — review/edit it, then rerun this command to continue."
    exit 0
  fi
  phase_workers
  phase_overview
  phase_registry
  phase_verify
}

main
