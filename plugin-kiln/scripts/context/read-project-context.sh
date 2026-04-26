#!/usr/bin/env bash
# read-project-context.sh — emit a deterministic ProjectContextSnapshot JSON.
#
# FR-001 (shared project-context reader), FR-002 (defensive / missing-dir-safe),
# FR-003 / NFR-002 (deterministic byte-identical output on unchanged state),
# NFR-001 (<2 s on 50-PRD + 100-item repo), NFR-006 (never called from hooks).
#
# Contract: specs/coach-driven-capture-ergonomics/contracts/interfaces.md
#   → Module: plugin-kiln/scripts/context/ → read-project-context.sh
#
# Usage:
#   bash read-project-context.sh [--repo-root <path>]
#
# Exit codes:
#   0 — success, JSON on stdout
#   2 — usage error (unknown flag)
#   3 — unrecoverable scan error (jq missing, etc.)
set -euo pipefail
export LC_ALL=C   # deterministic sort across macOS + Linux (NFR-002)

# ---- argv ----
REPO_ROOT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo-root)
      REPO_ROOT="${2:-}"
      shift 2
      ;;
    -h|--help)
      sed -n '2,16p' "$0"
      exit 0
      ;;
    *)
      echo "read-project-context.sh: unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

if [[ -z "$REPO_ROOT" ]]; then
  if REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"; then
    :  # got it
  else
    REPO_ROOT="$PWD"
  fi
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "read-project-context.sh: jq is required but not found in PATH" >&2
  exit 3
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
H_READ_PRDS="$SCRIPT_DIR/read-prds.sh"
H_READ_PLUGINS="$SCRIPT_DIR/read-plugins.sh"

# ---- prds[] and plugins[] via helper sub-scripts ----
PRDS_JSON="$(bash "$H_READ_PRDS" "$REPO_ROOT")"
PLUGINS_JSON="$(bash "$H_READ_PLUGINS" "$REPO_ROOT")"

# ---- roadmap_items[] ----
# Single-pass optimization: emit one TSV line per item (path \t id \t kind \t
# state \t phase \t addresses-pipe-joined), then fold into JSON with a single
# jq -R -s call. Avoids O(N) jq spawns (NFR-001).
ITEMS_DIR="$REPO_ROOT/.kiln/roadmap/items"
ITEMS_JSON="[]"
if [[ -d "$ITEMS_DIR" ]]; then
  shopt -s nullglob
  ITEM_FILES=( "$ITEMS_DIR"/*.md )
  shopt -u nullglob
  # Sort ASC by path (NFR-002).
  IFS=$'\n' ITEM_FILES=($(printf '%s\n' "${ITEM_FILES[@]}" | sort))
  unset IFS

  if [[ "${#ITEM_FILES[@]}" -gt 0 ]]; then
    # awk processes every file; emits one TSV per item.
    # Fields: rel-path, id, kind, state, phase, addresses (pipe-joined).
    # Repo-root prefix stripped here for portability.
    ITEM_TSV="$(awk -v ROOT="$REPO_ROOT/" '
      BEGIN { FS="\n" }
      function reset() {
        id=""; kind=""; state=""; phase=""
        delete addrs; na=0
        in_fm=0; seen_open=0; in_addrs=0
      }
      function emit() {
        rel = FILENAME
        # strip repo-root prefix
        sub("^" ROOT, "", rel)
        joined = ""
        for (i=1; i<=na; i++) {
          joined = joined (i>1 ? "|" : "") addrs[i]
        }
        print rel "\t" id "\t" kind "\t" state "\t" phase "\t" joined
      }
      FNR == 1 { if (file_cnt++) emit(); reset() }
      {
        # Frontmatter framing.
        if ($0 ~ /^---[[:space:]]*$/) {
          if (!seen_open) { seen_open = 1; in_fm = 1; next }
          else if (in_fm) { in_fm = 0; next }
        }
        if (!in_fm) next

        # Scalar keys we care about.
        if ($0 ~ /^(id|kind|state|phase):[[:space:]]/) {
          in_addrs = 0
          line = $0
          key = line
          sub(/:.*$/, "", key)
          val = line
          sub(/^[^:]*:[[:space:]]*/, "", val)
          gsub(/^["\x27]|["\x27][[:space:]]*$/, "", val)
          sub(/[[:space:]]+$/, "", val)
          if (key == "id")    id    = val
          if (key == "kind")  kind  = val
          if (key == "state") state = val
          if (key == "phase") phase = val
          next
        }

        # addresses inline: `addresses: [a, b]`
        if ($0 ~ /^addresses:[[:space:]]*\[/) {
          in_addrs = 0
          line = $0
          sub(/^addresses:[[:space:]]*\[/, "", line)
          sub(/\][[:space:]]*$/, "", line)
          n = split(line, parts, /[[:space:]]*,[[:space:]]*/)
          for (i = 1; i <= n; i++) {
            gsub(/^["\x27]|["\x27]$/, "", parts[i])
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", parts[i])
            if (length(parts[i]) > 0) { na++; addrs[na] = parts[i] }
          }
          next
        }

        # addresses block start: `addresses:` then `- id` lines.
        if ($0 ~ /^addresses:[[:space:]]*$/) { in_addrs = 1; next }
        if (in_addrs && $0 ~ /^[[:space:]]*-[[:space:]]+/) {
          line = $0
          sub(/^[[:space:]]*-[[:space:]]+/, "", line)
          gsub(/^["\x27]|["\x27]$/, "", line)
          sub(/[[:space:]]+$/, "", line)
          na++; addrs[na] = line
          next
        }
        if (in_addrs && $0 ~ /^[^[:space:]]/) { in_addrs = 0 }
      }
      END { if (file_cnt > 0) emit() }
    ' "${ITEM_FILES[@]}")"

    # Fold TSV into JSON array with a single jq invocation.
    ITEMS_JSON="$(printf '%s\n' "$ITEM_TSV" | jq -R -s '
      split("\n")
      | map(select(length > 0))
      | map(
          split("\t") as $f
          | {
              path:      $f[0],
              id:        $f[1],
              kind:      $f[2],
              state:     $f[3],
              phase:     (if $f[4] == "" then null else $f[4] end),
              addresses: (if $f[5] == "" then [] else ($f[5] | split("|")) end)
            }
        )
    ')"
  fi
