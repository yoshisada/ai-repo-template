# Structural Hygiene Rubric

**Version**: 1 (Apr 2026)
**Consumed by**: `/kiln:kiln-hygiene` (full rubric) and `/kiln:kiln-doctor` subcheck `3h` (cheap-cost rules only).
**Overridable from**: `.kiln/structural-hygiene.config` — per-rule merge, repo values win. See `specs/kiln-structural-hygiene/contracts/interfaces.md` §8 for the config shape.

This rubric is the single source of truth for "does this repo still sit cleanly on its own scaffolding, or has structural drift accumulated?". Each rule has a stable `rule_id`, a `signal_type` (load-bearing, editorial, or freshness), a `cost` (cheap = grep / stat / filesystem only; editorial = `gh`, LLM, or other network-bound calls), a `match_rule` (how the rule fires), an `action` (what the audit preview should propose), and a one-sentence `rationale`. The `cached` field is reserved for a future hash-cache optimization; leave it `false` for now.

A rule is a "signal" when it fires against the audited repo. The audit skill collects all signals, renders them as a single Signal Summary table, and proposes a review preview covering each action. The output is review material for a human — the audit never applies edits itself. (FR-003 of the kiln-structural-hygiene spec.)

## Configurable thresholds

These live under rule entries that reference them. Overridable from `.kiln/structural-hygiene.config` via the raw key name:

- `orphaned-top-level-folder.min_age_days` — default `30`. Consumed by `orphaned-top-level-folder`.
- `unreferenced-kiln-artifact.min_age_days` — default `60`. Consumed by `unreferenced-kiln-artifact`.
- `merged-prd-not-archived.gh_limit` — default `500`. Consumed by `merged-prd-not-archived`; passed to `gh pr list --limit`.

---

## Rules

### merged-prd-not-archived

```yaml
rule_id: merged-prd-not-archived
signal_type: editorial
cost: editorial
match_rule: frontmatter status == prd-created AND prd: points at a real PRD AND gh pr list --state merged contains that PRD's feature-slug
action: archive-candidate
rationale: Backlog items whose PRD already shipped to main are completed work — leaving them in prd-created pollutes distill/next signals and the Obsidian mirror.
cached: false
```

Fires against any file under `.kiln/issues/*.md` or `.kiln/feedback/*.md` whose frontmatter satisfies ALL of:

(a) `status: prd-created`;
(b) `prd:` field points at an existing PRD file under `docs/features/*/PRD.md` or `products/*/PRD.md`;
(c) the PRD's feature-slug matches the `headRefName` of some PR in `gh pr list --state merged` (with the leading `build/` and trailing `-YYYYMMDD` stripped from the branch).

**Primary path (post PRD `derived_from:` frontmatter — `specs/prd-derived-from-frontmatter/spec.md`)**: when a PRD under `docs/features/*/PRD.md` or `products/*/features/*/PRD.md` carries a non-empty `derived_from:` frontmatter list, the rule walks PRDs and emits one signal per listed entry (via the PROCESSED_PRDS dedup set). The walk-backlog loop below becomes the fallback and ONLY processes items whose `prd:` points at a PRD lacking `derived_from:`. Output for the fallback path is byte-identical to the pre-frontmatter behavior (FR-008 / NFR-001 of `prd-derived-from-frontmatter`).

**Bulk-lookup strategy**: see `specs/kiln-structural-hygiene/contracts/interfaces.md` §5. Exactly one `gh pr list --state merged --limit <merged-prd-not-archived.gh_limit>` call per audit invocation, results cached in an in-memory associative array keyed by derived slug. Per-item predicate evaluation is an O(1) map lookup. Graceful degradation: if `gh` is unavailable or unauthenticated, every candidate row is emitted as `inconclusive` with a single Notes-section warning. The skill exits 0 in that case.

**Proposed action** (strict bundle-accept in v1, per Decision 4): flip `status: prd-created` → `status: completed`, insert `completed_date: <gh mergedAt YYYY-MM-DD>`, insert `pr: #<gh number>`, and move the file from `.kiln/issues/<file>` to `.kiln/issues/completed/<file>` (or the analogous `.kiln/feedback/` pair). Rendered in the preview as a SINGLE bundled `## Bundled: merged-prd-not-archived (N items)` section containing one unified-diff hunk per item, sorted by filename ASC. The maintainer either applies the whole diff or none of it.

