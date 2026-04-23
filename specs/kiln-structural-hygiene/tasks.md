# Tasks: Kiln Structural Hygiene

**Spec**: [spec.md](./spec.md) | **Plan**: [plan.md](./plan.md) | **Contracts**: [contracts/interfaces.md](./contracts/interfaces.md)
**Branch**: `build/kiln-structural-hygiene-20260423`

**Ownership**: single implementer. No parallel agents. Sequential phase commits.
**Total tasks**: 17 (≤18 per plan target).

---

## Phase A — Rubric artifact + 3 MVP rules

- [X] **A1**: Create `plugin-kiln/rubrics/structural-hygiene.md` with the preamble block from contracts/interfaces.md §1 (Version 1, Apr 2026; Consumed by `/kiln:kiln-hygiene` full + `/kiln:kiln-doctor` 3h cheap; Overridable from `.kiln/structural-hygiene.config`). Include the "Configurable thresholds" section listing `orphaned-top-level-folder.min_age_days = 30`, `unreferenced-kiln-artifact.min_age_days = 60`, `merged-prd-not-archived.gh_limit = 500`. References FR-002.

- [X] **A2**: Add rule entry `### merged-prd-not-archived` with the YAML block (`signal_type: editorial`, `cost: editorial`, `action: archive-candidate`, `cached: false`) + prose block describing: trigger conditions (a/b/c from FR-005), the bulk-lookup strategy reference ("see `contracts/interfaces.md` §5"), known false-positive shapes (squash-merged-then-deleted branch; feature-slug collision). References FR-005, FR-007, FR-008.

- [X] **A3**: Add rule entries `### orphaned-top-level-folder` and `### unreferenced-kiln-artifact` with full YAML + prose per contracts/interfaces.md §1. Orphaned-folder includes the three predicates from plan Decision 3 inlined as pseudocode in the prose. Unreferenced-artifact matches files under `.kiln/logs/`, `.kiln/qa/`, `.kiln/state/` that are (i) not actively produced by any running workflow (no `.wheel/state_*.json` references the file), and (ii) older than `min_age_days` (default 60). References FR-001, FR-002.

- [X] **A4**: Verify discoverability (NFR-004): `grep -rn 'plugin-kiln/rubrics/structural-hygiene.md' .` returns ≥1 hit outside the rubric itself. Minimum one reference added as part of Phase B (skill body) and one in Phase E (CLAUDE.md). This task is the verification gate — run grep and confirm ≥2 hits by end of Phase E. Verified 2026-04-23: 28 hits outside `plugin-kiln/rubrics/structural-hygiene.md` and `plugin-kiln/skills/kiln-hygiene/SKILL.md` (including CLAUDE.md Available Commands + doctor 3h). PASS.

---

## Phase B — Audit skill `/kiln:kiln-hygiene`

- [X] **B1**: Create directory `plugin-kiln/skills/kiln-hygiene/` with empty `tests/fixtures/` tree (`fixture-no-drift/`, `fixture-all-rules-fire/`, `fixture-gh-unavailable/`).

- [X] **B2**: Write `plugin-kiln/skills/kiln-hygiene/SKILL.md` Step 1–3: parse `--config <path>` arg; resolve `RUBRIC_PATH` using the same 4-step fallback as `/kiln:kiln-claude-audit` Step 1 (CLAUDE_PLUGIN_ROOT → source repo → ~/.claude cache → npm root -g); resolve `OVERRIDE_PATH`; set `TIMESTAMP=$(date +%Y-%m-%d-%H%M%S)`; set `OUTPUT_PATH=.kiln/logs/structural-hygiene-${TIMESTAMP}.md`; ensure `.kiln/logs/` exists. References FR-001, FR-003.

- [X] **B3**: Write SKILL.md Step 4 — load rubric, parse `### <rule_id>` entries with their YAML blocks, merge overrides from `OVERRIDE_PATH`. Use the same malformed-override fallback as claude-audit Step 2 (`structural-hygiene.config: unparseable at line N; falling back to plugin defaults` — exit 0, warn only). References FR-002, spec Edge Cases.

- [X] **B4**: Write SKILL.md Step 5a — `orphaned-top-level-folder` cheap rule predicate. Implementation: enumerate top-level dirs (exclude `.git`, `node_modules`, manifest entries); for each, check predicates (a) (b) (c) from plan Decision 3. Record a signal per fired dir. References FR-001.

- [X] **B5**: Write SKILL.md Step 5b — `unreferenced-kiln-artifact` cheap rule predicate. Walk `.kiln/logs/`, `.kiln/qa/` artifact dirs, `.kiln/state/` (if present); for each file, check mtime > `min_age_days` (default 60) AND no match in any `.wheel/state_*.json`. Record signals. References FR-001.

- [X] **B6**: Write SKILL.md Step 6 — render preview at `OUTPUT_PATH` using the shape from contracts §2: header with timestamp, Signal Summary table (sorted per NFR-002), Proposed-Actions body (per-rule sections, with the bundled merged-PRD block reserved for Phase D), Notes. Implement the `**Result**: no drift` marker (empty body → that exact phrase). Print the one-line summary to stdout. Exit 0 regardless of signal count. Commit Phase B (`feat(kiln-hygiene): skill scaffold + cheap rules`). References FR-003, NFR-002, SC-005.

---

