# Implementation Plan: Kiln Structural Hygiene

**Branch**: `build/kiln-structural-hygiene-20260423` | **Date**: 2026-04-23 | **Spec**: [spec.md](./spec.md)
**Input**: PRD at `docs/features/2026-04-23-kiln-structural-hygiene/PRD.md`

## Summary

Extend kiln's self-maintenance surface from today's narrow `/kiln:kiln-cleanup` (QA-artifact purge) + `/kiln:kiln-doctor` (manifest validation) story into a first-class **structural hygiene** layer. Ship a versioned rubric (`plugin-kiln/rubrics/structural-hygiene.md`), a dedicated audit skill that produces a review preview but never applies edits, a cheap subcheck wired into `/kiln:kiln-doctor` at position `3h`, and a concrete `merged-prd-not-archived` rule that would have caught the 18 items that leaked this month. Pattern mirrors PR #141 (`/kiln:kiln-claude-audit`) end-to-end.

## Technical Context

**Language/Version**: Bash 5.x for the skill body; Markdown for rubric + skill definition; `gh` CLI for merged-branch lookup; `jq` for JSON parsing.
**Primary Dependencies**: `gh`, `jq`, `grep`, `find`, `date` — all already assumed. No new runtime deps (NFR-001).
**Storage**: Preview files at `.kiln/logs/structural-hygiene-<timestamp>.md`. No state mutation.
**Testing**: Shell-based fixture harness under `plugin-kiln/skills/kiln-hygiene/tests/` mirroring `plugin-kiln/skills/kiln-claude-audit/tests/` layout. SMOKE test captured at `specs/kiln-structural-hygiene/SMOKE.md`.
**Target Platform**: Developer macOS/Linux shells. `date` usage uses POSIX-portable `%s` math only.
**Project Type**: Single plugin repo; artifacts land under `plugin-kiln/`.
**Performance Goals**: 3h doctor subcheck <2 s. Full hygiene audit no hard target (opt-in).
**Constraints**: Propose-don't-apply (SC-005). Idempotence (NFR-002, SC-006). Backwards compat (NFR-003, SC-007).
**Scale/Scope**: ≤18 tasks, single implementer, single-PR landing.

## Constitution Check

