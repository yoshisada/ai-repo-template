# Interface Contracts: PRD `derived_from:` Frontmatter

These contracts are the **single source of truth** for implementation. The implementer MUST match these literal blocks, key orders, field names, and bash pseudocode verbatim. Any divergence is a contract bug — file an issue, do not silently rewrite.

---

## §1 — YAML frontmatter block shape (written by `/kiln:kiln-distill` Step 4)

### §1.1 Block skeleton (literal, 5 lines)

```yaml
---
derived_from:
  - <relative/path/from/repo-root.md>
  - <relative/path/from/repo-root.md>
distilled_date: <YYYY-MM-DD>
theme: <theme-slug>
---
```

Followed IMMEDIATELY (on the next line) by the existing PRD body beginning with `# Feature PRD: <Theme Name>`.

### §1.2 Key order (NON-NEGOTIABLE)

The three keys MUST appear in exactly this order inside the frontmatter block:

1. `derived_from:` — block sequence (list).
2. `distilled_date:` — scalar (UTC ISO-8601 date `YYYY-MM-DD`).
3. `theme:` — scalar (the slug portion of the PRD directory name, i.e. `<date>-<slug>` → `<slug>`).

Reordering, inserting other keys between them, or renaming any key is a contract violation. Future schema extensions MUST be added AFTER `theme:` (keeps existing readers stable).

### §1.3 `derived_from:` list-item format (NON-NEGOTIABLE)

Each list item is a YAML block-sequence entry on its own line:

```
  - <path>
```

Where `<path>` is:

- **Repo-relative**: beginning with `.kiln/feedback/` or `.kiln/issues/` (no leading `./`, no leading `/`).
- **Forward-slashed**: `/` as path separator regardless of host OS.
- **On-disk path at distill time**: the exact path under which the source file lived when distill ran. NOT the Obsidian path, NOT a GitHub URL, NOT a resolved symlink target.
- **Unquoted**: no surrounding `"` or `'` (paths in this project do not contain spaces or YAML-reserved characters; a future schema may revisit this).

Indentation is exactly two spaces before the `-`. The `- ` prefix is two chars (dash + space). Example:

```yaml
derived_from:
  - .kiln/feedback/2026-04-24-foo.md
  - .kiln/feedback/2026-04-24-bar.md
  - .kiln/issues/2026-04-24-baz.md
```

### §1.4 Sort order within `derived_from:` (determinism — NFR-003)

1. Feedback entries (`.kiln/feedback/*.md`) appear BEFORE issue entries (`.kiln/issues/*.md`). Mirrors FR-012 ordering in `/kiln:kiln-distill`.
2. Within each source-type group, entries are sorted by filename ASC (POSIX sort — byte-wise comparison; no locale-aware sort).

This ordering is the identity function on a second distill run against unchanged input — byte-identical output (NFR-003).

### §1.5 Empty list (hand-authored PRDs — Decision D3)

`derived_from: []` (inline empty-list form) is a valid frontmatter block. Hand-authored PRDs with no backlog origin MAY carry:

```yaml
---
derived_from: []
distilled_date: 2026-04-24
theme: some-slug
---
```

OR omit the frontmatter block entirely. Step 4b's frontmatter-path branch (contracts §2.3) checks `len(derived_from) > 0` and falls through to scan-fallback on an empty list — behaviorally identical to the no-frontmatter case.

### §1.6 FR-002 invariant (single-source-of-truth enforcement)

`/kiln:kiln-distill` Step 4 MUST render the frontmatter `derived_from:` list and the `### Source Issues` body table from the SAME in-memory array (Python-like pseudocode):

```python
source_items = feedback_items_sorted + issue_items_sorted   # ordering per §1.4
write_frontmatter(source_items)                              # §1.1 shape
write_source_issues_table(source_items)                      # same order
assert [item.path for item in source_items] == [row.path for row in parsed_table]
```

The assertion MUST be a hard abort (exit non-zero, clear error message) at write time — no partial PRD is emitted.

---

## §2 — Build-prd Step 4b reader extensions

### §2.1 `read_derived_from()` helper (bounded YAML frontmatter extractor)

Inserted at the top of Step 4b, immediately after the `PRD_PATH_NORM="$(normalize_path "$PRD_PATH")"` line (existing at `plugin-kiln/skills/kiln-build-prd/SKILL.md` ~line 622).

