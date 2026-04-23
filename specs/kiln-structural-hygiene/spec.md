# Feature Specification: Kiln Structural Hygiene

**Feature Branch**: `build/kiln-structural-hygiene-20260423`
**Created**: 2026-04-23
**Status**: Draft
**Input**: PRD at `docs/features/2026-04-23-kiln-structural-hygiene/PRD.md`

## User Scenarios & Testing

### User Story 1 — Full-repo structural audit on demand (Priority: P1)

A kiln maintainer runs a dedicated hygiene-audit skill at the end of a cycle. Instead of the narrow QA-only scope of today's `/kiln:kiln-cleanup`, the audit walks the repo against a versioned rubric and proposes a single review preview covering (a) lifecycle-invariant violations (the merged-PRD-not-archived class), (b) orphaned top-level folders, and (c) unreferenced artifacts in `.kiln/`. Nothing is applied automatically — the maintainer reads the preview and either applies manually or re-runs with an explicit `--apply` follow-up (v2).

**Why this priority**: Structural decay is invisible until someone goes looking. The 18 leaked `prd-created` items this month are the visible instance of a larger class. This is the load-bearing half of the PRD and the only way FR-001, FR-003, FR-005, FR-007, and FR-008 cohere into one reviewable artifact.

**Independent Test**: Run the new hygiene skill against a fixture with (a) 2–3 `status: prd-created` items whose `prd:` points at merged PRDs, (b) 1 orphaned top-level directory older than 30 days, (c) 1 stale artifact file in `.kiln/logs/`, plus control items that must NOT fire. Preview file at `.kiln/logs/structural-hygiene-<ts>.md` exists, contains a single bundled merged-PRD block covering exactly the 2–3 items, plus per-rule sections for the orphan and the artifact. Controls are absent.

**Acceptance Scenarios**:

1. **Given** a repo with at least one `merged-prd-not-archived` signal, one orphaned-folder signal, and one unreferenced-artifact signal, **When** the maintainer invokes the hygiene skill (Decision 1 locks the exact name in plan.md), **Then** the skill writes `.kiln/logs/structural-hygiene-<YYYY-MM-DD-HHMMSS>.md` with one bundled merged-PRD block, one per-rule section per other fired rule, and exits 0. (FR-001, FR-003, FR-007)
2. **Given** a repo with zero hygiene signals, **When** the maintainer invokes the skill, **Then** the preview file renders a `**Result**: no drift` header, the Signal Summary table has zero data rows (or only `keep`/`inconclusive`), and the skill exits 0. (NFR-002, FR-003)
3. **Given** the skill is invoked a second time against an unchanged repo, **When** both preview files are compared byte-by-byte excluding the single `# … — <timestamp>` header line, **Then** the bodies are identical. (NFR-002)

---

### User Story 2 — Cheap-signal subcheck in /kiln:kiln-doctor (Priority: P1)

A maintainer running `/kiln:kiln-doctor` at session start wants a cheap tripwire that says "structural drift detected — run the full hygiene skill" without paying the editorial/`gh` cost during routine diagnosis. Doctor's existing 3g CLAUDE.md-drift row gains a sibling 3h row that runs the `cost: cheap` subset of the hygiene rubric in under 2 s.

**Why this priority**: Without a cheap signal surfaced in the normal session-start flow, the structural audit is opt-in and forgotten. This makes hygiene discoverable by the same mechanism that surfaced CLAUDE.md drift in PR #141.

**Independent Test**: Introduce one cheap-signal firing file (an orphaned folder + an unreferenced artifact are cheap; merged-PRD is NOT cheap — it requires `gh`). Run `/kiln:kiln-doctor` with no flags and verify: (a) diagnosis table contains a row `| Structural hygiene drift | DRIFT | N cheap signals; run /kiln:kiln-hygiene |`, (b) wall time for the subcheck alone is <2 s measured via `/usr/bin/time -p` wrapping a targeted harness that sources only the 3h block.

**Acceptance Scenarios**:

1. **Given** at least one cheap hygiene signal in the repo, **When** the maintainer runs `/kiln:kiln-doctor` with no flags, **Then** the diagnosis table has exactly one `Structural hygiene drift` row with status `DRIFT` and a details column citing the count + the hygiene skill name. (FR-004)
2. **Given** no cheap hygiene signals, **When** the maintainer runs `/kiln:kiln-doctor`, **Then** the row renders as `| Structural hygiene drift | OK | No cheap signals triggered |`. (FR-004)
3. **Given** the rubric path cannot be resolved OR the repo is missing `.kiln/`, **When** the subcheck runs, **Then** the row renders as `| Structural hygiene drift | N/A | rubric or .kiln/ not found — skipped |` and doctor continues without error. (FR-004, mirrors 3g N/A pattern)
4. **Given** a real-repo fixture, **When** the 3h subcheck runs, **Then** wall time for the 3h section is <2 s. (FR-004, SC-004)

---

### User Story 3 — Merged-PRD lifecycle invariant catches leaked items (Priority: P1)

A maintainer has just merged a run of pipelines whose Step 4b silently dropped backlog items on the floor. The next hygiene audit must catch every `.kiln/issues/*.md` or `.kiln/feedback/*.md` with `status: prd-created` and a `prd:` field pointing at a PRD whose feature branch is merged to `main` on GitHub, and propose archival as a single bundled block.

**Why this priority**: The external safety net the PRD commits to (Part B). Without this the 18 items this month re-accumulate next cycle.

