---
name: kiln-claude-audit
description: Audit CLAUDE.md against the kiln usefulness rubric and propose a git-diff-shaped removal/archival diff. Runs the full rubric (cheap + editorial signals). Never applies edits — output goes to .kiln/logs/ for human review.
---

# Kiln CLAUDE.md Audit — Propose Drift Diff

Reads the current repo's `CLAUDE.md` (and `plugin-kiln/scaffold/CLAUDE.md` when run inside the plugin source repo), evaluates every rule in `plugin-kiln/rubrics/claude-md-usefulness.md`, and writes a git-diff-shaped proposal to `.kiln/logs/claude-md-audit-<timestamp>.md`. **This skill never applies edits.** The maintainer reviews the output and chooses which findings to accept.

Contracts:
- Rubric schema + required rules — `specs/kiln-self-maintenance/contracts/interfaces.md` §1.
- Output file shape — §2 of the same file.
- Optional override — `.kiln/claude-md-audit.config`, shape in §7.
- Editorial signals must be marked `inconclusive` if the LLM call fails (spec edge case).
- Idempotent output — two runs on unchanged inputs produce byte-identical Signal Summary + Proposed Diff bodies (NFR-002).

## User Input

```text
$ARGUMENTS
```

Supported flag: `--config <path>` — point the skill at an override file other than `.kiln/claude-md-audit.config`. No other flags; no required args.

## Step 1 — Load project-context snapshot (coach-driven-capture FR-013)

<!-- coach-driven-capture FR-013: consume ProjectContextSnapshot before applying
     the usefulness rubric. Extract commands / tech-stack / active phase / gotchas
     and cite at least one signal in the preview log.
     Contract: specs/coach-driven-capture-ergonomics/contracts/interfaces.md. -->

```bash
READER="plugin-kiln/scripts/context/read-project-context.sh"
if [ -x "$READER" ] || [ -f "$READER" ]; then
  CTX_JSON=$(bash "$READER" 2>/dev/null) || CTX_JSON=""
fi
if [ -z "${CTX_JSON:-}" ]; then
  # Pre-Phase-1 fallback — degrade to empty snapshot rather than fail the audit.
  CTX_JSON='{"schema_version":"1","prds":[],"roadmap_items":[],"roadmap_phases":[],"vision":null,"claude_md":null,"readme":null,"plugins":[]}'
  echo "warn: project-context reader unavailable; audit will proceed without grounding" >&2
fi

# FR-013 signals extracted for later citation in the preview log
CURRENT_PHASE=$(echo "$CTX_JSON" | jq -r '.roadmap_phases[] | select(.status=="in-progress") | .name // empty' | head -1)
PLUGIN_NAMES=$(echo "$CTX_JSON" | jq -r '.plugins[].name' | paste -sd',' -)
PRD_COUNT=$(echo "$CTX_JSON" | jq -r '.prds | length')
```

These variables feed the Signal Summary Notes section and the "## External
best-practices deltas" subsection in Step 4.

## Step 1b — Resolve paths

Set these variables in order. Fail fast with the exact error message when required inputs are missing.

**CLAUDE_MD_PATH**:
```bash
# Source repo: both the real CLAUDE.md and the scaffold get audited.
# Consumer repo: only the consumer CLAUDE.md at repo root.
AUDIT_PATHS=()
if [ -f "CLAUDE.md" ]; then AUDIT_PATHS+=("CLAUDE.md"); fi
if [ -f "plugin-kiln/scaffold/CLAUDE.md" ]; then
  AUDIT_PATHS+=("plugin-kiln/scaffold/CLAUDE.md")
fi
if [ ${#AUDIT_PATHS[@]} -eq 0 ]; then
  echo "no CLAUDE.md found at repo root; aborting" >&2
  exit 1
fi
```

**RUBRIC_PATH**: the plugin-embedded rubric. Resolution order:
1. `$CLAUDE_PLUGIN_ROOT/rubrics/claude-md-usefulness.md` (when invoked via a hook env).
2. `plugin-kiln/rubrics/claude-md-usefulness.md` (source-repo checkout).
3. `~/.claude/plugins/cache/*/kiln/*/rubrics/claude-md-usefulness.md` (consumer install — first `find` hit).
4. `$(npm root -g)/@yoshisada/kiln/rubrics/claude-md-usefulness.md` (legacy npm install).

If none resolve, exit 1 with the exact message from contract §2:

```
rubric not found at <path>; run kiln init or re-install the plugin
```

**OVERRIDE_PATH**: if `--config <path>` is passed, use that; else `.kiln/claude-md-audit.config` if present; else none.

**BEST_PRACTICES_CACHE**: `plugin-kiln/rubrics/claude-md-best-practices.md`. Required by the coach-driven-capture feature (FR-014 / FR-015). If absent, `/kiln:kiln-claude-audit` aborts with `best-practices cache missing at plugin-kiln/rubrics/claude-md-best-practices.md; re-install the plugin`. Parse its frontmatter to extract `fetched:` (ISO date) and `cache_ttl_days:` (integer — default 30 if absent).

**TIMESTAMP**: `date +%Y-%m-%d-%H%M%S`. Use this exact format for the output filename.

**OUTPUT_PATH**: `.kiln/logs/claude-md-audit-${TIMESTAMP}.md`. Ensure `.kiln/logs/` exists.

## Step 2 — Load rubric + merge overrides

Parse the rubric:
- Read every `### <rule_id>` heading under the rubric.
- For each rule, extract the fenced YAML-ish key/value block (`rule_id`, `signal_type`, `cost`, `match_rule`, `action`, `rationale`, `cached`).
- Collect the default threshold values from the preamble block (`recent_changes_keep_last_n`, `active_technologies_keep_last_n`, `migration_notice_max_age_days`).

Parse the override (if any) per contract §7:
- One `key = value` or `key: value` per line. `#` begins a comment; blank lines ignored.
- Threshold overrides use the raw name (e.g. `recent_changes_keep_last_n = 10`).
- Rule-level overrides use the `<rule_id>.<field>` shape (e.g. `stale-migration-notice.action = archive-candidate`, `duplicated-in-constitution.enabled = false`).
- Allowed `action` values: `keep | archive-candidate | removal-candidate | duplication-flag`. Reject anything else as malformed.

**Malformed-override behavior** (Decision 1 closing clause): if ANY line fails to parse OR assigns an invalid action value, emit exactly:

```
claude-md-audit.config: unparseable at line N; falling back to plugin defaults
```

…and proceed with plugin defaults ONLY. Do not half-apply. Continue with exit 0 — this is a warning, not a hard failure.

**Unknown rule_id**: if `<rule_id>.<field>` references a rule not in the plugin rubric, emit exactly:

```
claude-md-audit.config: unknown rule_id '<id>' at line N — ignoring
```

…and skip just that line. Other override lines keep applying.

Record the list of rules whose values were changed by the override — this list goes into the Notes section of the output.

## Step 3 — Run rubric rules

For EACH audited file (source-repo case has two), run every rule (both `cost: cheap` and `cost: editorial`). A rule either fires (produces a signal) or does not.

### Cheap rules (grep / line-count only)

**`load-bearing-section`** — never fires as "remove"; only ever emits a signal with action `keep`. Implementation:

```bash
# Find sections cited by name from skills/agents/hooks/workflows/templates.
# A section is cited if its header text (after the leading ##) appears as a phrase
# in any file under plugin-*/skills, plugin-*/agents, plugin-*/hooks,
# plugin-*/workflows, or templates/ — OR if "per CLAUDE.md" / "see CLAUDE.md" appears
# adjacent to a substring that matches a section header.
```

Enumerate sections in the audited file by collecting every `^## ` heading. For each section header text, grep for it across the citation surface. Record `load-bearing-section` signals for each cited section. These later protect those sections from other rules (see "Signal reconciliation" below).

**`stale-migration-notice`** — fires when the file contains a blockquote with `Migration Notice` OR a line matching `renamed from`. Measure age from the git commit that introduced the blockquote:

```bash
git log --reverse --format=%at -- <CLAUDE_MD_PATH> | head -1  # approximate; refine via -S search if needed
```

If `(now - commit_time)` exceeds `migration_notice_max_age_days` (default 60), fire the signal with action `removal-candidate`. Propose a diff that removes the full blockquote plus orphan blank lines around it.

**`recent-changes-overflow`** — count bullets under `## Recent Changes`. If count > `recent_changes_keep_last_n` (default 5), fire with action `archive-candidate`. Proposed diff keeps the top N bullets (entries are assumed newest-first), removes the rest. Include the git ref each removed bullet cites as a comment in the diff so the maintainer can reconstitute.