```bash
# read_derived_from <prd-path>
# Extracts the `derived_from:` list from the first YAML frontmatter block
# of the PRD. Emits one repo-relative path per line on stdout.
# Emits NOTHING (and returns 0) if:
#   - the PRD has no frontmatter block, OR
#   - the block has no `derived_from:` key, OR
#   - the list is empty (`derived_from: []` OR `derived_from:` with no child rows).
# Never exits non-zero — read failures degrade to "no entries" (Step 4b then falls to scan-fallback).
read_derived_from() {
  local prd="$1"
  [ -f "$prd" ] || { return 0; }
  awk '
    BEGIN { state = "before"; emit = 0 }
    # Close on the second --- (end of frontmatter block)
    state == "inside" && /^---[[:space:]]*$/ { exit 0 }
    # Open on the first --- (must be the first non-empty line)
    state == "before" && /^---[[:space:]]*$/ { state = "inside"; next }
    # Bail if the first non-empty line is not ---
    state == "before" && NF > 0 { exit 0 }
    # Inside the block
    state == "inside" {
      # Start of derived_from key (inline empty list or block-sequence header)
      if ($0 ~ /^derived_from:[[:space:]]*(\[\])?[[:space:]]*$/) {
        emit = 1
        next
      }
      # Any other top-level key closes the emit window
      if (emit == 1 && $0 ~ /^[A-Za-z_][A-Za-z0-9_]*:/) {
        emit = 0
        next
      }
      # Block-sequence entry under derived_from
      if (emit == 1 && $0 ~ /^[[:space:]]+-[[:space:]]+/) {
        # Strip the leading "  - " and any trailing CR/whitespace
        sub(/^[[:space:]]+-[[:space:]]+/, "", $0)
        sub(/[[:space:]]+$/, "", $0)
        gsub(/\r/, "", $0)
        if (length($0) > 0) print $0
      }
    }
  ' "$prd"
}
```

### §2.2 Step 4b branching (frontmatter path vs scan-fallback)

Inserted between the existing PRD_PATH_NORM line and the existing `SCANNED_ISSUES=0` declaration (around line 627 of current SKILL.md):

```bash
# Read derived_from once; empty means fall through to scan-fallback.
DERIVED_FROM_LIST=()
while IFS= read -r entry; do
  [ -n "$entry" ] && DERIVED_FROM_LIST+=("$entry")
done < <(read_derived_from "$PRD_PATH")

if [ "${#DERIVED_FROM_LIST[@]}" -gt 0 ]; then
  DERIVED_FROM_SOURCE="frontmatter"
else
  DERIVED_FROM_SOURCE="scan-fallback"
fi
```

### §2.3 Frontmatter-path archive loop

Runs iff `DERIVED_FROM_SOURCE == frontmatter`. Replaces the PR-#146 scan-and-match loop when that branch fires; the scan-fallback path (existing PR-#146 loop, unchanged) runs otherwise.

```bash
MISSING_ENTRIES=()
# On the frontmatter path, the scanned_* totals reflect the derived_from list,
# not a directory scan. This preserves the diagnostic's original field
# semantics ("what the step looked at") while making the new path deterministic.
SCANNED_ISSUES=0
SCANNED_FEEDBACK=0
MATCHED=0
ARCHIVED=0
SKIPPED=0
MATCH_LIST=()

for entry in "${DERIVED_FROM_LIST[@]}"; do
  case "$entry" in
    .kiln/issues/*)   SCANNED_ISSUES=$((SCANNED_ISSUES + 1)) ;;
    .kiln/feedback/*) SCANNED_FEEDBACK=$((SCANNED_FEEDBACK + 1)) ;;
  esac

  if [ ! -f "$entry" ]; then
    MISSING_ENTRIES+=("$entry")
    continue
  fi

  MATCH_LIST+=("$entry")
  MATCHED=$((MATCHED + 1))
done

# Archive loop (identical to PR-#146's §1 step 4 — reused verbatim).
for f in "${MATCH_LIST[@]}"; do
  orig_dir="$(dirname "$f")"
  base="$(basename "$f")"
  dest_dir="${orig_dir}/completed"
  mkdir -p "$dest_dir"

  tmp="$(mktemp "${f}.XXXXXX")"
  awk -v today="$TODAY" -v pr="$PR_NUMBER" '
    BEGIN { inserted = 0 }
    /^status:[[:space:]]/ && !inserted {
      print "status: completed"
      print "completed_date: " today
      print "pr: #" pr
      inserted = 1
      next
    }
    { print }
  ' "$f" > "$tmp" && mv "$tmp" "$f"

  if mv "$f" "${dest_dir}/${base}"; then
    ARCHIVED=$((ARCHIVED + 1))
  else
    echo "WARN: failed to archive $f → ${dest_dir}/${base}" >&2
    SKIPPED=$((SKIPPED + 1))
  fi
done
```