## Phase C — kiln-doctor subcheck 3h

- [X] **C1**: Edit `plugin-kiln/skills/kiln-doctor/SKILL.md`: insert the `### 3h: Structural hygiene drift (cheap signals only)` section with the exact intro paragraph from plan Decision 5. Place it AFTER `### 3g` and BEFORE `### 3f` (preserving the existing 3a → 3b → 3c → 3d → 3g → 3f → 3e order the file currently uses). Subcheck body resolves the rubric via the same two-step `find` + source-repo fallback used in 3g, runs ONLY the `cost: cheap` predicates (= `orphaned-top-level-folder` + `unreferenced-kiln-artifact`; not `merged-prd-not-archived`), and increments a `HYGIENE_DRIFT_COUNT` counter. References FR-004, Decision 5.

- [X] **C2**: Edit the Step 3e diagnosis-table example in the same file to include one new row per the three shapes in plan Decision 5 (`OK` / `DRIFT` / `N/A`). Ensure no 3a..3g rows are renumbered or altered. Add the Subchecks ordering reference to the Rules section at bottom if the existing section enumerates subchecks. Commit Phase C (`feat(kiln-doctor): add 3h structural hygiene subcheck`). References NFR-003, SC-007.

---

## Phase D — merged-PRD rule concrete implementation

- [X] **D1**: Extend SKILL.md (Phase B) with Step 5c — `merged-prd-not-archived` editorial rule predicate. Implementation: (i) run the gh bulk-lookup from plan Decision 2 into `$TMPDIR/gh-merged-prs.tsv`; (ii) if `gh` unavailable OR `gh auth status` non-zero, set `GH_AVAILABLE=false` and skip to step (vi); (iii) walk `.kiln/issues/*.md` + `.kiln/feedback/*.md`; (iv) for each with `status: prd-created`, parse the `prd:` field; (v) derive feature-slug from the PRD path per contracts §5 and look up against the in-memory TSV map; (vi) emit signals: `archive-candidate` if PR found, `needs-review` if `prd:` malformed/missing/unmerged (FR-008), `inconclusive` if `GH_AVAILABLE=false` (FR-006). References FR-005, FR-006, FR-008.

- [X] **D2**: Extend Step 6 (preview rendering) to emit the bundled merged-PRD block per FR-007. Block heading: `## Bundled: merged-prd-not-archived (N items)`. Prose header: exact text from plan Decision 4. Body: one git-diff-shaped hunk per item, concatenated, sorted by filename. If zero `archive-candidate` signals fired, the bundled section is omitted entirely (not rendered with zero rows). References FR-007, Decision 4.

- [X] **D3**: Add the gh-truncation warning per spec Edge Cases: when the TSV line count equals 500, append a Notes-section line `merged-prd-not-archived: gh pr list returned 500 entries — possible truncation; raise merged-prd-not-archived.gh_limit in .kiln/structural-hygiene.config if needed`. References spec Edge Cases.

- [X] **D4**: Add fixture under `plugin-kiln/skills/kiln-hygiene/tests/fixtures/fixture-all-rules-fire/` with 3 items whose `prd:` points at merged PRDs + 1 control (unmerged) + 1 malformed. Harness script asserts preview contains exactly 3 items in bundled block, control absent, malformed appears as `needs-review`. Also add `fixture-gh-unavailable/` asserting the `inconclusive` path. Commit Phase D (`feat(kiln-hygiene): merged-prd-not-archived rule + bundled preview`). References SC-002, SC-003.

---

## Phase E — SMOKE.md + backwards-compat + discoverability

- [X] **E1**: Write `specs/kiln-structural-hygiene/SMOKE.md` codifying SC-008: `git checkout 574f220^` in a scratch worktree, invoke `/kiln:kiln-hygiene`, assert all 18 filenames from `.kiln/issues/2026-04-23-stale-prd-created-issues-not-archived.md` appear in the bundled archive block. Include exact `grep -c`/`diff`-style assertions for CI-style reproducibility. References SC-008.

- [X] **E2**: Backwards-compat + discoverability combined commit. (a) Add one fixture under `plugin-kiln/skills/kiln-hygiene/tests/fixtures/fixture-no-drift/` that runs `/kiln:kiln-cleanup --dry-run`, `/kiln:kiln-cleanup`, `/kiln:kiln-doctor --fix --dry-run`, and `/kiln:kiln-doctor --cleanup` and asserts zero new-row regressions beyond the 3h row (SC-007). (b) Add the `/kiln:kiln-hygiene` entry + rubric path reference to CLAUDE.md's `## Available Commands` block (`/kiln:kiln-hygiene — Full hygiene audit; see plugin-kiln/rubrics/structural-hygiene.md`). (c) Verify A4 gate: `grep -rn 'plugin-kiln/rubrics/structural-hygiene.md' .` returns ≥2 hits (doctor 3h + CLAUDE.md + skill body = ≥3 in practice). Mark A4 `[X]` in this commit. Commit Phase E (`feat(kiln-hygiene): SMOKE + backwards-compat + rubric discoverability`). References SC-007, NFR-003, NFR-004.

---

## Phase boundaries

- Commit at the end of every phase. Do not batch.
- Each task marked `[X]` **immediately** on completion (Constitution VIII).
- Friction notes written to `specs/kiln-structural-hygiene/agent-notes/implementer.md` before marking Task #2 completed.
