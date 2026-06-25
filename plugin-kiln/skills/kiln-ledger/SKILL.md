---
name: "kiln-ledger"
description: "Read-only history view of the precedent ledger. Lists mistake/fix/retro/friction entries; supports --kind, --tag, and --last N filters."
---

# Ledger — Precedent History View

List entries from the `.kiln/ledger/` store. **Read-only — never writes or mutates any file.**

```text
$ARGUMENTS
```

## Flag Parsing

Parse `$ARGUMENTS`:
- `--kind <value>` — filter to entries whose `kind` field matches (one of: `mistake`, `fix`, `retro`, `friction`)
- `--tag <value>` — filter to entries whose `tags[]` array contains the given value (exact match, e.g. `topic/hooks`)
- `--last <N>` — show only the N most-recent entries (by `ts` descending), default unlimited
- `--proposals` — show `.kiln/ledger/proposals/*.json` instead of main ledger entries
- No flags → show all entries, newest first

## Step 1: Check Ledger Exists

```bash
LEDGER_DIR=".kiln/ledger"
if [ ! -d "$LEDGER_DIR" ]; then
  echo "No ledger entries yet."
  echo "(Run /kiln:kiln-mistake to begin recording precedent.)"
  exit 0
fi

COUNT=$(find "$LEDGER_DIR" -maxdepth 1 -name "*.json" 2>/dev/null | wc -l | tr -d ' ')
if [ "$COUNT" -eq 0 ]; then
  echo "No ledger entries yet."
  echo "(Run /kiln:kiln-mistake to begin recording precedent.)"
  exit 0
fi
```

## Step 2: Load and Filter Entries

Parse `$ARGUMENTS` for flags, then load matching entries.

```bash
# --- parse flags ---
KIND_FILTER=""
TAG_FILTER=""
LAST_N=""
SHOW_PROPOSALS=false

ARGS="$ARGUMENTS"
while [ -n "$ARGS" ]; do
  TOKEN=$(echo "$ARGS" | awk '{print $1}')
  REST=$(echo "$ARGS" | cut -d' ' -f2-)
  [ "$TOKEN" = "$REST" ] && REST=""
  case "$TOKEN" in
    --kind)       KIND_FILTER=$(echo "$REST" | awk '{print $1}'); ARGS=$(echo "$REST" | cut -d' ' -f2-); [ "$ARGS" = "$KIND_FILTER" ] && ARGS="" ;;
    --tag)        TAG_FILTER=$(echo "$REST" | awk '{print $1}');  ARGS=$(echo "$REST" | cut -d' ' -f2-); [ "$ARGS" = "$TAG_FILTER" ] && ARGS="" ;;
    --last)       LAST_N=$(echo "$REST" | awk '{print $1}');       ARGS=$(echo "$REST" | cut -d' ' -f2-); [ "$ARGS" = "$LAST_N" ] && ARGS="" ;;
    --proposals)  SHOW_PROPOSALS=true; ARGS="$REST" ;;
    *)            ARGS="$REST" ;;
  esac
done

# --- pick source directory ---
if [ "$SHOW_PROPOSALS" = "true" ]; then
  SRC_DIR=".kiln/ledger/proposals"
  if [ ! -d "$SRC_DIR" ] || [ "$(find "$SRC_DIR" -maxdepth 1 -name "*.json" 2>/dev/null | wc -l | tr -d ' ')" -eq 0 ]; then
    echo "No ledger proposals yet."
    exit 0
  fi
else
  SRC_DIR=".kiln/ledger"
fi

# --- collect, filter, sort, limit ---
ENTRIES=$(find "$SRC_DIR" -maxdepth 1 -name "*.json" 2>/dev/null)

# build a temp file with tab-separated fields for sorting
TMPFILE=$(mktemp /tmp/kiln-ledger-XXXXXX.tsv)
trap 'rm -f "$TMPFILE"' EXIT

for f in $ENTRIES; do
  [ -f "$f" ] || continue
  ID=$(jq -r '.id // "unknown"' "$f" 2>/dev/null)
  KIND=$(jq -r '.kind // ""' "$f" 2>/dev/null)
  SUMMARY=$(jq -r '.summary // ""' "$f" 2>/dev/null)
  TAGS=$(jq -r '.tags // [] | join(",")' "$f" 2>/dev/null)
  TS=$(jq -r '.ts // ""' "$f" 2>/dev/null)
  DATE=$(echo "$TS" | cut -c1-10)

  # kind filter
  if [ -n "$KIND_FILTER" ] && [ "$KIND" != "$KIND_FILTER" ]; then
    continue
  fi

  # tag filter (substring match within comma-joined tags)
  if [ -n "$TAG_FILTER" ]; then
    echo "$TAGS" | grep -qF "$TAG_FILTER" || continue
  fi

  # printf, not `echo -e` — macOS system bash (3.2) prints a literal "-e" with echo -e.
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$TS" "$ID" "$KIND" "$SUMMARY" "$TAGS" "$DATE" >> "$TMPFILE"
done

# sort newest first
SORTED=$(sort -r "$TMPFILE")

# apply --last N
if [ -n "$LAST_N" ] && [ "$LAST_N" -gt 0 ] 2>/dev/null; then
  SORTED=$(echo "$SORTED" | head -n "$LAST_N")
fi

if [ -z "$SORTED" ]; then
  echo "No entries match the given filters."
  exit 0
fi

echo "$SORTED"  # hand off to rendering step
```

## Step 3: Render Table

Take the tab-separated rows produced in Step 2 and render a readable markdown table.

Format the table with these columns:

| id | kind | summary | tags | date |
|----|------|---------|------|------|

Rules:
- `id` — full entry id (e.g. `2026-06-24-wheel-env-leak`)
- `kind` — `mistake` / `fix` / `retro` / `friction`
- `summary` — truncate at 72 chars if longer; append `…`
- `tags` — comma-separated, wrap at 40 chars with `…` if needed
- `date` — ISO date portion of `ts` (YYYY-MM-DD)
- Sort: newest first (already sorted by Step 2)

After the table, print:

```
Total: <N> entries  (filters: kind=<KIND_FILTER or "any">, tag=<TAG_FILTER or "any">, last=<LAST_N or "all">)
```

If `--proposals` was set, prefix the section header with "## Ledger Proposals" instead of "## Ledger Entries".

## Step 4: Proposal Detail (--proposals only)

When `--proposals` is active, after the table also list the `target` field for each proposal so the reader can see which plugin file would be patched:

```
Proposal targets:
  <id> → <target>
  ...
```

## Constraints

- **Never write, delete, or modify any file.** This skill is purely a read surface.
- **Graceful on missing dir/files.** Use `2>/dev/null` on all find/jq calls.
- **jq required.** If `jq` is not available, print: `Error: jq is required for kiln-ledger. Install with: brew install jq` and exit.
- **Empty results are not errors.** Print a friendly message and exit 0.