### §2.4 Scan-fallback path (unchanged from PR #146)

Runs iff `DERIVED_FROM_SOURCE == scan-fallback`. Use the existing PR-#146 scan-and-match loop verbatim (`plugin-kiln/skills/kiln-build-prd/SKILL.md` ~lines 625–692). Before entering the loop, initialize `MISSING_ENTRIES=()` (stays empty on this path). After the loop, the scanned_*/matched/archived/skipped totals are populated by the existing PR-#146 code.

### §2.5 Extended diagnostic line (FR-003 + FR-006; NFR-005 grep-anchor preservation)

REPLACES the single-line `DIAG_LINE=` assignment in PR #146 (`plugin-kiln/skills/kiln-build-prd/SKILL.md` ~line 696):

```bash
# Compose missing_entries JSON array (compact; jq for safety).
if [ "${#MISSING_ENTRIES[@]}" -eq 0 ]; then
  MISSING_JSON="[]"
else
  MISSING_JSON="$(printf '%s\n' "${MISSING_ENTRIES[@]}" | jq -Rn '[inputs]' -c)"
fi

DIAG_LINE="step4b: scanned_issues=${SCANNED_ISSUES} scanned_feedback=${SCANNED_FEEDBACK} matched=${MATCHED} archived=${ARCHIVED} skipped=${SKIPPED} prd_path=${PRD_PATH_NORM} derived_from_source=${DERIVED_FROM_SOURCE} missing_entries=${MISSING_JSON}"
echo "$DIAG_LINE"
printf '%s\n' "$DIAG_LINE" >> "$LOG_FILE"
```

### §2.6 Diagnostic line literal template (extended)

```
step4b: scanned_issues=<N> scanned_feedback=<M> matched=<K> archived=<A> skipped=<S> prd_path=<P> derived_from_source=<frontmatter|scan-fallback> missing_entries=<JSON-array>
```

Invariants:

- Fields 1–6 (`scanned_issues`, `scanned_feedback`, `matched`, `archived`, `skipped`, `prd_path`) MUST appear in the same positions and format as the PR-#146 diagnostic. **This preserves the PR-#146 grep regex** (`specs/pipeline-input-completeness/SMOKE.md` §5.3) which anchors on `^step4b: scanned_issues=[0-9]+ scanned_feedback=[0-9]+ matched=[0-9]+ archived=[0-9]+ skipped=[0-9]+ prd_path=[^[:space:]]+` (no end-of-line `$` — the regex does not require that nothing follows `prd_path`, so appending fields is safe).
- Field 7 (`derived_from_source`) is one of the two literal strings `frontmatter` or `scan-fallback`. No other values.
- Field 8 (`missing_entries`) is a compact JSON array (no whitespace inside). Empty array is rendered as `[]`, not `null` or empty string.
- The matched-count invariant: on the frontmatter path, `matched == ${#DERIVED_FROM_LIST[@]}` holds ONLY when `missing_entries == []`. When `missing_entries` is non-empty, the invariant is explicitly waived (FR-006).
- No embedded newlines. One line per run.

### §2.6.1 Extended verification regex (SC-002)

```
^step4b: scanned_issues=[0-9]+ scanned_feedback=[0-9]+ matched=[0-9]+ archived=[0-9]+ skipped=[0-9]+ prd_path=[^[:space:]]+ derived_from_source=(frontmatter|scan-fallback) missing_entries=\[.*\]$
```

### §2.6.2 PR-#146 regex replay (SC-007; NFR-005)

The existing PR-#146 grep regex continues to match the new line without modification:

```
^step4b: scanned_issues=[0-9]+ scanned_feedback=[0-9]+ matched=[0-9]+ archived=[0-9]+ skipped=[0-9]+ prd_path=[^[:space:]]+
```

(Unanchored at the end — passes on both the 6-field and the 8-field line.)

---

## §3 — Hygiene `merged-prd-not-archived` rule extensions

### §3.1 Frontmatter-walk primary path (FR-007)