**Known false-positive shapes**:
- _Squash-merged-then-deleted branch_: the branch no longer exists on GitHub but the PR is still in `gh pr list --state merged` (merged state is terminal). The rule fires normally — this is the intended signal, not a false positive.
- _Feature-slug collision_: two PRDs share a slug (e.g. both named `archive-stuff`). Resolution: the rule matches the `prd:` path first to pick the correct PRD, then resolves that PRD's slug against the in-memory map. If the map has multiple PRs for the same slug, the most recently merged wins (by `mergedAt` DESC ordering from `gh`).
- _PRD path in `prd:` field is empty, malformed, or points at a missing file_: the rule does NOT fire; instead the item surfaces as `needs-review` in the Signal Summary and is explicitly excluded from the bundled archive block. (FR-008.)

### orphaned-top-level-folder

```yaml
rule_id: orphaned-top-level-folder
signal_type: freshness
cost: cheap
match_rule: top-level directory (direct child of repo root) absent from kiln-manifest AND unreferenced across plugin-*/ + templates/ AND mtime > min_age_days
action: removal-candidate
rationale: A quiescent top-level folder that no manifest claims and no skill/agent/hook/workflow references is almost always leftover scaffolding from an abandoned experiment.
cached: false
```

Three predicates, all must hold. Inlined pseudocode (see contracts §6 for the literal bash):

```bash
# (a) manifest-absent: top-level dir not declared under manifest.directories
MANIFEST_DIRS=$(jq -r '.directories | keys[]' plugin-kiln/templates/kiln-manifest.json | sed 's:^\./::; s:/*$::')
TOP_LEVEL_MANIFEST=$(echo "$MANIFEST_DIRS" | awk -F/ '{print $1}' | sort -u)
echo "$TOP_LEVEL_MANIFEST" | grep -Fxq "$dir" && continue  # in manifest — skip

# (b) unreferenced: no literal path-prefix match across plugin-*/ + templates/
if grep -RlF "${dir}/" plugin-*/ templates/ 2>/dev/null | head -1 | grep -q . ; then
  continue  # referenced — not orphan
fi

# (c) mtime > min_age_days (default 30): directory's own mtime, not contents
MIN_AGE="${ORPHANED_MIN_AGE_DAYS:-30}"
find "$dir" -maxdepth 0 -type d -mtime "+$MIN_AGE" | grep -q . || continue
```

Notes: `grep -F` (fixed-string) avoids regex false positives (e.g., `apps` matching `app/`); the trailing slash in the search string forces path-segment matching, not substring. The directory's own mtime bumps only when files inside are added, removed, or renamed — so an actively maintained folder never fires. `.gitkeep`-only folders can still fire because creating the `.gitkeep` bumps the mtime once and then nothing touches it.

**Proposed action**: preview emits a fenced command block `git rm -rf <dir>` for the maintainer to run. The skill NEVER invokes `git rm` itself (propose, don't apply — SC-005).

**Known false-positive shapes**:
- _Quiescent-but-intentional_ scaffold (e.g., a `vendor/` directory that only gets touched during version bumps). Add the directory to the kiln manifest, or disable the rule for this repo via `orphaned-top-level-folder.enabled = false` in `.kiln/structural-hygiene.config`.
- _mtime bumped by shallow clones_: on a fresh `git clone`, every directory's mtime is recent. The rule will under-fire on a just-cloned tree — accepted tradeoff in v1; v2 may switch to `git log -1 --format=%at -- <dir>` if this becomes a real pain.

### unreferenced-kiln-artifact

```yaml
rule_id: unreferenced-kiln-artifact
signal_type: freshness
cost: cheap
match_rule: file under .kiln/logs/, .kiln/qa/*, or .kiln/state/ older than min_age_days AND not referenced by any .wheel/state_*.json
action: removal-candidate
rationale: Per-run artifacts accumulate indefinitely without a hygiene signal; once older than the retention window and no running workflow claims them, they are safe deletions.
cached: false
```

**Scope**: files (not directories) under:

- `.kiln/logs/*`
- `.kiln/qa/test-results/`, `.kiln/qa/playwright-report/`, `.kiln/qa/videos/`, `.kiln/qa/traces/`, `.kiln/qa/screenshots/`, `.kiln/qa/results/`
- `.kiln/state/` (if present)

**Exclusions**:
- Files currently referenced by any `.wheel/state_*.json` (grep -F against the file basename).
- Files with basename `.gitkeep` or `README.md`.

Predicate: `find <dir> -type f -mtime +$MIN_AGE` AND not-grep-matched in wheel state. See contracts §7 for the exact bash.

**Proposed action**: per-file fenced `rm` command block in the preview. The skill never invokes `rm` itself (propose-don't-apply; SC-005).

**Known false-positive shapes**:
- _Artifact actively consumed by a long-running test harness_ — the file is old by stat-mtime but a workflow outside `.wheel/state_*.json` owns it. Add the path to an exclude list via override, or disable the rule for this repo.
- _Run transcripts intentionally retained for compliance_ — raise `unreferenced-kiln-artifact.min_age_days` via `.kiln/structural-hygiene.config`.
