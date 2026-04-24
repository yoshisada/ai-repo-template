---
name: kiln-hygiene
description: Audit the repo against the structural-hygiene rubric and propose a review preview at .kiln/logs/. Never applies edits.
---

# Kiln Structural Hygiene Audit — Propose Review Preview

Reads the current repo against `plugin-kiln/rubrics/structural-hygiene.md`, evaluates every rule (cheap + editorial), and writes a review preview to `.kiln/logs/structural-hygiene-<timestamp>.md`. **This skill never applies edits.** The maintainer reads the preview and either applies a proposed change manually or re-runs the audit after fixing the underlying drift.

Contracts (single source of truth — consult these before changing behavior):
- Rubric schema + required rules — `specs/kiln-structural-hygiene/contracts/interfaces.md` §1.
- Output file shape — §2.
- `merged-prd-not-archived` predicate — §5.
- `orphaned-top-level-folder` predicate — §6.
- `unreferenced-kiln-artifact` predicate — §7.
- Override config shape — §8.
- Exact error/edge strings — §9 (grep-anchored by tests; do not re-word).

Mirrors the propose-don't-apply discipline of `/kiln:kiln-claude-audit`. Idempotent by construction (NFR-002 / SC-006).

## User Input

```text
$ARGUMENTS
```

Supported flag: `--config <path>` — point the skill at an override file other than `.kiln/structural-hygiene.config`.

**Subcommands**:

- `` (no subcommand) — run the full structural hygiene audit (Steps 1–7 below). Default behavior; unchanged.
- `backfill` — run the `derived_from:` backfill workflow (see **Step B — Backfill Subcommand** at the bottom of this file). Propose-don't-apply; writes a review preview at `.kiln/logs/prd-derived-from-backfill-<timestamp>.md`.

## Step 0 — Dispatch on subcommand (spec `prd-derived-from-frontmatter` Decision D1)

Parse the first token of `$ARGUMENTS` and dispatch. Before touching anything else, run:

```bash
SUBCOMMAND="$(printf '%s' "$ARGUMENTS" | awk '{print $1}')"
case "$SUBCOMMAND" in
  backfill)
    # Execute Step B — Backfill Subcommand (at the bottom of this file), then exit 0.
    # DO NOT continue into Steps 1–7.
    ;;
  "")
    # Default: full structural hygiene audit. Fall through to Step 1.
    ;;
  *)
    echo "Unknown subcommand: $SUBCOMMAND" >&2
    echo "Known subcommands: backfill" >&2
    exit 2
    ;;
esac
```

Unknown subcommands exit 2 with the exact two-line message above (grep-anchored).

## Step 1 — Resolve paths

Set these variables in order. Fail fast with the exact error message when required inputs are missing.

**RUBRIC_PATH**: the plugin-embedded rubric at `plugin-kiln/rubrics/structural-hygiene.md`. Resolution order (same 4-step fallback as `/kiln:kiln-claude-audit` Step 1):

1. `$CLAUDE_PLUGIN_ROOT/rubrics/structural-hygiene.md` (when invoked via a hook env).
2. `plugin-kiln/rubrics/structural-hygiene.md` (source-repo checkout).
3. `~/.claude/plugins/cache/*/kiln/*/rubrics/structural-hygiene.md` (consumer install — first `find` hit).
4. `$(npm root -g)/@yoshisada/kiln/rubrics/structural-hygiene.md` (legacy npm install).

If none resolve, exit 1 with the exact message from contract §9:

```
rubric not found at <expected path>; run kiln init or re-install the plugin
```

**OVERRIDE_PATH**: if `--config <path>` is passed, use that; else `.kiln/structural-hygiene.config` if present; else none.

**TIMESTAMP**: `date +%Y-%m-%d-%H%M%S`. Use this exact format for the output filename.

**OUTPUT_PATH**: `.kiln/logs/structural-hygiene-${TIMESTAMP}.md`. Create `.kiln/logs/` if it does not exist.

## Step 2 — Load rubric + detect override presence

Parse the rubric:

- Read every `### <rule_id>` heading in the rubric.
- For each rule, extract the fenced YAML-ish key/value block (`rule_id`, `signal_type`, `cost`, `match_rule`, `action`, `rationale`, `cached`).
- Collect the default threshold values from the preamble: `orphaned-top-level-folder.min_age_days` (default 30), `unreferenced-kiln-artifact.min_age_days` (default 60), `merged-prd-not-archived.gh_limit` (default 500).