Inserted BEFORE the existing walk-backlog loop in `plugin-kiln/skills/kiln-hygiene/SKILL.md` Step 5c (~line 215). Iterates PRDs, not backlog files:

```bash
# Track PRDs consumed via frontmatter — walk-backlog fallback skips items whose prd: is in this set.
declare -A PROCESSED_PRDS

# Walk PRDs under docs/features/ AND products/<slug>/features/.
for prd_file in docs/features/*/PRD.md products/*/features/*/PRD.md; do
  [ -f "$prd_file" ] || continue

  # Use the same read_derived_from helper shape defined in build-prd §2.1.
  DERIVED_FROM_LIST=()
  while IFS= read -r entry; do
    [ -n "$entry" ] && DERIVED_FROM_LIST+=("$entry")
  done < <(read_derived_from "$prd_file")

  [ "${#DERIVED_FROM_LIST[@]}" -eq 0 ] && continue  # fall through to walk-backlog for this PRD

  # Mark this PRD as handled by the frontmatter path.
  PROCESSED_PRDS["$prd_file"]=1

  # Derive the PRD's feature-slug the same way as today (contract §5 of kiln-structural-hygiene).
  prd_dir=$(dirname "$prd_file")
  slug=$(basename "$prd_dir" | sed -E 's:^[0-9]{4}-[0-9]{2}-[0-9]{2}-::')

  for entry in "${DERIVED_FROM_LIST[@]}"; do
    # Read the entry's current status off disk (frontmatter path expects the item to still exist in its pre-archive location OR in completed/).
    if [ -f "$entry" ]; then
      file="$entry"
    elif [ -f "$(dirname "$entry")/completed/$(basename "$entry")" ]; then
      # Already archived — emit keep signal (no drift).
      printf 'merged-prd-not-archived\tkeep\t%s\talready archived\n' "$entry" >> "$SIGNALS_FILE"
      continue
    else
      # Missing entry (hand-edited or moved) — needs-review.
      printf 'merged-prd-not-archived\tneeds-review\t%s\tderived_from entry missing on disk\n' "$entry" >> "$SIGNALS_FILE"
      continue
    fi

    status=$(awk -F: '/^status:/ {sub(/^[ \t]+/, "", $2); sub(/[ \t]+$/, "", $2); print $2; exit}' "$file" | tr -d ' ')
    [ "$status" = "prd-created" ] || { printf 'merged-prd-not-archived\tkeep\t%s\tstatus=%s\n' "$file" "$status" >> "$SIGNALS_FILE"; continue; }

    if [ "$GH_AVAILABLE" = false ]; then
      printf 'merged-prd-not-archived\tinconclusive\t%s\tgh unavailable\n' "$file" >> "$SIGNALS_FILE"
    elif [ -z "${MERGED_BY_SLUG[$slug]:-}" ]; then
      printf 'merged-prd-not-archived\tneeds-review\t%s\tno merged PR matching slug %s\n' "$file" "$slug" >> "$SIGNALS_FILE"
    else
      IFS=$'\t' read -r pr_num merged_at branch <<< "${MERGED_BY_SLUG[$slug]}"
      merged_date="${merged_at%%T*}"
      printf 'merged-prd-not-archived\tarchive-candidate\t%s\tPR #%s merged %s\n' "$file" "$pr_num" "$merged_date" >> "$SIGNALS_FILE"
    fi
  done
done
```

### §3.2 Walk-backlog fallback scope narrowing (FR-008)

The existing walk-backlog loop (lines 215–250 of `kiln-hygiene/SKILL.md`) stays in place — **but** each per-file iteration adds a new predicate at the top: **skip if the item's `prd:` value is a key in `PROCESSED_PRDS`**. This ensures the fallback only processes items whose PRD lacks `derived_from:`, preventing double-signal emission.

```bash
# Inside the existing walk-backlog loop, after reading prd_path:
if [ -n "${PROCESSED_PRDS[$prd_path]:-}" ]; then
  continue  # PRD already handled via frontmatter path — no double-signal.
fi
```

### §3.3 Rubric text update

`plugin-kiln/rubrics/structural-hygiene.md` `merged-prd-not-archived` rule's narrative section (lines 35–48) gets ONE new paragraph inserted between the "Fires against..." list and the "Bulk-lookup strategy" paragraph:

> **Primary path (post PRD `derived_from:` frontmatter — `specs/prd-derived-from-frontmatter/spec.md`)**: when a PRD under `docs/features/*/PRD.md` or `products/*/features/*/PRD.md` carries a non-empty `derived_from:` frontmatter list, the rule walks PRDs and emits one signal per listed entry (via the PROCESSED_PRDS dedup set). The walk-backlog loop below becomes the fallback and ONLY processes items whose `prd:` points at a PRD lacking `derived_from:`. Output for the fallback path is byte-identical to the pre-frontmatter behavior.

No other rubric text changes.

---

## §4 — Migration subcommand (propose-don't-apply)

### §4.1 Entry point (Decision D1)

`/kiln:kiln-hygiene backfill` — a subcommand of the existing `/kiln:kiln-hygiene` skill. The skill's `$ARGUMENTS` block dispatches on the first token:

```bash
case "${1:-}" in
  backfill)
    # Run the derived_from backfill — contracts §4.2.
    ;;
  "")
    # Default behavior: run the full structural hygiene audit (today's behavior).
    ;;
  *)
    echo "Unknown subcommand: $1" >&2
    echo "Known subcommands: backfill" >&2
    exit 2
    ;;
esac
```

### §4.2 Backfill workflow (FR-009, FR-010, FR-011)

```bash
TIMESTAMP="$(date -u +%Y-%m-%dT%H-%M-%SZ)"
OUT=".kiln/logs/prd-derived-from-backfill-${TIMESTAMP}.md"
mkdir -p .kiln/logs

HUNKS_FILE="$(mktemp -t derived-from-backfill.XXXXXX)"
HUNK_COUNT=0

for prd_file in docs/features/*/PRD.md products/*/features/*/PRD.md; do
  [ -f "$prd_file" ] || continue

  # Idempotence: skip if frontmatter already carries derived_from:
  existing="$(read_derived_from "$prd_file" | head -1 || true)"
  # Also check for empty-list case (derived_from: []) — treated as already migrated.
  if head -20 "$prd_file" | grep -Eq '^derived_from:[[:space:]]*(\[\])?[[:space:]]*$'; then
    continue
  fi

  # Parse ### Source Issues table — extract the first column's markdown-link target.
  table_rows="$(awk '
    /^### Source Issues/ { in_table = 1; next }
    in_table && /^## / { exit }
    in_table && /^\|[[:space:]]*[0-9]+[[:space:]]*\|/ {
      # First data column is |  # | second column is | [title](path) |
      # Extract path inside the parens of the second cell.
      if (match($0, /\]\(([^)]+)\)/, m)) print m[1]
    }
  ' "$prd_file")"

  [ -z "$table_rows" ] && continue  # no parseable table — nothing to backfill

  # Sort feedback-first, then issues, then filename ASC within each group.
  derived_lines="$(
    {
      printf '%s\n' "$table_rows" | grep -E '^\.kiln/feedback/' | sort
      printf '%s\n' "$table_rows" | grep -E '^\.kiln/issues/' | sort
    }
  )"

  # Derive theme from directory basename.
  prd_dir="$(dirname "$prd_file")"
  theme="$(basename "$prd_dir" | sed -E 's:^[0-9]{4}-[0-9]{2}-[0-9]{2}-::')"

  # Derive distilled_date from body **Date**: line; fall back to file mtime.
  date_line="$(grep -m1 '^\*\*Date\*\*:' "$prd_file" | sed -E 's/^\*\*Date\*\*:[[:space:]]*//; s/[[:space:]]+$//')"
  if [ -z "$date_line" ]; then
    date_line="$(date -u -r "$prd_file" +%Y-%m-%d 2>/dev/null || date -u +%Y-%m-%d)"
    date_note="  # distilled_date inferred from file mtime — review"
  else
    date_note=""
  fi

  # Compose the candidate frontmatter block.
  {
    echo "### diff --- $prd_file"
    echo '```diff'
    echo "@@ top of file @@"
    echo "+---"
    echo "+derived_from:"
    while IFS= read -r p; do
      if [ -f "$p" ]; then
        echo "+  - $p"
      else
        echo "+  # - $p  # path does not exist on disk — review"
      fi
    done <<< "$derived_lines"
    echo "+distilled_date: ${date_line}${date_note}"
    echo "+theme: ${theme}"
    echo "+---"
    echo '```'
    echo
  } >> "$HUNKS_FILE"

  HUNK_COUNT=$((HUNK_COUNT + 1))
