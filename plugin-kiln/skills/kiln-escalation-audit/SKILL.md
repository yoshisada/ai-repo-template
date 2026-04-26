---
name: kiln-escalation-audit
description: Inventory pause events from .wheel/history/, git log (confirm-never-silent), and .kiln/logs/ over the last 30 days. Emits a markdown report at .kiln/logs/escalation-audit-<timestamp>.md. V1 inventory-only — no verdict tagging. Use as /kiln:kiln-escalation-audit.
---

# Kiln Escalation Audit — Inventory Pause Events (V1)

Walks the last 30 days of pause-event sources and dumps them to a single markdown report at `.kiln/logs/escalation-audit-<timestamp>.md`. Inventory only — V1 emits NO verdict tags. The maintainer reviews the inventory and decides which pauses were calibrated correctly.

Contracts:
- Skill metadata + record shape + ingestor specs + report shape — `specs/escalation-audit/contracts/interfaces.md` §C.1.
- Report idempotence — `## Events` section MUST be byte-identical between two runs on unchanged inputs (NFR-003). Sort key: `(timestamp ASC, source ASC, surface ASC)`.
- Verdict-tagging is intentionally deferred — see roadmap item `2026-04-24-escalation-audit` for the design conversation.

## User Input

```text
$ARGUMENTS
```

V1 takes NO flags. Future PRDs may add `--since`, `--source`, etc.; today the skill always inventories the last 30 days from all three sources. Any args are ignored (logged as a Notes row).

## Step 1 — Resolve report path and timestamp

```bash
# H1 timestamp (ISO-8601 UTC, second precision). Used in the report filename and H1.
NOW_ISO="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
NOW_FILE="$(date -u +%Y-%m-%dT%H-%M-%SZ)"   # file-safe (colons → hyphens)

mkdir -p .kiln/logs
REPORT_PATH=".kiln/logs/escalation-audit-${NOW_FILE}.md"
```

The H1 timestamp is the ONLY part of the report exempt from the NFR-003 byte-identical re-run invariant. Two runs at different wall-clock times produce different filenames + different H1s; the `## Events` body is byte-identical.

## Step 2 — Ingest sources (FR-012)

Each ingestor writes one TSV row per event to a per-source temp file. The TSV columns are EXACTLY:

```
timestamp<TAB>source<TAB>event_type<TAB>context<TAB>surface
```

`timestamp` is ISO-8601 UTC. `context` is collapsed to a single line (newlines → space) and clipped to 120 chars. The TSV is later normalized + sorted in Step 3.

```bash
SCRATCH="$(mktemp -d)"
trap 'rm -rf "$SCRATCH"' EXIT
WHEEL_TSV="$SCRATCH/wheel.tsv"
GIT_TSV="$SCRATCH/git.tsv"
HOOK_TSV="$SCRATCH/hook.tsv"
NOTES="$SCRATCH/notes.txt"
: > "$WHEEL_TSV" "$GIT_TSV" "$HOOK_TSV" "$NOTES"
```

### Step 2a — Wheel `awaiting_user_input` events (FR-012a, OQ-3)

Source: `.wheel/history/*.json` files modified within the last 30 days where `awaiting_user_input == true`. Surface: `workflow`. Timestamp source: JSON `started_at` (preferred) → `ended_at` (fallback) → file mtime (last resort, with a Notes row).

```bash
# FR-012a — wheel pause events. Empty-corpus-safe: missing dir → zero rows + a Notes row.
if [ -d ".wheel/history" ]; then
  while IFS= read -r -d '' f; do
    # jq pulls a record; emit nothing on parse failure.
    rec=$(jq -r '
      select(.awaiting_user_input == true) |
      [
        (.started_at // .ended_at // ""),
        "wheel",
        "awaiting_user_input",
        ((.workflow // "unknown") | tostring),
        "workflow"
      ] | @tsv
    ' "$f" 2>/dev/null) || continue
    [ -z "$rec" ] && continue
    # If timestamp is empty, fall back to file mtime + emit a Notes row.
    ts=$(printf '%s' "$rec" | awk -F'\t' '{print $1}')
    if [ -z "$ts" ]; then
      ts=$(date -u -r "$f" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
        || date -u -d "@$(stat -c %Y "$f" 2>/dev/null)" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
        || echo "1970-01-01T00:00:00Z")
      printf 'wheel: %s used file mtime fallback (no started_at/ended_at in JSON).\n' "$f" >> "$NOTES"
      rec=$(printf '%s\twheel\tawaiting_user_input\t%s\tworkflow\n' "$ts" \
        "$(jq -r '(.workflow // "unknown") | tostring' "$f" 2>/dev/null || echo unknown)")
    fi
    printf '%s\n' "$rec" >> "$WHEEL_TSV"
  done < <(find .wheel/history -name '*.json' -mtime -30 -print0 2>/dev/null)
else
  printf 'wheel: .wheel/history/ not found — zero events from this source.\n' >> "$NOTES"
fi
```