Record `RUBRIC_RULE_ORDER` — the top-to-bottom rule_ids as they appear in the rubric file. Per-rule preview sections are emitted in this order for idempotence (NFR-002).

## Step 3 — Load override (if any)

If `OVERRIDE_PATH` is set and the file exists, parse per contract §8:

- One `key = value` or `key: value` per line. `#` begins a comment; blank lines ignored.
- Threshold overrides use the raw name (e.g. `orphaned-top-level-folder.min_age_days = 60`).
- Rule-level overrides use the `<rule_id>.<field>` shape (e.g. `orphaned-top-level-folder.enabled = false`, `merged-prd-not-archived.action = needs-review`).
- Allowed `action` values: `keep | archive-candidate | removal-candidate | needs-review | inconclusive`.

**Malformed-override behavior** (contract §9): if any line fails to parse OR assigns an invalid action value, emit exactly:

```
structural-hygiene.config: unparseable at line N; falling back to plugin defaults
```

Proceed with plugin defaults ONLY — do not half-apply. Continue with exit 0 (warning, not hard failure). Matches `claude-md-audit` Step 2 precedent.

**Unknown rule_id**: if `<rule_id>.<field>` references a rule not in the plugin rubric, emit exactly:

```
structural-hygiene.config: unknown rule_id '<id>' at line N — ignoring
```

Skip just that line; other override lines keep applying.

Record `APPLIED_OVERRIDES` — the list of rule_ids whose values were actually changed by a valid override. This list goes in the Notes section of the preview.

## Step 4 — Initialize signal collector + gh availability

```bash
SIGNALS_FILE=$(mktemp -t structural-hygiene-signals.XXXXXX.tsv)
# Each line: <rule_id>\t<action>\t<path>\t<detail>
NOTES=()
TRUNCATION_WARNING=""

GH_AVAILABLE=true
if ! command -v gh >/dev/null 2>&1; then GH_AVAILABLE=false; fi
if [ "$GH_AVAILABLE" = true ] && ! gh auth status >/dev/null 2>&1; then GH_AVAILABLE=false; fi
```

## Step 5 — Run rule predicates

Evaluate every rule from the rubric. A rule that is disabled via override (`<rule_id>.enabled = false`) is SKIPPED entirely and emits zero signals.

### Step 5a — `orphaned-top-level-folder` (cheap)

Contract §6. Enumerate top-level dirs, exclude `.git` and `node_modules`, check predicates (a)/(b)/(c):

```bash
MANIFEST_JSON=""
for candidate in \
  "$CLAUDE_PLUGIN_ROOT/templates/kiln-manifest.json" \
  "plugin-kiln/templates/kiln-manifest.json" \
  "$(find ~/.claude/plugins/cache -path '*/kiln/templates/kiln-manifest.json' 2>/dev/null | head -1)"; do
  if [ -n "$candidate" ] && [ -f "$candidate" ]; then MANIFEST_JSON="$candidate"; break; fi
done

if [ -z "$MANIFEST_JSON" ]; then
  NOTES+=("orphaned-top-level-folder: kiln-manifest.json not found — rule skipped")
else
  MANIFEST_DIRS=$(jq -r '.directories | keys[]' "$MANIFEST_JSON" | sed 's:^\./::; s:/*$::')
  TOP_LEVEL_MANIFEST=$(echo "$MANIFEST_DIRS" | awk -F/ '{print $1}' | sort -u)

  MIN_AGE="${ORPHANED_MIN_AGE_DAYS:-30}"
  while IFS= read -r dir; do
    [ -z "$dir" ] && continue
    # (a) manifest-absent
    echo "$TOP_LEVEL_MANIFEST" | grep -Fxq "$dir" && continue
    # (b) unreferenced (literal path-prefix across plugin-*/ + templates/)
    if grep -RlF "${dir}/" plugin-*/ templates/ 2>/dev/null | head -1 | grep -q . ; then continue; fi
    # (c) mtime > min_age_days on the directory itself
    find "$dir" -maxdepth 0 -type d -mtime "+$MIN_AGE" | grep -q . || continue
    printf 'orphaned-top-level-folder\tremoval-candidate\t%s\tquiescent top-level dir, not in manifest, unreferenced, mtime > %sd\n' "$dir" "$MIN_AGE" >> "$SIGNALS_FILE"
  done < <(find . -maxdepth 1 -mindepth 1 -type d ! -name '.git' ! -name 'node_modules' | sed 's:^\./::')
fi
```