done

# Write the preview.
{
  echo "# derived_from Backfill — ${TIMESTAMP}"
  echo
  echo "**Audited repo**: $(pwd)"
  echo "**Rubric**: plugin-kiln/rubrics/structural-hygiene.md (rule: derived_from-backfill)"
  echo "**Result**: ${HUNK_COUNT} PRD(s) to backfill"
  echo
  echo "## Bundled: derived_from-backfill (${HUNK_COUNT} items)"
  echo
  if [ "$HUNK_COUNT" -eq 0 ]; then
    echo "_no PRDs to backfill — all PRDs already carry \`derived_from:\` frontmatter._"
  else
    echo "> **Accept or reject as a unit.** Per-item cherry-pick is supported by applying individual hunks manually. Hunks that reference non-existent paths are commented out (\`# - <path>  # path does not exist on disk — review\`) — review and resolve before applying."
    echo
    sort "$HUNKS_FILE" | awk '/^### diff --- / { print "---"; print ""; print } !/^### diff --- / { print }'
  fi
} > "$OUT"

rm -f "$HUNKS_FILE"

echo "Wrote: $OUT"
echo "Bundled hunks: $HUNK_COUNT"
```

### §4.3 Rubric entry for the backfill rule

Added to `plugin-kiln/rubrics/structural-hygiene.md` in a new `### derived_from-backfill` section AFTER `### merged-prd-not-archived`:

```yaml
rule_id: derived_from-backfill
signal_type: load-bearing
cost: cheap
match_rule: PRD under docs/features/*/PRD.md or products/*/features/*/PRD.md LACKS a non-empty derived_from: frontmatter AND contains a parseable ### Source Issues table
action: backfill-candidate
rationale: Retrofit derived_from: frontmatter on pre-migration PRDs so Step 4b and merged-prd-not-archived can use the read-PRD-once primary path. Propose-don't-apply: the subcommand writes a diff preview; the maintainer applies manually.
cached: false
```

Entrypoint: `/kiln:kiln-hygiene backfill`. Output: `.kiln/logs/prd-derived-from-backfill-<timestamp>.md` (one bundled section, one hunk per eligible PRD, sorted by PRD path ASC). Idempotent: a second invocation on the same state writes `0 items`.

---

## §5 — Fixture shapes (for SMOKE.md)

### §5.1 Distill writer fixture (SC-001, SC-006)

```bash
# Setup — scaffold a minimal fixture backlog.
TMPDIR="$(mktemp -d -t distill-fixture.XXXXXX)"
cd "$TMPDIR"
mkdir -p .kiln/feedback .kiln/issues docs/features/

cat > .kiln/feedback/2026-04-30-fixture-feedback.md <<'EOF'
---
id: 2026-04-30-fixture-feedback
title: Fixture feedback for distill
type: feedback
date: 2026-04-30
status: open
severity: medium
area: testing
---
body
EOF

cat > .kiln/issues/2026-04-30-fixture-issue.md <<'EOF'
---
title: Fixture issue for distill
type: bug
severity: low
category: testing
source: manual
status: open
date: 2026-04-30
---
body
EOF

# Invocation: the distill skill renders the PRD (simulate via contracts §1 skeleton).
# After /kiln:kiln-distill exits:
PRD="docs/features/2026-04-30-fixture-theme/PRD.md"

# Assertion 1: frontmatter block is at the top and keys are in order.
head -6 "$PRD" | awk '
  NR==1 && $0 == "---" { ok1=1 }
  NR==2 && $0 == "derived_from:" { ok2=1 }
  /^distilled_date:/ { ok_date=1 }
  /^theme:/ { ok_theme=1 }
  END { if (ok1 && ok2 && ok_date && ok_theme) exit 0; else exit 1 }
' && echo "OK: frontmatter block present with correct key order" || echo "FAIL"

# Assertion 2: derived_from: paths == Source Issues table paths, in order.
FRONTMATTER_PATHS="$(awk '/^---$/{s++;next} s==1 && /^[[:space:]]+-[[:space:]]+/{sub(/^[[:space:]]+-[[:space:]]+/,"");print}' "$PRD")"
TABLE_PATHS="$(awk '/^### Source Issues/{in_t=1;next} in_t && /^## /{exit} in_t && /\]\(/{if(match($0,/\]\(([^)]+)\)/,m)) print m[1]}' "$PRD")"
test "$FRONTMATTER_PATHS" = "$TABLE_PATHS" && echo "OK: frontmatter and table agree" || echo "FAIL"

cd - && rm -rf "$TMPDIR"
```

