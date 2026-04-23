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

Supported flag: `--config <path>` — point the skill at an override file other than `.kiln/structural-hygiene.config`. No other flags; no required args.

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
  done < <(find . -maxdepth 1 -mindepth 1 -type d ! -name '.git' ! -name 'node_modules' -printf '%f\n')
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

> **Filled in by Phase D.** This step is a no-op in the Phase B scaffold commit. See Phase D of `specs/kiln-structural-hygiene/tasks.md` for the gh-bulk-lookup + per-item predicate; contract §5 is the authoritative signature.

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

**Bundled merged-PRD section** (FR-007 / Decision 4): filled in by Phase D. In the Phase B scaffold, the bundled section is always OMITTED because Step 5c emits no signals yet.

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