### Step 5b — `unreferenced-kiln-artifact` (cheap)

Contract §7. Walk artifact-bearing directories under `.kiln/`; skip files referenced by any `.wheel/state_*.json`; skip `.gitkeep` and `README.md`.

```bash
MIN_AGE="${UNREF_ARTIFACT_MIN_AGE_DAYS:-60}"
ARTIFACT_DIRS=(
  ".kiln/logs"
  ".kiln/qa/test-results"
  ".kiln/qa/playwright-report"
  ".kiln/qa/videos"
  ".kiln/qa/traces"
  ".kiln/qa/screenshots"
  ".kiln/qa/results"
  ".kiln/state"
)

for art_dir in "${ARTIFACT_DIRS[@]}"; do
  [ -d "$art_dir" ] || continue
  while IFS= read -r file; do
    [ -z "$file" ] && continue
    base=$(basename "$file")
    # Exclude gitkeep/README
    case "$base" in .gitkeep|README.md) continue ;; esac
    # Exclude files referenced by any live wheel state
    if compgen -G ".wheel/state_*.json" >/dev/null 2>&1; then
      if grep -lF "$base" .wheel/state_*.json 2>/dev/null | head -1 | grep -q . ; then
        continue
      fi
    fi
    printf 'unreferenced-kiln-artifact\tremoval-candidate\t%s\tartifact older than %sd, not referenced by any wheel state\n' "$file" "$MIN_AGE" >> "$SIGNALS_FILE"
  done < <(find "$art_dir" -type f -mtime "+$MIN_AGE" 2>/dev/null)
done
```

### Step 5c — `merged-prd-not-archived` (editorial)

Contract §5. Single bulk `gh` call, in-memory associative array keyed by derived slug, per-item O(1) predicate. ZERO per-item `gh` calls.