fi

# ---- roadmap_phases[] ----
PHASES_DIR="$REPO_ROOT/.kiln/roadmap/phases"
PHASES_JSON="[]"
if [[ -d "$PHASES_DIR" ]]; then
  shopt -s nullglob
  PHASE_FILES=( "$PHASES_DIR"/*.md )
  shopt -u nullglob

  declare -a PHASE_ENTRIES=()
  for abs in "${PHASE_FILES[@]}"; do
    [[ -f "$abs" ]] || continue

    # Parse frontmatter keys: name, status, started, completed.
    PFM="$(awk '
      BEGIN { in_fm = 0; seen_open = 0 }
      /^---[[:space:]]*$/ {
        if (!seen_open) { seen_open = 1; in_fm = 1; next }
        else { exit }
      }
      in_fm {
        if ($0 ~ /^(name|status|started|completed):[[:space:]]/) {
          line = $0
          key = line
          sub(/:.*$/, "", key)
          val = line
          sub(/^[^:]*:[[:space:]]*/, "", val)
          gsub(/^["\x27]|["\x27][[:space:]]*$/, "", val)
          sub(/[[:space:]]+$/, "", val)
          print key "\t" val
        }
      }
    ' "$abs" 2>/dev/null || true)"

    name=""; status=""; started=""; completed=""
    while IFS=$'\t' read -r k v; do
      [[ -z "$k" ]] && continue
      case "$k" in
        name)      name="$v" ;;
        status)    status="$v" ;;
        started)   started="$v" ;;
        completed) completed="$v" ;;
      esac
    done <<< "$PFM"

    # Fallback name from filename.
    [[ -z "$name" ]] && name="$(basename "$abs" .md)"

    entry="$(jq -n \
      --arg name      "$name" \
      --arg status    "$status" \
      --arg started   "$started" \
      --arg completed "$completed" \
      '{
         name:      $name,
         status:    $status,
         started:   (if $started   == "" or $started   == "null" then null else $started   end),
         completed: (if $completed == "" or $completed == "null" then null else $completed end)
       }')"
    PHASE_ENTRIES+=("$entry")
  done

  if [[ "${#PHASE_ENTRIES[@]}" -gt 0 ]]; then
    # Sort ASC by name (NFR-002).
    PHASES_JSON="$(printf '%s\n' "${PHASE_ENTRIES[@]}" | jq -s 'sort_by(.name)')"
  fi
fi