### §5.2 Step 4b extended diagnostic fixture (SC-002, SC-003, SC-007 replay)

```bash
# Sub-fixture A: PRD with derived_from: → frontmatter path.
TMPDIR="$(mktemp -d -t step4b-frontmatter.XXXXXX)"
cd "$TMPDIR"
mkdir -p .kiln/feedback .kiln/issues docs/features/2026-04-30-fixture/

cat > docs/features/2026-04-30-fixture/PRD.md <<'EOF'
---
derived_from:
  - .kiln/feedback/a.md
  - .kiln/issues/b.md
distilled_date: 2026-04-30
theme: fixture
---
# Feature PRD: Fixture
EOF

cat > .kiln/feedback/a.md <<'EOF'
---
status: prd-created
prd: docs/features/2026-04-30-fixture/PRD.md
---
EOF

cat > .kiln/issues/b.md <<'EOF'
---
status: prd-created
prd: docs/features/2026-04-30-fixture/PRD.md
---
EOF

# Invocation: paste Step 4b body from plugin-kiln/skills/kiln-build-prd/SKILL.md.
PRD_PATH="docs/features/2026-04-30-fixture/PRD.md"
PR_NUMBER="999"
# (run Step 4b)

TODAY="$(date -u +%Y-%m-%d)"
LOG=".kiln/logs/build-prd-step4b-${TODAY}.md"
LAST="$(tail -1 "$LOG")"

# Extended regex (contracts §2.6.1)
echo "$LAST" | grep -E '^step4b: scanned_issues=[0-9]+ scanned_feedback=[0-9]+ matched=[0-9]+ archived=[0-9]+ skipped=[0-9]+ prd_path=[^[:space:]]+ derived_from_source=(frontmatter|scan-fallback) missing_entries=\[.*\]$' >/dev/null \
  && echo "$LAST" | grep -q 'derived_from_source=frontmatter missing_entries=\[\]' \
  && test -f .kiln/feedback/completed/a.md \
  && test -f .kiln/issues/completed/b.md \
  && echo "OK (sub-fixture A)" || echo "FAIL (sub-fixture A)"

# PR-#146 grep-anchor replay (contracts §2.6.2 / NFR-005)
echo "$LAST" | grep -E '^step4b: scanned_issues=[0-9]+ scanned_feedback=[0-9]+ matched=[0-9]+ archived=[0-9]+ skipped=[0-9]+ prd_path=[^[:space:]]+' >/dev/null \
  && echo "OK (PR-#146 regex still matches)" || echo "FAIL"

cd - && rm -rf "$TMPDIR"

# Sub-fixture B: pre-migration PRD (no frontmatter) → scan-fallback path.
TMPDIR="$(mktemp -d -t step4b-fallback.XXXXXX)"
cd "$TMPDIR"
mkdir -p .kiln/feedback .kiln/issues docs/features/2026-04-30-legacy/

cat > docs/features/2026-04-30-legacy/PRD.md <<'EOF'
# Feature PRD: Legacy

**Date**: 2026-04-30
EOF

cat > .kiln/feedback/c.md <<'EOF'
---
status: prd-created
prd: docs/features/2026-04-30-legacy/PRD.md
---
EOF

PRD_PATH="docs/features/2026-04-30-legacy/PRD.md"
PR_NUMBER="999"
# (run Step 4b)

LAST="$(tail -1 .kiln/logs/build-prd-step4b-$(date -u +%Y-%m-%d).md)"
echo "$LAST" | grep -q 'derived_from_source=scan-fallback missing_entries=\[\]' \
  && echo "OK (sub-fixture B)" || echo "FAIL (sub-fixture B)"

cd - && rm -rf "$TMPDIR"
```

### §5.3 Hygiene + migration fixture (SC-004, SC-005)