```bash
MERGED_PRD_GH_LIMIT="${MERGED_PRD_GH_LIMIT:-500}"
declare -A MERGED_BY_SLUG
GH_TSV=""

if [ "$GH_AVAILABLE" = true ]; then
  GH_TSV=$(mktemp -t gh-merged-prs.XXXXXX.tsv)
  if ! gh pr list --state merged --limit "$MERGED_PRD_GH_LIMIT" \
       --json number,headRefName,title,mergedAt \
       --jq '.[] | "\(.headRefName)\t\(.number)\t\(.mergedAt)"' \
       > "$GH_TSV" 2>/dev/null; then
    GH_AVAILABLE=false
  fi
fi

if [ "$GH_AVAILABLE" = true ] && [ -f "$GH_TSV" ]; then
  # Populate map keyed by derived slug (build/<slug>-<YYYYMMDD> → <slug>).
  # gh orders merged PRs by mergedAt DESC — first occurrence wins on collision
  # (most-recent-merge semantics per contract §5 and spec Edge Cases).
  while IFS=$'\t' read -r branch num merged_at; do
    slug=$(echo "$branch" | sed -E 's:^build/::; s:-[0-9]{8}$::')
    [ -z "$slug" ] && continue
    if [ -z "${MERGED_BY_SLUG[$slug]:-}" ]; then
      MERGED_BY_SLUG[$slug]="$num	$merged_at	$branch"
    fi
  done < "$GH_TSV"

  # Truncation check (contract §9 exact error string — grep-anchored in tests)
  GH_LINE_COUNT=$(wc -l < "$GH_TSV" | tr -d ' ')
  if [ "$GH_LINE_COUNT" = "$MERGED_PRD_GH_LIMIT" ]; then
    NOTES+=("merged-prd-not-archived: gh pr list returned ${GH_LINE_COUNT} entries — possible truncation; raise merged-prd-not-archived.gh_limit in .kiln/structural-hygiene.config if needed")
  fi
else
  # gh-unavailable path (FR-006). Exact string from contract §9.
  NOTES+=("merged-prd-not-archived: gh unavailable — marked inconclusive")
fi

# --- Frontmatter-walk primary path (FR-007, spec `prd-derived-from-frontmatter`) ---
# When a PRD carries a non-empty derived_from: frontmatter list, walk PRDs (not backlog)
# and emit one signal per listed entry. The walk-backlog loop below becomes the fallback
# and only processes items whose prd: points at a PRD NOT in PROCESSED_PRDS.

# read_derived_from helper — bounded extractor for the first YAML frontmatter block.
# Mirrors plugin-kiln/skills/kiln-build-prd/SKILL.md Step 4b §2.1. Duplicated here per
# the specifier's friction notes (defer factoring to a follow-on PRD to avoid a
# plugin-portability question today).
read_derived_from() {
  local prd="$1"
  [ -f "$prd" ] || { return 0; }
  awk '
    BEGIN { state = "before"; emit = 0 }
    state == "inside" && /^---[[:space:]]*$/ { exit 0 }
    state == "before" && /^---[[:space:]]*$/ { state = "inside"; next }
    state == "before" && NF > 0 { exit 0 }
    state == "inside" {
      if ($0 ~ /^derived_from:[[:space:]]*(\[\])?[[:space:]]*$/) { emit = 1; next }
      if (emit == 1 && $0 ~ /^[A-Za-z_][A-Za-z0-9_]*:/) { emit = 0; next }
      if (emit == 1 && $0 ~ /^[[:space:]]+-[[:space:]]+/) {
        sub(/^[[:space:]]+-[[:space:]]+/, "", $0)
        sub(/[[:space:]]+$/, "", $0)
        gsub(/\r/, "", $0)
        if (length($0) > 0) print $0
      }
    }
  ' "$prd"
}

# Track PRDs consumed via frontmatter — walk-backlog fallback skips items whose prd: is in this set.
declare -A PROCESSED_PRDS

# Walk PRDs under docs/features/ AND products/<slug>/features/.
for prd_file in docs/features/*/PRD.md products/*/features/*/PRD.md; do
  [ -f "$prd_file" ] || continue

  DERIVED_FROM_LIST=()
  while IFS= read -r entry; do
    [ -n "$entry" ] && DERIVED_FROM_LIST+=("$entry")
  done < <(read_derived_from "$prd_file")

  # Empty list → pre-migration PRD; fall through to walk-backlog for this one.
  [ "${#DERIVED_FROM_LIST[@]}" -eq 0 ] && continue

  # Mark this PRD as handled by the frontmatter path (FR-008 dedup).
  PROCESSED_PRDS["$prd_file"]=1

  prd_dir=$(dirname "$prd_file")
  slug=$(basename "$prd_dir" | sed -E 's:^[0-9]{4}-[0-9]{2}-[0-9]{2}-::')

  for entry in "${DERIVED_FROM_LIST[@]}"; do
    # Frontmatter path expects the entry to still exist in its pre-archive location
    # OR to have already been archived under completed/.
    if [ -f "$entry" ]; then
      file="$entry"
    elif [ -f "$(dirname "$entry")/completed/$(basename "$entry")" ]; then
      # Already archived — keep signal (no drift).
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

# --- Walk-backlog fallback (FR-008) — scoped to PRDs NOT in PROCESSED_PRDS ---
# Walk candidates under .kiln/issues/*.md + .kiln/feedback/*.md.
# DO NOT scan .kiln/issues/completed/ — those are already archived.
for scan_dir in .kiln/issues .kiln/feedback; do
  [ -d "$scan_dir" ] || continue
  for file in "$scan_dir"/*.md; do
    [ -f "$file" ] || continue

    status=$(awk -F: '/^status:/ {sub(/^[ \t]+/, "", $2); sub(/[ \t]+$/, "", $2); print $2; exit}' "$file" | tr -d ' ')
    [ "$status" = "prd-created" ] || continue

    prd_path=$(awk -F: '/^prd:/ {sub(/^[ \t]+/, "", $2); sub(/[ \t]+$/, "", $2); print $2; exit}' "$file" | tr -d ' ')

    # FR-008 dedup: if the PRD was already handled via frontmatter path, skip the backlog row.
    if [ -n "${PROCESSED_PRDS[$prd_path]:-}" ]; then
      continue
    fi

    # FR-008: empty / missing prd: field, or points at a non-existent file.
    if [ -z "$prd_path" ] || [ ! -f "$prd_path" ]; then
      printf 'merged-prd-not-archived\tneeds-review\t%s\tprd: field empty or points at missing file\n' "$file" >> "$SIGNALS_FILE"
      continue
    fi

    # Feature-slug derivation (contract §5). Handles BOTH:
    #   docs/features/YYYY-MM-DD-<slug>/PRD.md → <slug>
    #   products/<slug>/PRD.md                → <slug>
    prd_dir=$(dirname "$prd_path")
    slug=$(basename "$prd_dir" | sed -E 's:^[0-9]{4}-[0-9]{2}-[0-9]{2}-::')

    if [ "$GH_AVAILABLE" = false ]; then
      printf 'merged-prd-not-archived\tinconclusive\t%s\tgh unavailable\n' "$file" >> "$SIGNALS_FILE"
    elif [ -z "${MERGED_BY_SLUG[$slug]:-}" ]; then
      # FR-008: prd: points at a PRD whose branch doesn't appear in the bulk lookup.
      printf 'merged-prd-not-archived\tneeds-review\t%s\tno merged PR matching slug %s\n' "$file" "$slug" >> "$SIGNALS_FILE"
    else
      IFS=$'\t' read -r pr_num merged_at branch <<< "${MERGED_BY_SLUG[$slug]}"
      merged_date="${merged_at%%T*}"  # YYYY-MM-DD
      printf 'merged-prd-not-archived\tarchive-candidate\t%s\tPR #%s merged %s\n' "$file" "$pr_num" "$merged_date" >> "$SIGNALS_FILE"
    fi
  done
done

[ -f "$GH_TSV" ] && rm -f "$GH_TSV"
```