**`active-technologies-overflow`** — same mechanic as `recent-changes-overflow`, scoped to `## Active Technologies`. Threshold: `active_technologies_keep_last_n` (default 5).

### Editorial rules (LLM calls)

**`duplicated-in-prd`**, **`duplicated-in-constitution`**, **`stale-section`** — each invokes a single LLM call.

For each editorial rule:

1. Read the audited CLAUDE.md file in full.
2. Read the reference document(s):
   - `duplicated-in-prd` → `docs/PRD.md` (if present) + every `products/*/PRD.md` + every `docs/features/*/PRD.md`.
   - `duplicated-in-constitution` → `.specify/memory/constitution.md` (consumer path) OR `plugin-kiln/scaffold/constitution.md` (plugin source repo).
   - `stale-section` → a small inventory: `ls plugin-*/skills/`, `ls plugin-*/agents/`, `ls plugin-*/workflows/`, `ls plugin-*/hooks/`, directly listed so the LLM sees what currently exists.
3. Call the LLM with a prompt that names the rule's `match_rule` + `rationale` from the rubric and asks for a list of section headings whose content fires the rule. Prompt shape:

```
You are evaluating CLAUDE.md section-by-section against rule <rule_id>.

Rule rationale: <rubric rationale>
Rule match: <rubric match_rule>
Known false-positive shape: <rubric prose block for the rule>

<Reference material inline here>

<CLAUDE.md content inline here>

Return a JSON list: [{"section": "## <heading>", "justification": "<1-sentence why the rule fires>"}]
Return an empty list if nothing fires. Do not flag sections that match the known false-positive shape.
```

4. Parse the LLM response. Each returned entry becomes a signal with the rule's `action` from the rubric.
5. If the LLM call errors (timeout, parse failure, rate-limit), record ONE signal for the rule with action `inconclusive` and a Notes-section line `editorial rule <rule_id>: LLM unavailable — marked inconclusive`. Do NOT propose a diff for the inconclusive signal — it goes into the Signal Summary as a row but not into the Proposed Diff body.

### Signal reconciliation

After collecting all signals:

- Any signal on a section that ALSO appeared as `load-bearing-section` is demoted: the signal is kept in the Signal Summary table with action `keep (load-bearing)` but no diff is proposed for that section. The `load-bearing-section` rule always wins.
- Duplicate signals for the same section from the same rule collapse into one row with `count: N` = how many spans fired inside that section.

## Step 3b — External best-practices evaluation (coach-driven-capture FR-014, FR-015)

<!-- coach-driven-capture FR-014: evaluate CLAUDE.md against Anthropic's published
     guidance (cached at plugin-kiln/rubrics/claude-md-best-practices.md). Emit a
     dedicated "## External best-practices deltas" subsection with at least one
     finding per run — or an explicit "no deltas found" note.
     coach-driven-capture FR-015: on WebFetch failure → cached copy + single-line
     "cache used, network unreachable" note. Flag staleness when fetched: >30 days.
     NFR-004: network call is OPTIONAL — cached path is always usable. -->

```bash
# 1. Read cache frontmatter
CACHE_FETCHED=$(awk '/^fetched:/ { print $2; exit }' "$BEST_PRACTICES_CACHE" 2>/dev/null)
CACHE_TTL=$(awk '/^cache_ttl_days:/ { print $2; exit }' "$BEST_PRACTICES_CACHE" 2>/dev/null)
CACHE_TTL=${CACHE_TTL:-30}

# 2. Compute cache age (portable — GNU and BSD date)
TODAY_EPOCH=$(date -u +%s)
if [ -n "$CACHE_FETCHED" ]; then
  # Try GNU `date -d`, fallback to BSD `date -j -f`
  FETCHED_EPOCH=$(date -d "$CACHE_FETCHED" +%s 2>/dev/null \
    || date -j -f "%Y-%m-%d" "$CACHE_FETCHED" +%s 2>/dev/null \
    || echo 0)
  CACHE_AGE_DAYS=$(( (TODAY_EPOCH - FETCHED_EPOCH) / 86400 ))
else
  CACHE_AGE_DAYS=9999   # treat missing fetched: as stale
fi

# 3. Attempt live fetch (FR-014). If WebFetch is unavailable (non-Claude-runtime) or fails,
# set BP_SOURCE="cache-fallback". On success, refresh the cache body + fetched: date.
BP_SOURCE="cache"
BP_FETCH_NOTE=""
BP_URL="https://code.claude.com/docs/en/best-practices#write-an-effective-claude-md"
# This skill runs INSIDE Claude Code — the model invokes WebFetch via its tool harness,
# not via a shell command. At SKILL.md-authoring time we document the contract; the model
# executes it. If WebFetch succeeds, the model updates $BEST_PRACTICES_CACHE body +
# frontmatter fetched:, and sets BP_SOURCE="webfetch-refreshed".
# On any failure, the model sets BP_FETCH_NOTE="cache used, network unreachable".

# 4. Staleness flag (FR-015 + Clarification #3)
if [ "$CACHE_AGE_DAYS" -gt "$CACHE_TTL" ]; then
  CACHE_STALE="yes"
else
  CACHE_STALE="no"
fi
```