# ---- vision ----
# Emit an object { path, frontmatter, body } or null when the file is absent.
VISION_FILE="$REPO_ROOT/.kiln/vision.md"
if [[ -f "$VISION_FILE" ]]; then
  v_body="$(awk '
    BEGIN { in_fm = 0; seen_open = 0; seen_close = 0; past_fm = 0 }
    /^---[[:space:]]*$/ {
      if (!seen_open)       { seen_open = 1; in_fm = 1; next }
      else if (in_fm)       { seen_close = 1; in_fm = 0; past_fm = 1; next }
    }
    # Lines after the frontmatter close are body.
    past_fm { print }
    # If there was no frontmatter at all, everything is body.
    !seen_open { print }
  ' "$VISION_FILE")"

  # Frontmatter key/value pairs (all top-level scalars, preserved).
  FM_JSON="$(awk '
    BEGIN { in_fm = 0; seen_open = 0 }
    /^---[[:space:]]*$/ {
      if (!seen_open) { seen_open = 1; in_fm = 1; next }
      else { exit }
    }
    in_fm && /^[A-Za-z_][A-Za-z0-9_]*:[[:space:]]/ {
      line = $0
      key = line
      sub(/:.*$/, "", key)
      val = line
      sub(/^[^:]*:[[:space:]]*/, "", val)
      gsub(/^["\x27]|["\x27][[:space:]]*$/, "", val)
      sub(/[[:space:]]+$/, "", val)
      print key "\t" val
    }
  ' "$VISION_FILE" 2>/dev/null || true)"

  # Build a jq object from key/value pairs.
  FM_ARGS=()
  FM_FILTER='.'
  FM_OBJ='{}'
  if [[ -n "$FM_JSON" ]]; then
    # Build the jq object via a sequence of --arg flags.
    TMP_JQ='{}'
    while IFS=$'\t' read -r k v; do
      [[ -z "$k" ]] && continue
      TMP_JQ="$(jq -n --arg k "$k" --arg v "$v" --argjson prev "$TMP_JQ" '$prev + {($k): $v}')"
    done <<< "$FM_JSON"
    FM_OBJ="$TMP_JQ"
  fi

  # NOTE: jq 1.7.1-apple's `--arg` and `-Rs` encoders have a bug — multi-byte
  # UTF-8 strings exceeding ~6.7KB emit raw newlines inside JSON string output
  # instead of escaped `\n`, producing unparseable JSON. Workaround: encode the
  # body to a JSON string via python3 first, then hand the pre-encoded value
  # to jq via `--argjson`. jq's `--argjson` re-emits already-valid JSON cleanly.
  V_BODY_JSON="$(printf '%s' "$v_body" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')"
  VISION_JSON="$(jq -n \
    --arg path "$(echo "$VISION_FILE" | sed "s|^$REPO_ROOT/||")" \
    --argjson frontmatter "$FM_OBJ" \
    --argjson body "$V_BODY_JSON" \
    '{ path: $path, frontmatter: $frontmatter, body: $body }')"
else
  VISION_JSON="null"
fi

# ---- claude_md + readme ----
read_full_md() {
  local abs="$1" rel="$2"
  if [[ ! -f "$abs" ]]; then
    echo "null"
    return
  fi
  # Encode body via python3 json.dumps to sidestep the jq 1.7.1-apple
  # `--arg`/`-Rs` UTF-8 + size encoder bug — see vision-emit comment above.
  local body_json
  body_json="$(python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))' < "$abs")"
  jq -n --arg path "$rel" --argjson body "$body_json" '{ path: $path, body: $body }'
}

CLAUDE_MD_JSON="$(read_full_md "$REPO_ROOT/CLAUDE.md"  "CLAUDE.md")"
README_JSON="$(read_full_md   "$REPO_ROOT/README.md"   "README.md")"

# ---- Assemble final JSON ----
jq -n \
  --argjson prds           "$PRDS_JSON" \
  --argjson roadmap_items  "$ITEMS_JSON" \
  --argjson roadmap_phases "$PHASES_JSON" \
  --argjson vision         "$VISION_JSON" \
  --argjson claude_md      "$CLAUDE_MD_JSON" \
  --argjson readme         "$README_JSON" \
  --argjson plugins        "$PLUGINS_JSON" \
  '{
     schema_version: "1",
     prds:           $prds,
     roadmap_items:  $roadmap_items,
     roadmap_phases: $roadmap_phases,
     vision:         $vision,
     claude_md:      $claude_md,
     readme:         $readme,
     plugins:        $plugins
   }'