## Step 6 — Render preview

Sort signals deterministically (NFR-002): `rule_id ASC, path ASC` primary, `action ASC` tiebreaker.

```bash
SORTED_SIGNALS=$(sort -t $'\t' -k1,1 -k3,3 -k2,2 "$SIGNALS_FILE")
```

Count by action:

```bash
ARCHIVE_CANDIDATES=$(echo "$SORTED_SIGNALS" | awk -F'\t' '$1=="merged-prd-not-archived" && $2=="archive-candidate"' | wc -l | tr -d ' ')
TOTAL_ACTIONABLE=$(echo "$SORTED_SIGNALS" | awk -F'\t' '$2!="keep" && $2!="" && NF>0' | wc -l | tr -d ' ')
TOTAL_ROWS=$(echo "$SORTED_SIGNALS" | awk 'NF>0' | wc -l | tr -d ' ')
```

Compute the Result line:

- If `TOTAL_ROWS == 0` OR all rows are `keep`/`inconclusive` → `**Result**: no drift`.
- Otherwise → `**Result**: <TOTAL_ACTIONABLE> signals`.

Write `OUTPUT_PATH` using the exact shape from contract §2:

```markdown
# Structural Hygiene Audit — <YYYY-MM-DD HH:MM:SS>

**Audited repo**: <absolute path to repo root>
**Rubric**: plugin-kiln/rubrics/structural-hygiene.md (+ .kiln/structural-hygiene.config if present)
**gh availability**: <available | unavailable>
**Result**: <no drift | N signals>

## Signal Summary

| rule_id | signal_type | cost | action | path | count |
|---|---|---|---|---|---|
<one row per signal, sorted rule_id ASC / path ASC>

<per-rule sections, emitted in RUBRIC_RULE_ORDER; see below>

## Notes

- <TRUNCATION_WARNING if set>
- <gh-unavailable line if applicable>
- Override rules applied: <list of rule_ids, or "none">
```

**Bundled merged-PRD section** (FR-007 / Decision 4, contract §4):

If `ARCHIVE_CANDIDATES > 0`, render a single section:

```markdown
## Bundled: merged-prd-not-archived (<N> items)

> **Accept or reject as a unit.** Per-item cherry-pick is out of scope for v1 — if the `merged-prd-not-archived` invariant holds for one item, it holds for all. To exclude a specific item, move it to `status: in-progress` manually and re-run the audit.

` ``diff
<one unified-diff hunk per archive-candidate signal, sorted by filename ASC>
` ``
```

Each hunk shape (copy the pattern exactly; `git apply` must accept the concatenated block):