**AI step** (inside the SKILL body, not bash): attempt `WebFetch(BP_URL)`. On success, rewrite
the cache body below the frontmatter with the verbatim "Write an effective CLAUDE.md" section,
bump `fetched:` to today's ISO date, and set `BP_SOURCE="webfetch-refreshed"`. On failure
(network error, 404, parse failure), set `BP_FETCH_NOTE="cache used, network unreachable"` and
continue with the existing cache body. Do NOT fail the audit on WebFetch failure — NFR-004
requires graceful degradation.

**Evaluate the audited CLAUDE.md against the cached guidance.** The cache body describes the
five "Derived audit checks" (see `plugin-kiln/rubrics/claude-md-best-practices.md`). For each
check, produce zero-or-more findings with: `section`, `current`, `proposed`, `evidence`. If
all five checks come back clean, emit a single "no deltas found" row instead.

Accumulate these findings into `EXTERNAL_FINDINGS` for rendering in Step 4.

## Step 4 — Write the output file

Write to `.kiln/logs/claude-md-audit-<TIMESTAMP>.md` using the exact shape from contract §2, extended by coach-driven-capture FR-013 (project-context citation) and FR-014 (External best-practices deltas subsection):

```markdown
# CLAUDE.md Audit — <YYYY-MM-DD HH:MM:SS>

**Audited file(s)**: <comma-separated path list>
**Rubric**: plugin-kiln/rubrics/claude-md-usefulness.md (+ .kiln/claude-md-audit.config if present)
**Result**: <no drift | N signals>

## Project Context (FR-013)

- **Active phase**: <CURRENT_PHASE or "(none — no phase in-progress)">
- **Installed plugins**: <PLUGIN_NAMES or "(none)">
- **Shipped PRDs**: <PRD_COUNT>
- **Project-context snapshot**: <path to reader script, or "(reader unavailable)">

At least ONE finding below MUST cite a signal from this block (e.g., a phase drift, a tech-stack mismatch, a stale command reference). This is the FR-013 invariant.

## Signal Summary

| rule_id | cost | signal_type | action | count |
|---|---|---|---|---|
| ... | ... | ... | ... | ... |

## Proposed Diff

` ``diff
<unified-diff body, git-diff --no-index shape>
` ``

## External best-practices deltas (FR-014)

**Source**: plugin-kiln/rubrics/claude-md-best-practices.md (fetched: <CACHE_FETCHED>, age: <CACHE_AGE_DAYS> days, ttl: <CACHE_TTL> days, source: <BP_SOURCE>)
<if CACHE_STALE=="yes">⚠  **Cache stale**: fetched date is older than <CACHE_TTL> days; the audit attempted a fresh WebFetch.</if>
<if BP_FETCH_NOTE non-empty>Note: <BP_FETCH_NOTE></if>

<Table of EXTERNAL_FINDINGS with columns: check | section | current | proposed | evidence. Render exactly one row labelled "no deltas found" when all five derived checks come back clean.>

## Notes

- Editorial signals marked `inconclusive` if LLM call failed (edge case in spec).
- Override rules applied: <rule_id list, or "none">.
- Project-context signals cited in findings: <list CURRENT_PHASE / plugins / etc.>.
```

**Required rendering rules**:

- The `## Project Context` block MUST appear whenever `CTX_JSON` parsed successfully. It's the FR-013 anchor.
- The `## External best-practices deltas` heading MUST appear verbatim — downstream tests grep for this exact string.
- When `CACHE_STALE=="yes"`, the preview MUST contain the word `stale` adjacent to the cache notice — the assertions in `plugin-kiln/tests/claude-audit-cache-stale/` grep for `/stale/i`.
- When `BP_FETCH_NOTE` is non-empty, its exact text (`cache used, network unreachable`) MUST appear in the preview — the assertions in `plugin-kiln/tests/claude-audit-network-fallback/` grep for it.
- At least one finding under External best-practices MUST appear per run, OR an explicit `no deltas found` row. Empty table is a regression.

**No-drift marker** (NFR / SC-001): when the Proposed Diff body is empty (no fired signals, or all signals are `keep`/`inconclusive`), the **Result** header line MUST read exactly:

```
**Result**: no drift
```

…and the Signal Summary table MUST still be rendered (can have zero data rows or only `keep`/`inconclusive` rows). Downstream tests grep for this exact phrase.

**Multi-file case** (source repo): when `AUDIT_PATHS` has two entries, render ONE Signal Summary table with a `file` column inserted at the start, and ONE Proposed Diff block containing both files' diffs stacked. Do NOT write two separate output files.

**Diff body shape**: use `git diff --no-index` style so the output is directly `git apply`-able if the maintainer chooses. Each hunk header includes the rule_id as a comment:

```diff
# rule_id: stale-migration-notice — removes stale migration blockquote older than 60 days
--- a/CLAUDE.md
+++ b/CLAUDE.md
@@ -7,5 +7,0 @@
-> **Migration Notice**: ...
-> Old skill names ...
-> Use the new names ...
-
```

### Idempotence (NFR-002)

Two runs against unchanged inputs MUST produce byte-identical **Signal Summary** rows AND **Proposed Diff** body. The `# ... — <YYYY-MM-DD HH:MM:SS>` header line and the filename will differ (timestamp); everything else must be deterministic.

Enforce this by:
- Sorting signals in the Signal Summary table by `rule_id ASC`, then `section ASC`, then `count DESC`.
- Emitting hunks in the Proposed Diff in the order they appear in the source file (top-to-bottom by line number).
- Never embedding wall-clock time, random IDs, or process PIDs anywhere except the header timestamp.

## Step 5 — Report to the user

Print a single line summarising the result and the output file path, then stop:

```
CLAUDE.md audit: <N signals | no drift> → .kiln/logs/claude-md-audit-<TIMESTAMP>.md
```

Exit 0 on success regardless of how many signals fired. Non-zero exit only on hard failure (missing rubric, unreadable CLAUDE.md after path-resolution succeeded).

## Rules

- The skill ONLY proposes a diff. It MUST NOT call `Edit`, `Write`, `sed -i`, `perl -i`, or `git apply` against CLAUDE.md (coach-driven-capture FR-016). The maintainer applies changes manually after reviewing `.kiln/logs/claude-md-audit-<timestamp>.md`. The *only* files this skill is permitted to modify are:
  - `.kiln/logs/claude-md-audit-<TIMESTAMP>.md` (the preview).
  - `plugin-kiln/rubrics/claude-md-best-practices.md` (cache body + `fetched:` date on a successful WebFetch refresh — FR-014).
  - `.kiln/logs/` (the directory itself, if absent).
- Every audited file is read fresh on each invocation — no caching of the source file body.
- If the rubric is present but malformed (cannot be parsed into rule entries), print the exact parse error and exit non-zero. Do not default-to-empty — malformed rubric is a real bug, not drift.
- Editorial LLM calls have no latency target for this skill (the `<2s` budget applies only to the `/kiln:kiln-doctor` subcheck, not here). Spend the tokens; this skill is opt-in.
- `load-bearing-section` always wins over any other rule for the same section.
- **coach-driven-capture FR-013**: every preview MUST render the `## Project Context` block and cite at least one signal from it in findings. An audit that fails to ground itself in project context is a regression.
- **coach-driven-capture FR-014**: every preview MUST render `## External best-practices deltas` with ≥1 finding row OR an explicit `no deltas found` row. Empty external subsection is a regression.
- **coach-driven-capture FR-015 / NFR-004**: WebFetch failure is expected. The `cache used, network unreachable` note in the preview is the agreed failure signal. The audit MUST NOT exit non-zero on network failure — the cached rubric is always the fallback.
- **coach-driven-capture Clarification #3**: `cache_ttl_days: 30` is the staleness threshold. When exceeded, the preview flags it; the cache remains usable regardless.