### Step 2b — git-log `confirm-never-silent` mentions (FR-012b)

Source: `git log --since="30 days ago" --grep='confirm-never-silent'`. Surface: `skill` (the skill that emitted the prompt is what landed in the commit). Timestamp source: git author date `%aI` (already ISO-8601).

```bash
# FR-012b — confirm-never-silent commit mentions in last 30 days.
if git rev-parse --git-dir >/dev/null 2>&1; then
  git log --since="30 days ago" --grep='confirm-never-silent' \
    --pretty=format:'%aI%x09%H%x09%s' 2>/dev/null \
    | while IFS=$'\t' read -r ts sha subj; do
        [ -z "$ts" ] && continue
        # Normalize +HH:MM offsets to Z for sort stability.
        ts_utc=$(date -u -d "$ts" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
          || python3 -c "import sys,datetime;print(datetime.datetime.fromisoformat(sys.argv[1].replace('Z','+00:00')).astimezone(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'))" "$ts" 2>/dev/null \
          || echo "$ts")
        ctx=$(printf '%s %s' "${sha:0:8}" "$subj" | tr '\n' ' ' | cut -c1-120)
        printf '%s\tconfirm-never-silent\tconfirm-never-silent\t%s\tskill\n' "$ts_utc" "$ctx" >> "$GIT_TSV"
      done
else
  printf 'confirm-never-silent: not inside a git repo — zero events from this source.\n' >> "$NOTES"
fi
```

### Step 2c — hook-block events grep'd from `.kiln/logs/` (FR-012c)

Source: `.kiln/logs/*.md` files modified within the last 30 days. Permissive regex matches lines starting with `BLOCKED`, `hook-block`, or `require-spec.sh blocked`. Surface: `hook`. Timestamp source: filename embedded date (`escalation-audit-YYYY-MM-DD*` style), else file mtime (with a Notes row).

```bash
# FR-012c — hook-block events from .kiln/logs/*.md
if [ -d ".kiln/logs" ]; then
  while IFS= read -r -d '' f; do
    # Try to lift a YYYY-MM-DD date from the filename for the timestamp.
    base=$(basename "$f")
    ts=""
    if [[ "$base" =~ ([0-9]{4}-[0-9]{2}-[0-9]{2}) ]]; then
      ts="${BASH_REMATCH[1]}T00:00:00Z"
    fi
    if [ -z "$ts" ]; then
      ts=$(date -u -r "$f" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
        || date -u -d "@$(stat -c %Y "$f" 2>/dev/null)" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
        || echo "1970-01-01T00:00:00Z")
      printf 'hook-block: %s used file mtime fallback (no date in filename).\n' "$f" >> "$NOTES"
    fi
    # Permissive regex; missing matches are silently ignored (no false positives).
    grep -hEo '^(BLOCKED|hook-block|require-spec\.sh blocked).*' "$f" 2>/dev/null \
      | while IFS= read -r line; do
          ctx=$(printf '%s' "$line" | tr '\n' ' ' | cut -c1-120)
          # event_type = first whitespace-or-colon-delimited token, clipped.
          ev=$(printf '%s' "$line" | awk '{print $1}' | tr -d ':' | cut -c1-40)
          printf '%s\thook-block\t%s\t%s\thook\n' "$ts" "$ev" "$ctx" >> "$HOOK_TSV"
        done
  done < <(find .kiln/logs -maxdepth 1 -name '*.md' -mtime -30 -print0 2>/dev/null)
else
  printf 'hook-block: .kiln/logs/ not found — zero events from this source.\n' >> "$NOTES"
fi
```

## Step 3 — Sort + tally (FR-013, NFR-003)

Concat the three per-source TSVs, sort deterministically by `(timestamp ASC, source ASC, surface ASC)`, and count by source + by surface for the Summary section.

```bash
ALL_TSV="$SCRATCH/all.tsv"
cat "$WHEEL_TSV" "$GIT_TSV" "$HOOK_TSV" 2>/dev/null \
  | LC_ALL=C sort -t$'\t' -k1,1 -k2,2 -k5,5 -s > "$ALL_TSV"

TOTAL=$(wc -l < "$ALL_TSV" | tr -d ' ')
WHEEL_N=$(wc -l < "$WHEEL_TSV" | tr -d ' ')
GIT_N=$(wc -l < "$GIT_TSV" | tr -d ' ')
HOOK_N=$(wc -l < "$HOOK_TSV" | tr -d ' ')

# Surface tallies (column 5)
SKILL_N=$(awk -F'\t' '$5=="skill"{c++} END{print c+0}' "$ALL_TSV")
HOOKSURF_N=$(awk -F'\t' '$5=="hook"{c++} END{print c+0}' "$ALL_TSV")
WORKFLOW_N=$(awk -F'\t' '$5=="workflow"{c++} END{print c+0}' "$ALL_TSV")
```