```bash
TMPDIR="$(mktemp -d -t hygiene-migration.XXXXXX)"
cd "$TMPDIR"
git init -q
mkdir -p .kiln/feedback .kiln/issues docs/features/2026-04-30-migrated docs/features/2026-04-30-unmigrated

# Migrated PRD (has derived_from:)
cat > docs/features/2026-04-30-migrated/PRD.md <<'EOF'
---
derived_from:
  - .kiln/feedback/m.md
distilled_date: 2026-04-30
theme: migrated
---
# Feature PRD: Migrated

**Date**: 2026-04-30

### Source Issues

| # | Source Item | Source | Type | GitHub Issue | Severity / Area |
|---|---|---|---|---|---|
| 1 | [m](.kiln/feedback/m.md) | .kiln/feedback/ | feedback | — | medium |
EOF

# Unmigrated PRD (no frontmatter, has body table)
cat > docs/features/2026-04-30-unmigrated/PRD.md <<'EOF'
# Feature PRD: Unmigrated

**Date**: 2026-04-30

### Source Issues

| # | Source Item | Source | Type | GitHub Issue | Severity / Area |
|---|---|---|---|---|---|
| 1 | [u](.kiln/issues/u.md) | .kiln/issues/ | issue | — | low |
EOF

cat > .kiln/feedback/m.md <<'EOF'
---
status: prd-created
prd: docs/features/2026-04-30-migrated/PRD.md
---
EOF

cat > .kiln/issues/u.md <<'EOF'
---
status: prd-created
prd: docs/features/2026-04-30-unmigrated/PRD.md
---
EOF

# Run hygiene (stub gh — both PRDs in the map for fixture).
# Preview should contain ONE row per derived_from entry for migrated/, AND the walk-backlog signal for u.md (unmigrated PRD has no frontmatter).
# (run /kiln:kiln-hygiene)
PREVIEW="$(ls -t .kiln/logs/structural-hygiene-*.md | head -1)"
grep -q '.kiln/feedback/m.md' "$PREVIEW" && grep -q '.kiln/issues/u.md' "$PREVIEW" \
  && echo "OK (mixed-state hygiene)" || echo "FAIL"

# Run migration twice; second run should emit 0 items.
# (run /kiln:kiln-hygiene backfill) → .kiln/logs/prd-derived-from-backfill-<ts1>.md
FIRST_PREVIEW="$(ls -t .kiln/logs/prd-derived-from-backfill-*.md | head -1)"
grep -qE 'Bundled: derived_from-backfill \(1 items?\)' "$FIRST_PREVIEW" \
  && echo "OK (first backfill run found 1 eligible PRD)" || echo "FAIL"

# Apply the hunk manually (simulate): prepend derived_from: frontmatter to the unmigrated PRD.
cat > docs/features/2026-04-30-unmigrated/PRD.md.new <<'EOF'
---
derived_from:
  - .kiln/issues/u.md
distilled_date: 2026-04-30
theme: unmigrated
---
EOF
cat docs/features/2026-04-30-unmigrated/PRD.md >> docs/features/2026-04-30-unmigrated/PRD.md.new
mv docs/features/2026-04-30-unmigrated/PRD.md.new docs/features/2026-04-30-unmigrated/PRD.md

# Second migration run
# (run /kiln:kiln-hygiene backfill) → .kiln/logs/prd-derived-from-backfill-<ts2>.md
SECOND_PREVIEW="$(ls -t .kiln/logs/prd-derived-from-backfill-*.md | head -1)"
grep -qE 'Bundled: derived_from-backfill \(0 items?\)' "$SECOND_PREVIEW" \
  && echo "OK (idempotent — second run 0 items)" || echo "FAIL"

cd - && rm -rf "$TMPDIR"
```

---

## §6 — Cross-references

| Contract section | Spec FR | Success Criterion | Phase |
|---|---|---|---|
| §1 (frontmatter block shape + FR-002 invariant) | FR-001, FR-002, FR-003 | SC-001, SC-006 | A |
| §2.1–§2.3 (Step 4b frontmatter-path reader + archive) | FR-004 | SC-002 | B |
| §2.4 (scan-fallback unchanged) | FR-005 | SC-003 | B |
| §2.5, §2.6 (extended diagnostic) | FR-006, NFR-005 | SC-002, SC-007 | B |
| §3.1 (hygiene frontmatter-walk primary) | FR-007 | SC-004 | C |
| §3.2 (hygiene walk-backlog fallback scoped) | FR-008, NFR-001 | SC-004 | C |
| §3.3 (rubric text) | FR-007 | SC-004 | C |
| §4 (migration subcommand + idempotence) | FR-009, FR-010, FR-011 | SC-005 | D |
| §5 fixtures | (all) | SC-008 | E |
| §2.6.2 (PR-#146 regex replay in Phase F log) | NFR-005 | SC-007 | F |