**Independent Test**: `git checkout 574f220^` (the commit immediately before this month's housekeeping sweep) and run the hygiene skill. Preview MUST flag all 18 listed items in `.kiln/issues/2026-04-23-stale-prd-created-issues-not-archived.md` for archival. Codified as `SMOKE.md`.

**Acceptance Scenarios**:

1. **Given** a fixture with three `status: prd-created` items whose `prd:` fields point at PRDs whose feature branches appear in `gh pr list --state merged`, plus one control item whose `prd:` points at an unmerged branch, **When** the skill runs, **Then** the bundled merged-PRD block proposes exactly three archive moves and leaves the control alone. (FR-005, FR-008)
2. **Given** the maintainer is offline or `gh auth status` is non-zero, **When** the skill runs, **Then** the Signal Summary marks every `merged-prd-not-archived` candidate as `inconclusive`, a one-line warning appears in the Notes section, and the skill exits 0. (FR-006)
3. **Given** a `status: prd-created` item whose `prd:` field is empty, malformed, or points at a non-existent PRD path, **When** the skill runs, **Then** that item is reported as `needs-review` (visible in Signal Summary, not in the bundled archive block). (FR-008)
4. **Given** five merged-PRD archive candidates, **When** the preview renders, **Then** there is exactly ONE bundled block listing all five proposed frontmatter edits + move-to-completed instructions — not five separate sections. The preview's prose instructs the maintainer that this is strict bundle-accept for v1 (Decision 4). (FR-007)

---

### User Story 4 — Rubric artifact exists, is discoverable, and is overridable (Priority: P2)

A maintainer wants "what the hygiene audit checks and why" written down in one file, versioned with the plugin, and evolvable without editing skill bodies. A consumer project can override a rule's action or threshold via `.kiln/structural-hygiene.config` without forking the plugin.

**Why this priority**: Rubric-as-artifact is the same pattern that landed CLAUDE.md-usefulness rubric (PR #141). Without it, hygiene rules are implicit in the skill body and drift silently. Lower priority than US-1/US-3 because the rubric is dead weight without the skill that consumes it.

**Independent Test**: File exists at `plugin-kiln/rubrics/structural-hygiene.md`. `grep -rn 'structural-hygiene'` outside that file and outside the new hygiene skill body returns ≥1 hit (rubric is referenced from doctor 3h + CLAUDE.md's Available Commands list per NFR-004). Rubric parses into ≥3 `### <rule_id>` entries matching the schema in `contracts/interfaces.md` §1.

**Acceptance Scenarios**:

1. **Given** the rubric file exists and contains at minimum `merged-prd-not-archived`, `orphaned-top-level-folder`, and `unreferenced-kiln-artifact` entries, **When** the hygiene skill runs, **Then** the skill parses the rubric at invocation and does NOT hardcode rule IDs in its body. (FR-002)
2. **Given** `.kiln/structural-hygiene.config` contains `orphaned-top-level-folder.enabled = false`, **When** the skill runs in that repo, **Then** the Signal Summary contains zero rows for `orphaned-top-level-folder` and the Notes section records `Override rules applied: orphaned-top-level-folder`. (FR-002, mirrors claude-md override precedent)
3. **Given** `grep -rn 'plugin-kiln/rubrics/structural-hygiene.md'` is executed across the repo, **When** results are counted, **Then** ≥1 reference exists outside the rubric itself and outside `plugin-kiln/skills/kiln-hygiene/SKILL.md`. (NFR-004)

---

### User Story 5 — Backwards compatibility with existing cleanup + doctor (Priority: P2)

A maintainer whose muscle memory is `/kiln:kiln-cleanup --dry-run` and `/kiln:kiln-doctor --fix` must see zero regression. The new hygiene surface is a sibling skill — it does not alter the argument surface, exit codes, or side effects of the existing skills.

**Why this priority**: The PRD (NFR-003) explicitly locks non-regression of cleanup and doctor. Without an explicit acceptance criterion, a later refactor could accidentally fold hygiene into cleanup's `--cleanup` mode and break the contract.

**Independent Test**: On a fixture that contains zero hygiene signals, run (a) `/kiln:kiln-cleanup --dry-run`, (b) `/kiln:kiln-cleanup`, (c) `/kiln:kiln-doctor --fix --dry-run`, (d) `/kiln:kiln-doctor --cleanup`. All four produce the same side effects and exit codes they did on main before this PR. Doctor's diagnosis table gains one new `Structural hygiene drift | OK | …` row; no other row shape changes.

**Acceptance Scenarios**:

1. **Given** a fixture with no hygiene signals, **When** `/kiln:kiln-cleanup --dry-run` runs, **Then** its stdout + exit code match the pre-PR behavior on a fixture where the existing `Step 2.5 Scan Backlog Issues for Archival` would produce identical output. (NFR-003, SC-007)
2. **Given** the same fixture, **When** `/kiln:kiln-doctor` runs with any existing flag combination (`--diagnose`, `--fix`, `--fix --dry-run`, `--cleanup`, `--cleanup --dry-run`), **Then** all pre-existing diagnosis rows (3a..3g) render identically; only a new 3h row is added. (NFR-003, FR-004)

---

## Requirements

### Functional Requirements

**Structural audit skill and rubric (strategic)**:

- **FR-001 (from PRD FR-001)**: A dedicated hygiene audit skill (shape locked in plan.md Decision 1) MUST perform a repo-wide structural audit covering at minimum three rule classes: (a) lifecycle invariants (merged-PRD archival), (b) orphaned top-level folders, (c) unreferenced artifacts under `.kiln/`. Additional rules may be added later without re-writing the skill body.
- **FR-002 (from PRD FR-002)**: The audit MUST be driven by a plugin-embedded, versioned rubric at `plugin-kiln/rubrics/structural-hygiene.md` with the schema locked in `contracts/interfaces.md` §1. Each rule entry specifies `rule_id`, `signal_type`, `cost`, `match_rule`, `action`, `rationale`, `cached`. Optional consumer override at `.kiln/structural-hygiene.config` — per-rule merge, repo wins.
- **FR-003 (from PRD FR-003)**: The audit output MUST be a review preview written to `.kiln/logs/structural-hygiene-<YYYY-MM-DD-HHMMSS>.md`. The skill MUST NOT apply destructive edits. Grep of the hygiene skill body for `sed -i`, `mv .kiln/issues/`, `mv .kiln/feedback/`, or `git mv` against issue/feedback paths MUST return zero hits (SC-005).
- **FR-004 (from PRD FR-004)**: `/kiln:kiln-doctor` MUST gain a new subcheck named `3h: Structural hygiene drift (cheap signals only)` (Decision 5) that runs ONLY the `cost: cheap` subset of the hygiene rubric and appends exactly one row to the Step 3e diagnosis table. Wall time for the 3h block MUST be <2 s on a real-repo fixture measured via `/usr/bin/time -p`.

**Merged-PRD archival invariant (tactical)**:

- **FR-005 (from PRD FR-005)**: The rubric MUST include a rule `merged-prd-not-archived` that fires when ALL of: (a) a file under `.kiln/issues/` or `.kiln/feedback/` has frontmatter `status: prd-created`, (b) its `prd:` frontmatter field points at an existing PRD file under `docs/features/*/PRD.md` or `products/*/PRD.md`, (c) a GitHub PR whose `headRefName` begins with or equals the PRD's feature-slug is in state `MERGED`. The rule's matched-branch lookup MUST use a single `gh pr list --state merged --limit 500 --json number,headRefName,title,mergedAt` call per audit invocation (Decision 2) — NOT one `gh` call per item. The proposed action is `archive-candidate`: flip `status: completed`, add `completed_date: <gh mergedAt YYYY-MM-DD>`, add `pr: #<gh number>`, move the file to `completed/`.
- **FR-006 (from PRD FR-006)**: The `merged-prd-not-archived` rule MUST gracefully degrade when `gh` is unavailable or unauthenticated. Degradation: emit a single Notes-section line `merged-prd-not-archived: gh unavailable — marked inconclusive`, mark every candidate row as `inconclusive` in the Signal Summary, exit 0. Mirrors `/kiln:kiln-next` FR-014.
- **FR-007 (from PRD FR-007)**: When one or more `merged-prd-not-archived` signals fire, the preview MUST render them as a SINGLE bundled block (one section, one diff body covering all N proposed edits) — not per-item. The preview MUST state in prose above the block: `Accept or reject as a unit. Per-item cherry-pick is out of scope for v1 — if the invariant holds for one item, it holds for all.` (Decision 4, strict bundle-accept.) Downstream v2 MAY relax this based on usage data.
- **FR-008 (from PRD FR-008)**: The `merged-prd-not-archived` rule MUST NOT fire on items where the `prd:` field is empty/missing, points at a non-existent file, or points at a PRD whose feature branch does NOT appear in the gh bulk-lookup result set. Such items are emitted as `needs-review` rows in the Signal Summary — visible to the maintainer but NOT included in the bundled archive block.

### Non-Functional Requirements

- **NFR-001 (from PRD NFR-001)**: No new runtime dependencies. The skill uses bash 5.x, `gh`, `jq`, and standard POSIX utilities already in the tech stack.
- **NFR-002 (from PRD NFR-002)**: Preview output MUST be idempotent — two consecutive runs against an unchanged repo produce byte-identical `Signal Summary` rows and preview body. Permitted diff: the single `# … — <timestamp>` header line and the filename timestamp. Enforced by sorting Signal Summary rows by `rule_id ASC, path ASC`, emitting archive-block entries in filename-sort order, and never embedding wall-clock time outside the header.
- **NFR-003 (from PRD NFR-003)**: Backwards compatibility — existing `/kiln:kiln-cleanup` (with `--dry-run`, default-mode) and `/kiln:kiln-doctor` (with `--diagnose`, `--fix`, `--cleanup`, `--dry-run` and any combination) MUST retain their pre-PR behavior. The only permitted change to doctor is the new 3h row appended to the diagnosis table in Step 3e.
- **NFR-004 (from PRD NFR-004)**: Rubric discoverability — `grep -rn 'plugin-kiln/rubrics/structural-hygiene.md'` from the repo root MUST return ≥1 hit outside the rubric itself AND outside the hygiene skill body. Enforced by referencing the rubric path from the doctor 3h section AND from CLAUDE.md's Available Commands block.

## Success Criteria

- **SC-001 (from PRD SC-001) Rubric exists and is versioned.** `plugin-kiln/rubrics/structural-hygiene.md` exists at HEAD, contains at minimum the three rules from FR-001 (`merged-prd-not-archived`, `orphaned-top-level-folder`, `unreferenced-kiln-artifact`), and `grep -rn` finds ≥1 reference outside the rubric + the hygiene skill body.
- **SC-002 (from PRD SC-002) Merged-PRD archival catches a real instance.** A fixture with 3 `status: prd-created` items pointing at merged PRDs + 1 control pointing at an unmerged PRD produces a preview whose bundled archive block contains exactly the 3 items. The control appears only in the Signal Summary with `needs-review`.
- **SC-003 (from PRD SC-003) gh-unavailable graceful degradation.** Running the skill with `PATH` stripped of `gh`, or with `GH_TOKEN=` unset on a non-authed host, produces a preview whose Notes section includes `merged-prd-not-archived: gh unavailable — marked inconclusive`, every `merged-prd-not-archived` row is `inconclusive`, exit code is 0.
- **SC-004 (from PRD SC-004) Doctor subcheck under budget.** On a real-repo fixture, the wall time of the 3h block (isolated in a harness script under `plugin-kiln/skills/kiln-doctor/tests/` — matches existing doctor test layout) is <2 s measured by `/usr/bin/time -p`.
- **SC-005 (from PRD SC-005) Propose-don't-apply.** `grep -nE 'sed -i|mv .kiln/(issues|feedback)/|git mv .kiln/(issues|feedback)/' plugin-kiln/skills/kiln-hygiene/SKILL.md` returns zero matches.
- **SC-006 (from PRD SC-006) Idempotence.** Two consecutive invocations of the hygiene skill on an unchanged repo produce preview files whose bodies are byte-identical excluding the header timestamp line. Verified by `diff <(tail -n +2 preview1) <(tail -n +2 preview2)` returning empty.
- **SC-007 (from PRD SC-007) Backwards compat.** A fixture with zero hygiene signals produces byte-identical stdout + exit code from (a) `/kiln:kiln-cleanup`, (b) `/kiln:kiln-cleanup --dry-run`, (c) `/kiln:kiln-doctor --fix` (excluding the 3h row which is permitted to exist), (d) `/kiln:kiln-doctor --cleanup` — compared against the outputs captured on main immediately before merge.
- **SC-008 (from PRD SC-008) This month's leak would have been caught.** Running the new skill against `git checkout 574f220^` (the state immediately before this month's housekeeping sweep) flags every one of the 18 items listed in `.kiln/issues/2026-04-23-stale-prd-created-issues-not-archived.md` for archive. Captured as `specs/kiln-structural-hygiene/SMOKE.md`.

## Edge Cases

- **gh bulk-lookup returns exactly 500 entries** (limit hit): the skill MUST emit a Notes-section warning `merged-prd-not-archived: gh pr list returned 500 entries — possible truncation; consider --limit 1000 via plan Decision 2 knob` and continue. v1 does not paginate; v2 MAY.
- **Feature-slug collision**: two PRDs share a feature-slug (both `archive-stuff`). The rule MUST match the `prd:` path first, then verify the resolved PR's `headRefName` starts with or equals the slug — if multiple PRs match, pick the most recently merged (by `mergedAt`). Document in rubric prose.
- **`prd:` field points at an in-repo PRD whose branch was squash-merged and the branch subsequently deleted**: the `gh pr list --state merged` call still returns the PR (merged state is terminal). Rule fires normally.
- **Orphaned folder contains a `.gitkeep` only**: treat as orphan (stat `find <dir> -type f ! -name .gitkeep` — zero result + mtime >30 d = orphan candidate).
- **Config override references a rule_id not in the plugin rubric**: emit one Notes-section line `structural-hygiene.config: unknown rule_id '<id>' — ignoring` and skip just that line. Mirrors claude-md-audit precedent.

## Assumptions

- `gh` CLI is installed and authenticated in the maintainer's environment (same assumption as `/kiln:kiln-next` and `/kiln:kiln-analyze-issues`). Non-authed case is handled explicitly by FR-006.
- Feature-branch naming convention: `build/<feature-slug>-<YYYYMMDD>`. The merged-PRD predicate extracts the feature-slug by stripping the `build/` prefix and trailing `-YYYYMMDD`; the predicate matches against PR `headRefName`. Locked in `contracts/interfaces.md` §5.
- Scoped only to repo-local state under the repo root. The hygiene skill does NOT audit `~/.claude/plugins/cache/` or any path outside the working tree.