```
# rule_id: merged-prd-not-archived — PR #<N> merged <YYYY-MM-DD>
diff --git a/.kiln/issues/<file> b/.kiln/issues/completed/<file>
rename from .kiln/issues/<file>
rename to .kiln/issues/completed/<file>
--- a/.kiln/issues/<file>
+++ b/.kiln/issues/completed/<file>
@@ <frontmatter>
-status: prd-created
+status: completed
+completed_date: <YYYY-MM-DD from gh mergedAt>
+pr: #<N>
```

(For `.kiln/feedback/*.md` candidates, substitute `feedback` for `issues` in both `diff --git` paths and the `rename` lines.)

If `ARCHIVE_CANDIDATES == 0`, the entire `## Bundled: merged-prd-not-archived` section is OMITTED. Do NOT render an empty bundle header.

**Per-rule sections for cheap rules**:

If any `orphaned-top-level-folder` signals fired, render:

```markdown
## Proposed Actions: orphaned-top-level-folder

` ``diff
# rule_id: orphaned-top-level-folder — removal-candidate
# run: git rm -rf <dir>
` ``
```

One code block per fired signal, sorted by path ASC. If zero fired, section is OMITTED.

If any `unreferenced-kiln-artifact` signals fired, render:

```markdown
## Proposed Actions: unreferenced-kiln-artifact

` ``diff
# rule_id: unreferenced-kiln-artifact — removal-candidate
# run: rm <file>
` ``
```

One code block per fired signal, sorted by path ASC. If zero fired, section is OMITTED.

**Notes section**:

- Always rendered. Zero notes case renders the section with a single line `- No notes.` to keep the shape deterministic.
- Override rules applied line: always emitted; `none` if `APPLIED_OVERRIDES` is empty.

**Idempotence** (NFR-002 / SC-006): the only permitted diff between two consecutive runs on unchanged repo state is the single `# … — <timestamp>` header line. Enforce by:

- Sorting Signal Summary rows by `rule_id ASC, path ASC, action ASC`.
- Bundled merged-PRD hunks ordered by filename ASC.
- Per-rule sections emitted in `RUBRIC_RULE_ORDER` (top-to-bottom rubric order).
- Never embed wall-clock time, random IDs, or PIDs outside the header.

## Step 7 — Report to the user

Print a single line summarising the result and exit 0:

```
structural hygiene: <N signals | no drift> → .kiln/logs/structural-hygiene-<TIMESTAMP>.md
```

Exit 0 regardless of signal count. Non-zero exit only on rubric-resolution failure (Step 1).

## Rules

- The skill ONLY proposes a diff or a command block. It MUST NOT call the Edit/Write tools, in-place sed (`-i`), in-place perl (`-i`), directory-renaming moves against backlog paths, `git mv`, or `git apply` against issue/feedback paths. SC-005 greps this file for those imperative patterns — zero hits allowed.
- The rubric is parsed fresh on every invocation — no caching.
- If the rubric resolves but is malformed (no `### <rule_id>` entries), exit non-zero with the parse failure printed. Malformed rubric is a real bug, not drift.
- `gh` calls are limited to a single `gh pr list` per invocation (contract §5). Do NOT fan out one `gh` call per item.
- Graceful degradation (FR-006): `gh` unavailable or unauthenticated marks every `merged-prd-not-archived` candidate as `inconclusive` with one Notes line; exit code stays 0.
- Performance budget: no hard target for the full audit (opt-in, editorial). The <2s budget applies ONLY to `/kiln:kiln-doctor` subcheck 3h, not here.
- Reference: `plugin-kiln/rubrics/structural-hygiene.md` is the single source of truth for which rules run and what their actions are. Skill body must not hardcode rule IDs outside the predicate dispatch.

---

## Step B — Backfill Subcommand (FR-009, FR-010, FR-011 — spec `prd-derived-from-frontmatter`)

Runs ONLY when Step 0 dispatched to `backfill`. Proposes `derived_from:` frontmatter for every PRD that lacks it. **Propose-don't-apply** — the subcommand writes a single review preview at `.kiln/logs/prd-derived-from-backfill-<timestamp>.md` and exits. NEVER calls `Edit`/`Write`/`perl -i`/`sed -i`/`git mv`/`git apply` against any PRD file.

### Step B.1 — Preamble + output path

```bash
TIMESTAMP="$(date -u +%Y-%m-%dT%H-%M-%SZ)"
OUT=".kiln/logs/prd-derived-from-backfill-${TIMESTAMP}.md"
mkdir -p .kiln/logs

HUNKS_FILE="$(mktemp -t derived-from-backfill.XXXXXX)"
HUNK_COUNT=0
```

