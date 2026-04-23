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

## Step 1 — Resolve paths

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

## Step 4 — Write the output file

Write to `.kiln/logs/claude-md-audit-<TIMESTAMP>.md` using the exact shape from contract §2:

```markdown
# CLAUDE.md Audit — <YYYY-MM-DD HH:MM:SS>

**Audited file(s)**: <comma-separated path list>
**Rubric**: plugin-kiln/rubrics/claude-md-usefulness.md (+ .kiln/claude-md-audit.config if present)
**Result**: <no drift | N signals>

## Signal Summary

| rule_id | cost | signal_type | action | count |
|---|---|---|---|---|
| ... | ... | ... | ... | ... |

## Proposed Diff

` ``diff
<unified-diff body, git-diff --no-index shape>
` ``

## Notes

- Editorial signals marked `inconclusive` if LLM call failed (edge case in spec).
- Override rules applied: <rule_id list, or "none">.
```

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

- The skill ONLY proposes a diff. It MUST NOT call `Edit`, `Write`, `sed -i`, `perl -i`, or `git apply` against CLAUDE.md. The maintainer applies changes manually after reviewing `.kiln/logs/claude-md-audit-<timestamp>.md`.
- Every audited file is read fresh on each invocation — no caching of the source file body.
- If the rubric is present but malformed (cannot be parsed into rule entries), print the exact parse error and exit non-zero. Do not default-to-empty — malformed rubric is a real bug, not drift.
- Editorial LLM calls have no latency target for this skill (the `<2s` budget applies only to the `/kiln:kiln-doctor` subcheck, not here). Spend the tokens; this skill is opt-in.
- `load-bearing-section` always wins over any other rule for the same section.
