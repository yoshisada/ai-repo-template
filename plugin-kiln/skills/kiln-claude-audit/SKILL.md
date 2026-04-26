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
- For each rule, extract the fenced YAML-ish key/value block (`rule_id`, `signal_type`, `cost`, `match_rule`, `action`, `rationale`, `cached`, plus the new optional fields `classification_input`, `sort_priority`, `target_file`, `render_section`).
- Collect the default threshold values from the preamble block (`recent_changes_keep_last_n`, `active_technologies_keep_last_n`, `migration_notice_max_age_days`).

Parse the override (if any) per contract §7 + claude-md-audit-reframe contracts §2:
- One `key = value` or `key: value` per line. `#` begins a comment; blank lines ignored.
- Threshold overrides use the raw name (e.g. `recent_changes_keep_last_n = 10`).
- Rule-level overrides use the `<rule_id>.<field>` shape (e.g. `stale-migration-notice.action = archive-candidate`, `duplicated-in-constitution.enabled = false`, `benefit-missing.enabled = false`, `hook-claim-mismatch.action = removal-candidate`).
- Allowed `action` values: `keep | archive-candidate | removal-candidate | duplication-flag | expand-candidate | sync-candidate | correction-candidate`. Reject anything else as malformed. (The last three were added by claude-md-audit-reframe per contracts §2.4.)

**New top-level override keys** (claude-md-audit-reframe FR-017, FR-029):

- `exclude_section_from_classification = <regex>, <regex>, ...   # reason: <free text>`
  - Comma-separated POSIX-extended regexes. Sections matching any regex are reclassified as `preference` after the FR-001 LLM call, exempting them from FR-002 / FR-005.
  - Inline `# reason:` is required; missing reason emits a Notes-section warning ("override `exclude_section_from_classification` lacks `# reason:` comment") but the override still applies.
- `exclude_plugin_from_sync = <plugin-name>, <plugin-name>, ...   # reason: <free text>`
  - Comma-separated plugin names matching the `enabledPlugins` list. Listed plugins are skipped during FR-011 enumeration; they do not contribute to `## Plugins`.
  - `# reason:` rule same as above.
- `product_sync = false   # reason: <free text>`
  - Boolean. Default `true` (vision sync runs). When `false`, all `product-*` rules (FR-025, FR-026, FR-027) are suppressed and `## Vision Sync` is not rendered. `## Product` (if present) is classified under FR-001 like any other section.
  - `# reason:` rule same as above.

Parse these by keeping the inline-comment splitter intact: split on the FIRST unquoted `#` and treat everything after as the comment line. The reason text is captured for Notes-section rendering when missing.

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

Record the list of rules whose values were changed by the override — this list goes into the Notes section of the output. Also record the missing-reason warnings keyed by override key for Notes rendering per claude-md-audit-reframe contracts §3.4.

## Step 2.5 — Classify CLAUDE.md sections (claude-md-audit-reframe FR-001..FR-004)

For each audited file (CLAUDE.md and the scaffold variant when applicable), perform a SINGLE editorial LLM call that classifies every `## ` heading into one of: `product | feedback-loop | convention-rationale | plugin-surface | preference | unclassified`.

The classification feeds the new rules in Step 3 (`enumeration-bloat`, `benefit-missing`) — those rules' `classification_input:` field names which class triggers them.

**Why one call, not per-section** (per Decision 3 in `agent-notes/specifier.md`): bounded run time, idempotence guarantee, predictable token spend. Per-section fan-out would be more accurate but blow the budget — and the audit is propose-diff-only, so an occasional misclassification is recoverable via the override surface (FR-017).

**Prompt shape** (issued once per audited file):

```
You are classifying every `## ` section of a CLAUDE.md file. Each section header is one row. For each row, return exactly one classification from this enum:

- product: section describes WHAT the product is (mission, target user, jobs, non-goals, north-star, differentiator). Strategic narrative, not pipeline ops.
- feedback-loop: section describes HOW captured items become PRDs become code (issues, feedback, roadmap, mistakes, distill chain). The product's iteration mechanic.
- convention-rationale: section describes a workflow rule with a stated reason ("you must do X because Y"). Includes the constitution / 4-gate / mandatory-workflow patterns.
- plugin-surface: section enumerates skills, agents, commands, hooks, workflows, or templates. Anything Claude already receives at runtime as available context. (`## Available Commands`, `## Agents`, `## Hooks`, etc.)
- preference: section is a maintainer preference unrelated to drift (custom workflow, project-specific snippet, opt-in style). When in doubt between preference and plugin-surface, choose plugin-surface — preference is a small bucket.
- unclassified: section does not fit any of the above (default — used only when none of the above plausibly fits).

For each section header, output one line: `## <heading>\t<classification>`. Use a literal tab between heading and classification. Return one line per section in input order. Do not output any other text.

Sections to classify:
<one heading per line, in source order>
```

Parse the response into a map `{ "## <heading>": "<class>" }`.

**Apply override AFTER LLM** (FR-017 + FR-003): if `exclude_section_from_classification` is set, for each section heading, if any of the configured regexes matches the heading line (anchored at `^## ` to mirror grammar §2.1), reclassify the section as `preference` regardless of LLM output.

**Failure handling** (FR-004): if the LLM call errors, times out, or returns malformed output, mark ALL sections as `unclassified`. Each `unclassified` section MUST appear in the Notes section per contracts §3.4: `Section "<heading>" could not be classified by editorial LLM — defaulting to unclassified (FR-004)`. The audit MUST NOT propose a removal diff for an `unclassified` section — default action is `keep`.

Record the map keyed by audited-file path; downstream rules read it via lookup.

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

### Reframe rules (claude-md-audit-reframe FR-002, FR-005..FR-008, FR-025, FR-027)

These rules layer on the classification map from Step 2.5. Run them after the existing rules above so reconciliation can compare signals.

**`enumeration-bloat`** (cheap input + editorial framing — FR-002): for each `## ` section in the audited file, look up the classification. When `classification == plugin-surface` AND the section was NOT reclassified to `preference` by `exclude_section_from_classification`, fire the signal. Action: `removal-candidate`. Justification text MUST be verbatim: `Claude receives available skills / agents / commands via runtime context.` The diff proposes removing the entire section (heading + body up to the next `## ` heading or EOF).

**`hook-claim-mismatch`** (cheap+editorial hybrid — FR-007, FR-008): two-pass static-only check.

1. Cheap claim extraction: scan CLAUDE.md for sentences mentioning `hook` (case-insensitive) plus an enforcement verb (`block`, `bump`, `enforce`, `prevent`, `gate`, `require`, `auto-`) OR naming a `*-hook` / `<name>.sh` token. Collect candidate `(claim_text, named_hook?)` pairs.
2. For each candidate, grep `plugin-*/hooks/*.sh` for the named hook (filename token) AND any keywords from the claim. If grep returns 0 hits across all `plugin-*/hooks/` directories, fire `hook-claim-mismatch` with action `correction-candidate`. Notes the claim text + the directories searched.

Per FR-008, scope is **static text presence only**. Semantic verification is out of scope; jq-filter false negatives are accepted. Fire one signal per orphan claim.

**`product-undefined`** (cheap — FR-025, sort_priority: top): fires once per audit when CLAUDE.md has no `## Product` section AND `.kiln/vision.md` does not exist (`! [ -f .kiln/vision.md ]`). Action: `expand-candidate`. The proposed diff is COMBINED:

- Creates `.kiln/vision.md` from `plugin-kiln/templates/vision-template.md` (or, when running consumer-side and the template isn't available, a minimal 7-slot scaffold).
- Adds a placeholder `## Product` section to CLAUDE.md at the file's end (or a deterministic anchor — after `## Quick Start` if present, else just before `## Recent Changes` if present, else at EOF).

When fired, this signal MUST appear at row 1 of the Signal Summary table per `sort_priority: top` (see Step 4 sort wiring).

**`product-section-stale`** (cheap — FR-027): when `.kiln/vision.md` exists AND CLAUDE.md has a `## Product` section, compose the synced section per FR-023 region rules + FR-028 header demotion (see Step 3.5 below for the composer), then byte-compare against the current `## Product` body. Differing bodies fire with `sync-candidate`; the diff replaces the whole section in one hunk.

**Sub-signal — vision overlong without markers** (per spec.md Edge Cases): when `vision.md` is >40 lines AND has no `<!-- claude-md-sync:start --> ... <!-- claude-md-sync:end -->` markers, fire under `product-section-stale` with `signal_type: freshness`, action: `expand-candidate`, justification `vision.md is N lines without claude-md-sync markers — add markers around the summary region for managed sync`. Do NOT propose mirroring the full long file.

**`benefit-missing`** (editorial — FR-005): for each section classified as `convention-rationale` or `feedback-loop`:

1. Cheap pre-filter: grep the section body (lines from `## <heading>` exclusive to next `## ` or EOF) for any of: `because`, `without this`, `prevents`, `so that`, `Why:` (case-insensitive). If any match, the rule does NOT fire — short-circuit without an LLM call.
2. Editorial LLM call (only if pre-filter found nothing): pass the section body and ask whether ANY sentence in the body provides a rationale. Prompt: `Does the section body below contain at least one sentence answering "why does this convention exist"? Reply only yes or no. Treat lists of facts as not-a-rationale; rationale must be motivational.`. If `no`, fire with action `expand-candidate`. The diff inserts a placeholder line `Why: <reason — fill in>` at the end of the section.

On LLM failure for a single section, mark `inconclusive` per the existing convention; do not propose a diff for that section.

**`loop-incomplete`** (editorial — FR-006): once-per-file rule.

1. Cheap pre-check (gates the LLM call): `find .kiln/issues .kiln/feedback .kiln/roadmap/items .kiln/mistakes .kiln/fixes -mindepth 1 -name '*.md' -print -quit 2>/dev/null` — if EMPTY, the rule does not fire (no capture surfaces populated).
2. If at least one capture surface is populated, `grep -F /kiln:kiln-distill CLAUDE.md` — if hits, the rule does not fire.
3. If no `/kiln:kiln-distill` mention but capture surfaces are populated, issue an editorial LLM call: `The repo has populated capture surfaces (issues / feedback / roadmap / mistakes / fixes). Does the CLAUDE.md content below name a canonical consumer of those surfaces — by command name, by chain (issues → PRDs → code), or by equivalent narrative? Reply only yes or no.` Pass CLAUDE.md body. If `no`, fire `loop-incomplete` with action `expand-candidate`. The diff inserts a paragraph naming `/kiln:kiln-distill` and the PRD → spec → code chain (placement: at the end of the existing capture-surface section, or as a new `## Capture loop` section after `## Quick Start`).

**`product-slot-missing`** (editorial — FR-026, target_file: `.kiln/vision.md`, render_section: `Vision.md Coverage`): runs only when `.kiln/vision.md` exists AND `product_sync` is not `false`. Reads vision.md and asks the LLM to evaluate each of the 7 slots from FR-024:

1. One-line product summary
2. Primary target user (+ optional secondary)
3. Top 3 jobs-to-be-done
4. Non-goals (what the product is NOT)
5. Current phase (pre-launch | early-access | maturing | mature | end-of-life)
6. North-star metric / success shape
7. Key differentiator

For each slot, the LLM returns `filled` or `missing|placeholder` plus a one-sentence justification. Empty slots fire one signal each with action `expand-candidate`. Findings render under a dedicated `### Vision.md Coverage` table (see Step 4 §3.2) with one row per slot — even slots that did NOT fire (rendered as ✅ filled rows) — so the maintainer sees full coverage shape every run.

## Step 3.5 — Plugin & vision sync composers (FR-011..FR-016, FR-022..FR-029)

These produce the candidate `## Plugins` and `## Product` section bodies. They run once per audit; downstream they feed Step 4's diff renderer.

### Plugin enumeration + path resolution (contracts §5, §6)

```bash
# Enumeration — union of project + user enabled plugins (FR-011)
PROJECT_ENABLED=$(jq -r '.enabledPlugins // [] | .[]' .claude/settings.json 2>/dev/null || true)
USER_ENABLED=$(jq -r '.enabledPlugins // [] | .[]' ~/.claude/settings.json 2>/dev/null || true)
ENABLED_PLUGINS=$( { printf '%s\n' "$PROJECT_ENABLED"; printf '%s\n' "$USER_ENABLED"; } \
                  | grep -v '^$' | sort -u | LC_ALL=C sort )

# Apply exclude_plugin_from_sync override (FR-017)
if [ -n "${EXCLUDE_PLUGIN_FROM_SYNC:-}" ]; then
  for excl in $EXCLUDE_PLUGIN_FROM_SYNC; do
    ENABLED_PLUGINS=$(printf '%s\n' "$ENABLED_PLUGINS" | grep -Fxv "$excl" || true)
  done
fi
```

For each enabled plugin, resolve the install path per FR-012:

1. **Source-repo mode**: `plugin-<name>/` directory at repo root → `plugin-<name>/.claude-plugin/claude-guidance.md`.
2. **Consumer mode (versioned)**: `~/.claude/plugins/cache/<org>-<marketplace>/<plugin-name>/<version>/.claude-plugin/claude-guidance.md` matching the version declared in settings.
3. **Consumer mode (fallback)**: highest-cached-version dir under `~/.claude/plugins/cache/<org>-<marketplace>/<plugin-name>/`.

If none resolve, the plugin is skipped silently per FR-013 (no signal, no warning). Track skipped plugins for the `## Plugins Sync` Notes line.

**Empty / malformed guidance file** (per spec.md Edge Cases): treat as missing — silent skip + Notes-section line `Plugin <name>: guidance file empty/malformed at <path>; skipped.`

### `## Plugins` section composer (FR-014)

For each plugin with a resolved guidance file (alphabetical order, LC_ALL=C):

1. Read the file body.
2. Demote headings: `## When to use` → `#### When to use`; `## Key feedback loop` → `#### Key feedback loop`; `## Non-obvious behavior` → `#### Non-obvious behavior`. Other heading levels are preserved (no rewriting).
3. Emit:

```markdown
### <plugin-name>

<demoted body>

```

Concatenate all plugin subsections under a single `## Plugins` heading. The composed section is the candidate body for FR-015's diff.

### vision.md region selection + composer (FR-022..FR-029)

```bash
VISION_PATH=".kiln/vision.md"
if [ ! -f "$VISION_PATH" ] || [ "${PRODUCT_SYNC:-true}" = "false" ]; then
  # No-op for sync; product-undefined / product_sync override handles signaling.
  VISION_REGION=""
else
  LINE_COUNT=$(wc -l < "$VISION_PATH" | tr -d ' ')
  if grep -q '<!-- claude-md-sync:start -->' "$VISION_PATH"; then
    VISION_REGION=$(awk '/<!-- claude-md-sync:start -->/{flag=1; next} /<!-- claude-md-sync:end -->/{flag=0} flag' "$VISION_PATH")
    REGION_KIND="fenced"
  elif [ "$LINE_COUNT" -le 40 ]; then
    VISION_REGION=$(cat "$VISION_PATH")
    REGION_KIND="full-file"
  else
    # Overlong without markers — sub-signal fires (Step 3 handles); no sync proposed.
    VISION_REGION=""
    REGION_KIND="overlong-unmarked"
  fi
fi
```

When `VISION_REGION` is non-empty, demote per FR-028: top-level `# <title>` → `## Product` (drop the title, replace with literal `## Product` heading); each `## <subhead>` inside the region → `### <subhead>`. Other heading levels are preserved.

The composed body is the candidate `## Product` section. Compare against the current `## Product` body in CLAUDE.md byte-for-byte; differences fire `product-section-stale` (Step 3) AND drive the diff in Step 4.

### Reconciliation (FR-031, extends existing)

After collecting all signals (existing + reframe):

- Any signal on a section that ALSO appeared as `load-bearing-section` is demoted: the signal is kept in the Signal Summary table with action `keep (load-bearing)` but no diff is proposed for that section. **EXCEPT** signals with `rule_id == enumeration-bloat`: those WIN over `load-bearing-section`. The diff IS proposed.
- Signals with `rule_id` starting `product-` never conflict with `load-bearing-section` (the `## Product` section is machine-managed and never load-bearing).
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

Write to `.kiln/logs/claude-md-audit-<TIMESTAMP>.md` using the exact shape from contract §2, extended by coach-driven-capture FR-013 (project-context citation), FR-014 (External best-practices deltas subsection), and claude-md-audit-reframe contracts §3 (`## Plugins Sync`, `## Vision Sync`, `### Vision.md Coverage`):

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

## Plugins Sync

**Enabled plugins** (project + user settings union): <comma-separated list, alphabetical, LC_ALL=C>
**Excluded by override**: <comma-separated list from FR-017's `exclude_plugin_from_sync`, or "(none)">
**Plugins with guidance file**: <comma-separated list>
**Plugins skipped (no guidance file)**: <comma-separated list>

<status line — exactly one of:>
- ✅ `## Plugins` section is in sync.
- ➕ Proposed: insert `## Plugins` section (N plugin entries).
- 🔄 Proposed: replace `## Plugins` section (N additions, M removals from existing subsections).
- ➖ Proposed: remove `## Plugins` section (no enabled plugins have guidance).

> This section is auto-synced from per-plugin `.claude-plugin/claude-guidance.md` files. Edit the plugins, not CLAUDE.md, for persistent changes.

## Vision Sync

**Source**: .kiln/vision.md (<line count> lines, <fenced | full-file | absent | overlong-unmarked>)
**Sync status**: <exactly one of:>
- ✅ `## Product` section is in sync.
- ➕ Proposed: insert `## Product` section from vision.md.
- 🔄 Proposed: replace `## Product` section.
- ⚠ `vision.md` is >40 lines without `<!-- claude-md-sync:start --> ... <!-- claude-md-sync:end -->` markers — sub-signal fired (see Signal Summary).
- 🚫 `product_sync = false` — vision sync skipped (reason: <reason from override>).

### Vision.md Coverage

<rendered when `product-slot-missing` ran AND vision.md exists>

| Slot # | Slot name | Status | Justification |
|---|---|---|---|
| 1 | One-line product summary | ✅ filled | (or one-line LLM justification when missing) |
| 2 | Primary target user | ❌ missing | <justification> |
| 3 | Top 3 jobs-to-be-done | ✅ filled | |
| 4 | Non-goals | ❌ missing | <justification> |
| 5 | Current phase | ✅ filled | |
| 6 | North-star metric | ✅ filled | |
| 7 | Key differentiator | ✅ filled | |

The 7 slots from FR-024 MUST be enumerated in this exact fixed order, even slots that did not fire (rendered as ✅).

## External best-practices deltas (FR-014)

**Source**: plugin-kiln/rubrics/claude-md-best-practices.md (fetched: <CACHE_FETCHED>, age: <CACHE_AGE_DAYS> days, ttl: <CACHE_TTL> days, source: <BP_SOURCE>)
<if CACHE_STALE=="yes">⚠  **Cache stale**: fetched date is older than <CACHE_TTL> days; the audit attempted a fresh WebFetch.</if>
<if BP_FETCH_NOTE non-empty>Note: <BP_FETCH_NOTE></if>

<Table of EXTERNAL_FINDINGS with columns: check | section | current | proposed | evidence. Render exactly one row labelled "no deltas found" when all five derived checks come back clean.>

## Notes

- Editorial signals marked `inconclusive` if LLM call failed (edge case in spec).
- Override rules applied: <rule_id list, or "none">.
- Project-context signals cited in findings: <list CURRENT_PHASE / plugins / etc.>.
- External alignment: <https://code.claude.com/docs/en/best-practices#write-an-effective-claude-md>
- <FR-016 reminder, ONLY when `## Plugins Sync` fires a non-✅ status: "This section is auto-synced from per-plugin `.claude-plugin/claude-guidance.md` files. Edit the plugins, not CLAUDE.md, for persistent changes." — de-duplicated against the `## Plugins Sync` blockquote.>
- <Per-override missing-reason warnings, one line each: "Override `<key>` lacks `# reason:` comment — applied with no documented rationale.">
- <Per LLM-failed section: "Section `<heading>` could not be classified by editorial LLM — defaulting to `unclassified` (FR-004).">
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
- Sorting signals in the Signal Summary table by `sort_priority DESC` (signals with `sort_priority: top` win — currently only `product-undefined`), then `rule_id ASC`, then `section ASC`, then `count DESC`. Multiple `sort_priority: top` signals sort among themselves by `rule_id ASC`.
- Emitting hunks in the Proposed Diff in the order they appear in the source file (top-to-bottom by line number).
- Plugin enumeration sorted with `LC_ALL=C sort -u`; `## Plugins` subsections rendered in alphabetical order by plugin name.
- Vision.md Coverage table: 7 slots enumerated in fixed FR-024 order (1..7).
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
- `load-bearing-section` always wins over any other rule for the same section, **EXCEPT** for `enumeration-bloat` (claude-md-audit-reframe FR-031) on `plugin-surface`-classified sections — that rule WINS over load-bearing because re-enumerating runtime-provided context is bloat regardless of citations.
- **claude-md-audit-reframe FR-001..FR-004**: Step 2.5 issues a single classification LLM call per audited file. On failure, all sections default to `unclassified` with action `keep` — never propose a removal diff for an unclassified section.
- **claude-md-audit-reframe FR-013**: a plugin without `.claude-plugin/claude-guidance.md` is silently skipped — no signal, no warning. Empty / malformed guidance file → also silent skip + Notes-section line.
- **claude-md-audit-reframe FR-016 / FR-022**: `## Plugins` and `## Product` are MACHINE-MANAGED sections. Manual edits to either MUST be reverted on next sync. The audit proposes the diff; the maintainer applies it; subsequent audits keep the section in sync.
- **claude-md-audit-reframe FR-018 / SC-009**: every preview MUST cite the Anthropic best-practices URL (https://code.claude.com/docs/en/best-practices#write-an-effective-claude-md) exactly once in the Notes section, regardless of which rules fired.
- **claude-md-audit-reframe FR-025 / SC-007**: when `product-undefined` fires, its row appears at the top of the Signal Summary table (per `sort_priority: top`).
- **claude-md-audit-reframe NFR-002 / SC-006**: idempotence extends to `## Plugins Sync` and `## Vision Sync` bodies — two runs on unchanged inputs produce byte-identical bodies (timestamp line excepted).
- **coach-driven-capture FR-013**: every preview MUST render the `## Project Context` block and cite at least one signal from it in findings. An audit that fails to ground itself in project context is a regression.
- **coach-driven-capture FR-014**: every preview MUST render `## External best-practices deltas` with ≥1 finding row OR an explicit `no deltas found` row. Empty external subsection is a regression.
- **coach-driven-capture FR-015 / NFR-004**: WebFetch failure is expected. The `cache used, network unreachable` note in the preview is the agreed failure signal. The audit MUST NOT exit non-zero on network failure — the cached rubric is always the fallback.
- **coach-driven-capture Clarification #3**: `cache_ttl_days: 30` is the staleness threshold. When exceeded, the preview flags it; the cache remains usable regardless.