The `read_derived_from()` helper function defined in Step 5c is reused here (same shell — the helper is still in scope).

### Step B.2 — Walk PRDs + compose diff hunks

```bash
for prd_file in docs/features/*/PRD.md products/*/features/*/PRD.md; do
  [ -f "$prd_file" ] || continue

  # Idempotence predicate (FR-010): skip if frontmatter already carries derived_from:
  # Matches both block-sequence form (derived_from:) and inline empty-list form (derived_from: []).
  if head -20 "$prd_file" | grep -Eq '^derived_from:[[:space:]]*(\[\])?[[:space:]]*$'; then
    continue
  fi

  # Parse ### Source Issues table — extract the first column's markdown-link target.
  # POSIX-portable: avoids gawk's 3-arg match() by using RSTART/RLENGTH + substr.
  table_rows="$(awk '
    /^### Source Issues/ { in_table = 1; next }
    in_table && /^## / { exit }
    in_table && /^\|[[:space:]]*[0-9]+[[:space:]]*\|/ {
      s = $0
      if (match(s, /\]\([^)]+\)/)) {
        frag = substr(s, RSTART, RLENGTH)
        sub(/^\]\(/, "", frag)
        sub(/\)$/, "", frag)
        print frag
      }
    }
  ' "$prd_file")"

  # No parseable table → nothing to backfill (hand-authored PRD with no backlog origin).
  [ -z "$table_rows" ] && continue

  # Sort feedback-first, then issues, then filename ASC within each group.
  derived_lines="$(
    {
      printf '%s\n' "$table_rows" | grep -E '^\.kiln/feedback/' | sort
      printf '%s\n' "$table_rows" | grep -E '^\.kiln/issues/' | sort
    }
  )"

  # Derive theme from directory basename (YYYY-MM-DD-<slug> → <slug>).
  prd_dir="$(dirname "$prd_file")"
  theme="$(basename "$prd_dir" | sed -E 's:^[0-9]{4}-[0-9]{2}-[0-9]{2}-::')"

  # Derive distilled_date from body **Date**: line; fall back to file mtime (Decision D2).
  date_line="$(grep -m1 '^\*\*Date\*\*:' "$prd_file" | sed -E 's/^\*\*Date\*\*:[[:space:]]*//; s/[[:space:]]+$//')"
  if [ -z "$date_line" ]; then
    date_line="$(date -u -r "$prd_file" +%Y-%m-%d 2>/dev/null || date -u +%Y-%m-%d)"
    date_note="  # distilled_date inferred from file mtime — review"
  else
    date_note=""
  fi

  # Compose the candidate frontmatter block as a unified-diff hunk.
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
        # Path-validation: row path does not exist — annotate, do not include raw.
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
```

### Step B.3 — Write the bundled preview

```bash
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
    # Sort by PRD path ASC (the "### diff --- " header carries the path).
    sort "$HUNKS_FILE" | awk '/^### diff --- / { print "---"; print ""; print } !/^### diff --- / { print }'
  fi
} > "$OUT"

rm -f "$HUNKS_FILE"

echo "Wrote: $OUT"
echo "Bundled hunks: $HUNK_COUNT"
```

### Step B.4 — Exit

```bash
exit 0
```

No commit, no git operations — the maintainer reviews `$OUT` and applies hunks manually.

### Invariants (FR-009, FR-010, FR-011)

- The subcommand NEVER calls `Edit`/`Write`/`perl -i`/`sed -i`/`git mv`/`git apply` against any `docs/features/*/PRD.md` or `products/*/features/*/PRD.md`. Only writes `$OUT`.
- Idempotence (FR-010): a second invocation on the same repo state produces `Bundled: derived_from-backfill (0 items)`. The `head -20 | grep -Eq '^derived_from:'` predicate matches both block-sequence (`derived_from:`) and inline empty-list (`derived_from: []`) forms — both treated as already-migrated.
- Product-level PRD paths (`products/*/features/*/PRD.md`) follow the same shape (FR-011) — no special-case logic.
- Non-existent `### Source Issues` paths are annotated inline with `# path does not exist on disk — review`; the maintainer decides whether to keep, drop, or fix during review.