`LC_ALL=C` + `sort -s` (stable) guarantees byte-identical re-run output for identical inputs (NFR-003). Ties on the sort key fall through stably in line-of-emission order from the per-source TSVs, which themselves emit in `find` order (deterministic on a given filesystem).

## Step 4 — Render report (FR-013, FR-014)

### Step 4a — Empty-corpus path

When `TOTAL == 0`, the body between H1 and `## Notes` is the EXACT string from the contract. No event rows; no per-source counts table.

```bash
if [ "$TOTAL" -eq 0 ]; then
  {
    printf '# Escalation Audit Report — %s\n\n' "$NOW_ISO"
    printf '## Summary\n\n'
    printf 'No pause events found in the last 30 days.\n\n'
    printf '## Events\n\n'
    printf '(none)\n\n'
    printf '## Notes\n\n'
    if [ -s "$NOTES" ]; then
      sed 's/^/- /' "$NOTES"
      printf '\n'
    fi
    printf '*Verdict-tagging deferred — see roadmap item 2026-04-24-escalation-audit for design context.*\n'
  } > "$REPORT_PATH"
  echo "$REPORT_PATH"
  exit 0
fi
```

### Step 4b — Non-empty corpus

```bash
{
  printf '# Escalation Audit Report — %s\n\n' "$NOW_ISO"

  # ----- ## Summary -----
  printf '## Summary\n\n'
  printf '| Source | Count |\n'
  printf '|--------|------:|\n'
  printf '| wheel  | %5d |\n' "$WHEEL_N"
  printf '| confirm-never-silent | %5d |\n' "$GIT_N"
  printf '| hook-block | %5d |\n' "$HOOK_N"
  printf '| **Total** | **%d** |\n\n' "$TOTAL"

  printf '| Surface | Count |\n'
  printf '|---------|------:|\n'
  printf '| skill    | %5d |\n' "$SKILL_N"
  printf '| hook     | %5d |\n' "$HOOKSURF_N"
  printf '| workflow | %5d |\n\n' "$WORKFLOW_N"

  # ----- ## Events -----
  printf '## Events\n\n'
  printf '| Timestamp (UTC) | Source | Event | Context | Surface |\n'
  printf '|---|---|---|---|---|\n'
  awk -F'\t' '{
    # Escape pipe + backslash chars in context to keep table well-formed.
    ctx=$4
    gsub(/\\/, "\\\\", ctx)
    gsub(/\|/, "\\|", ctx)
    printf "| %s | %s | %s | %s | %s |\n", $1, $2, $3, ctx, $5
  }' "$ALL_TSV"
  printf '\n'

  # ----- ## Notes -----
  printf '## Notes\n\n'
  # Per-source zero-count notes (FR-013).
  [ "$WHEEL_N" -eq 0 ] && printf -- '- wheel: zero events found in the last 30 days.\n'
  [ "$GIT_N" -eq 0 ]   && printf -- '- confirm-never-silent: zero events found in the last 30 days.\n'
  [ "$HOOK_N" -eq 0 ]  && printf -- '- hook-block: zero events found in the last 30 days.\n'
  # Ingestor diagnostic notes (mtime fallbacks, missing dirs, etc.).
  if [ -s "$NOTES" ]; then
    sed 's/^/- /' "$NOTES"
  fi
  printf '\n*Verdict-tagging deferred — see roadmap item 2026-04-24-escalation-audit for design context.*\n'
} > "$REPORT_PATH"

echo "$REPORT_PATH"
```

## Rules

- **NFR-003 (idempotent Events)** — the `## Events` table body MUST be byte-identical between two runs on unchanged inputs. The H1 timestamp and any timing-dependent `## Notes` rows (e.g., a new ingestion error) are exempt.
- **FR-014 (no verdict tags)** — V1 emits NO verdict tags. The literal verdict-deferred placeholder MUST always close the report.
- **FR-013 (empty-corpus path)** — when total event count is zero, the body between H1 and `## Notes` MUST be exactly the strings rendered above (Summary line + `(none)` Events). Do NOT fail.
- **No network calls** — every ingestor reads local state. No `gh` calls, no LLM calls.
- **No verdict-side-effects** — the skill writes ONLY the report file at `.kiln/logs/escalation-audit-<ts>.md`. It does not mutate `.wheel/history/`, `.kiln/logs/`, or any source.
- **Permissive grep on hook-block** — non-matching log lines are silently ignored (no false-positive events) per spec edge case.
- **OQ-3 timestamp normalization** — every emitted row carries an ISO-8601 UTC timestamp. mtime fallback is documented in `## Notes`.