- **I. Spec-First** ✅ — spec.md precedes all code changes, FRs have IDs, acceptance scenarios are Given/When/Then.
- **II. 80% Coverage** ✅ — shell-fixture tests under the skill's `tests/` dir cover each rule fire/no-fire path + gh-degraded path + idempotence.
- **III. PRD as Source** ✅ — PRD at `docs/features/2026-04-23-kiln-structural-hygiene/PRD.md` is the authoritative input; FR IDs trace 1:1.
- **IV. Hooks Enforce** ✅ — no hook changes needed. The 4 Gates already cover `src/` edits; plugin-kiln/ edits are not gated today (same as PR #141).
- **V. E2E Required** ✅ — fixture harness invokes the real skill body end-to-end against real `.kiln/` files.
- **VI. Small Changes** ✅ — skill body target <400 lines. Rubric target <150 lines. No file edited exceeds 500 lines.
- **VII. Interface Contracts** ✅ — `contracts/interfaces.md` locks rubric schema, skill I/O, doctor subcheck signature, both MVP predicates, override config shape.
- **VIII. Incremental Task Completion** ✅ — tasks.md breaks into 5 phases (A–E) with per-phase commits; each task marked `[X]` immediately on completion.

No violations; no complexity tracking entries required.

---

## Locked Decisions

The spec explicitly surfaces five open questions. Each is locked below.

### Decision 1 — Skill shape: new sibling skill

**Locked**: `/kiln:kiln-hygiene` as a new sibling skill at `plugin-kiln/skills/kiln-hygiene/SKILL.md`.

**Rejected alternatives**:
- **Extend `/kiln:kiln-cleanup` with an `--audit` mode.** Rejected: cleanup's semantics today are "purge destructively, dry-run-able". Hygiene's semantics are "propose, never apply". Folding the two muddies the contract and risks users running `--audit` then accidentally omitting the flag. Matches the PRD's "Risks & Open Questions" recommendation.
- **Extend `/kiln:kiln-doctor` with an `--audit-hygiene` mode.** Rejected: doctor is the cheap-signals-only tripwire. Hygiene needs `gh` + file walks — editorial cost. Doctor stays cheap; the sibling skill owns the editorial path. This is the same split landed in PR #141 (doctor 3g cheap / claude-audit full).

**Chosen directory**:
```
plugin-kiln/skills/kiln-hygiene/
  SKILL.md
  tests/
    fixtures/
      fixture-all-rules-fire/
      fixture-no-drift/
      fixture-gh-unavailable/
    harness.sh
```

**Invocation name**: `/kiln:kiln-hygiene`. Description: `Audit the repo against the structural-hygiene rubric and propose a review preview at .kiln/logs/. Never applies edits.` — mirrors `/kiln:kiln-claude-audit`'s one-liner shape.

**User-visible consequence**: `/kiln:kiln-cleanup` stays exactly as it is today. `/kiln:kiln-hygiene` is a new command listed in CLAUDE.md's Available Commands block alongside claude-audit.

---

### Decision 2 — gh rate-limit strategy: one bulk call, in-memory match

**Locked**: Exactly one `gh pr list` invocation per audit run, results cached in an associative array keyed by `headRefName`. Every per-item predicate evaluation is an O(1) lookup against that map.

**Exact command**:
```bash
gh pr list --state merged --limit 500 \
  --json number,headRefName,title,mergedAt \
  --jq '.[] | "\(.headRefName)\t\(.number)\t\(.mergedAt)"' \
  > "$TMPDIR/gh-merged-prs.tsv"
```

**Rejected alternatives**:
- **Per-item `gh pr list --search <slug>`.** Rejected: 18 items = 18 API calls, compounding across audit runs. Violates the PRD's rate-limit concern.
- **`gh pr list --state merged --limit 1000`.** Rejected: pagination adds latency for the median case. v1 caps at 500 with an explicit warning if truncated (see Edge Cases in spec). v2 may raise the cap.

**Cache lifetime**: per-invocation only. The skill never persists the TSV — `$TMPDIR` is wiped on process exit. Rationale: hygiene runs are infrequent; a persistent cache would go stale and silently mask newly-merged PRs.

**Truncation behavior**: if the `gh pr list` result count == 500 (the `--limit`), emit a Notes-section warning (see FR-005 edge case in spec). Do NOT fail.

**gh-unavailable path (FR-006)**:
```bash
if ! command -v gh >/dev/null 2>&1 || ! gh auth status >/dev/null 2>&1; then
  GH_AVAILABLE=false
  # every merged-prd-not-archived candidate marked `inconclusive`
fi
```
No retry, no fallback API path. Mirrors `/kiln:kiln-next` FR-014.

---

### Decision 3 — Orphaned-folder predicate

**Locked**: A top-level directory (direct child of the repo root, excluding `.git/`, `node_modules/`, and every directory listed in `manifest.directories`) is an orphan candidate when ALL of:

**(a) Not declared in the manifest**:
```bash
MANIFEST_DIRS=$(jq -r '.directories | keys[]' plugin-kiln/templates/kiln-manifest.json | sed 's:/*$::')
echo "$MANIFEST_DIRS" | grep -Fxq "$dir"  # expect non-zero = not in manifest
```

**(b) Not referenced by any plugin skill/agent/hook/workflow/template**:
```bash
# Literal path-prefix match across citation surface (plugin-*/ + templates/).
grep -RlF "$dir/" plugin-*/ templates/ 2>/dev/null | head -1   # zero hits = unreferenced
```
Notes:
- `grep -F` (fixed string) avoids regex false positives from names like `tests/` matching `.kiln/qa/tests`.
- Path is matched with trailing `/` to avoid matching `apps` when looking for `app/`.
- Citation surface uses `plugin-*/` (all plugins, not just kiln) to catch cross-plugin references.

**(c) mtime >30 days**:
```bash
find "$dir" -maxdepth 0 -type d -mtime +30 | head -1   # non-empty = older than 30 d
```
`mtime` of the directory itself (not its contents) — meaning the last time a file was added, removed, or renamed inside it. A folder actively receiving files will never fire. Directories containing only `.gitkeep` still fire because git tracking does not touch mtime.

**Threshold override**: `orphaned-top-level-folder.min_age_days` in `.kiln/structural-hygiene.config`. Default `30`.

**Rejected alternatives**:
- **git-log-based "last referenced" check.** Rejected: expensive and redundant — grep surface already catches live references; mtime catches quiescent orphans.
- **Content-hash-based "has anything changed since creation"**. Rejected: too clever; mtime is the honest signal.

---

### Decision 4 — Bundled-accept UX for merged-PRD block

**Locked**: **Strict bundle-accept for v1.** The preview renders one section titled `## Bundled: merged-prd-not-archived (N items)` containing a single prose block + one unified-diff body covering every proposed edit. The maintainer either applies the whole diff or none of it.

**Exact prose header** (copy-pasteable, codified in contracts §4):

> **Accept or reject as a unit.** Per-item cherry-pick is out of scope for v1 — if the `merged-prd-not-archived` invariant holds for one item, it holds for all. To exclude a specific item, move it to `status: in-progress` manually and re-run the audit.

**Rejected alternatives**:
- **Per-item toggle via `--except <file>`**. Rejected for v1: doubles the preview-rendering logic surface and adds an arg that's rarely needed. Usage data can promote to v2.
- **Separate section per item**. Rejected: reproduces the PRD's explicit anti-goal — 18 separate sections is the noise shape we want to eliminate.

**v2 escape hatch** (documented, not implemented): a `kiln-hygiene --apply` subcommand may introduce per-item opt-out via an interactive prompt. Not on this PR.

---

### Decision 5 — kiln-doctor subcheck: 3h: Structural hygiene drift

**Locked**: Insert a new section in `plugin-kiln/skills/kiln-doctor/SKILL.md` after `### 3g: CLAUDE.md Drift Check (cheap signals only)` and before `### 3f: Stale prd-created Issue Detection — FR-010` (current file ordering: 3a → 3b → 3c → 3d → 3g → 3f → 3e).

**Exact heading text** (no variation):
```
### 3h: Structural hygiene drift (cheap signals only)
```

**Exact intro paragraph** (matches 3g's shape verbatim where possible):
```
Run the `cost: cheap` subset of the `plugin-kiln/rubrics/structural-hygiene.md` rubric against the repo's structural state and report a single row in the diagnosis table. Performance budget: **<2s** (cheap-greppy only, no `gh`, no LLM). For the full rubric — including the editorial `merged-prd-not-archived` rule that needs `gh` — invoke `/kiln:kiln-hygiene` directly.
```

**Cheap rules run by 3h**: `orphaned-top-level-folder` and `unreferenced-kiln-artifact`. NOT `merged-prd-not-archived` (that rule's cost is `editorial` because it needs `gh`).

**Diagnosis-table row shape** (appended to Step 3e's table):
```
| Structural hygiene drift | OK    | No cheap signals triggered |
| Structural hygiene drift | DRIFT | N cheap signals; run /kiln:kiln-hygiene |
| Structural hygiene drift | N/A   | rubric or .kiln/ not found — skipped |
```

**No collision risk**: current doctor file uses `3a, 3b, 3c, 3d, 3g, 3f` (3e is the Report). 3h is the next unused letter. Confirmed by `grep -nE '^### 3[a-z]:' plugin-kiln/skills/kiln-doctor/SKILL.md`.

**Override hook**: same resolution logic as 3g — 3h resolves `plugin-kiln/rubrics/structural-hygiene.md` via the same two-step `find` + fallback that 3g uses for the CLAUDE.md rubric. If unresolved, the row is `N/A` and doctor continues (parity with 3g).

---

## Phased Implementation

All five phases are sequential, single implementer, per-phase commit.

### Phase A — Rubric artifact + 3 MVP rules

Ship `plugin-kiln/rubrics/structural-hygiene.md` with the schema locked in contracts §1 and these three rule entries (each with the full YAML block + prose):

1. `merged-prd-not-archived` (signal_type: editorial, cost: editorial, action: archive-candidate).
2. `orphaned-top-level-folder` (signal_type: freshness, cost: cheap, action: removal-candidate).
3. `unreferenced-kiln-artifact` (signal_type: freshness, cost: cheap, action: removal-candidate).

Configurable thresholds (per-rule, overridable):
- `orphaned-top-level-folder.min_age_days` — default 30.
- `unreferenced-kiln-artifact.min_age_days` — default 60.
- `merged-prd-not-archived.gh_limit` — default 500.

### Phase B — Audit skill (`/kiln:kiln-hygiene`)

Ship `plugin-kiln/skills/kiln-hygiene/SKILL.md`. Mirror the 5-step shape of `/kiln:kiln-claude-audit`:

1. Parse args (only `--config <path>` supported).
2. Resolve rubric path (same fallback chain as claude-audit Step 1).
3. Load rubric + merge overrides.
4. Run rule predicates against the repo state; collect signals.
5. Render preview file to `.kiln/logs/structural-hygiene-<ts>.md`.

### Phase C — Doctor subcheck 3h

Edit `plugin-kiln/skills/kiln-doctor/SKILL.md`: insert the 3h block (locked text in Decision 5). Append the DRIFT/OK/N-A row to the Step 3e diagnosis table. Zero changes to 3a..3g.

### Phase D — merged-PRD rule concrete implementation

Fill in the `merged-prd-not-archived` predicate inside the skill body. This is the gh bulk-lookup + in-memory match + bundled preview + inconclusive-on-fail path locked in Decision 2 + FR-007.

### Phase E — SMOKE.md + backwards-compat guard + discoverability

- Write `specs/kiln-structural-hygiene/SMOKE.md` reproducing SC-008 (`git checkout 574f220^` + invoke + assert 18 hits).
- Add a fixture test under the skill's `tests/` that captures stdout of `/kiln:kiln-cleanup --dry-run` on a no-signal repo and diffs against a committed baseline (SC-007).
- Bump rubric discoverability: add one reference in CLAUDE.md's Available Commands block (`/kiln:kiln-hygiene — Full hygiene audit; see plugin-kiln/rubrics/structural-hygiene.md`).

---

## Progress Tracking

- [ ] Phase A — Rubric + 3 rules
- [ ] Phase B — Audit skill skeleton + cheap rules
- [ ] Phase C — Doctor 3h subcheck
- [ ] Phase D — merged-PRD rule implementation
- [ ] Phase E — SMOKE + backwards-compat + discoverability

Commit after each phase (Constitution VIII).
