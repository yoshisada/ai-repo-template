# Blockers: Structured Roadmap Planning Layer

**Branch**: `build/structured-roadmap-20260424`
**Audit date**: 2026-04-24
**Auditor**: audit-compliance

---

## Blocker: T063 — Bash coverage gate (80%) cannot be measured

**Status**: OPEN
**Reason**: `bashcov` (and the alternative `kcov`) are not installed in the implementation environment. Constitution Article II requires ≥80% line + branch coverage on new/modified code. The 10 new Bash helpers under `plugin-kiln/scripts/roadmap/` ship with 17 test fixtures that structurally exercise every code path, but the coverage metric itself cannot be produced without the tooling.
**Impact**: Cannot formally certify that the 80% gate is met before PR merge. All code paths are exercised by the test fixtures, but this is a structural assertion rather than a measured one.
**Resolution path**:
1. Install `bashcov` (requires Ruby): `gem install bashcov`
2. OR install `kcov` (binary: `brew install kcov` on macOS, `apt install kcov` on Ubuntu)
3. Run: `bashcov bash <helper>.sh <args>` against each helper with its fixture inputs
4. Measure aggregate line + branch coverage; require ≥80% before final merge
5. Mark T063 `[X]` and update this entry to RESOLVED with the measured coverage %
**Date**: 2026-04-24

---

## Blocker: FR-004 — `.shelf-config`-reading shelf helpers (RESOLVED)

**Status**: RESOLVED — commit `90f3e78` on `main` (PR #146)
**Original description**: Issue `2026-04-23-write-issue-note-ignores-shelf-config` — `shelf:shelf-write-issue-note` was guessing the Obsidian path instead of reading `.shelf-config`, which meant any shelf-dependent write could produce incorrect paths.
**Resolution**: PR #146 (`fix(kiln,shelf): pipeline input completeness — Step 4b scans feedback + write-issue-note reads .shelf-config`) landed on `main` and is present in this branch. Evidence:
- `plugin-shelf/scripts/parse-shelf-config.sh` reads `.shelf-config` directly and emits a structured block (verified: `## SHELF_CONFIG_PARSED` format).
- `plugin-shelf/workflows/shelf-write-issue-note.json` step 1 is `bash "${WORKFLOW_PLUGIN_DIR}/scripts/parse-shelf-config.sh"` (no vault discovery).
- `plugin-shelf/workflows/shelf-write-roadmap-note.json` (new, this feature) mirrors the fixed pattern exactly.
- `obsidian-write` agent in both workflows explicitly `MUST NOT call list_files`.
- Issue `.kiln/issues/2026-04-23-write-issue-note-ignores-shelf-config.md` carries `status: prd-created` (promoted, not `open`).
- The `shelf-mirror-paths` test fixture directly validates the `path_source` literal-string contract (§3.2).
**Date resolved**: 2026-04-23 (PR #146)
**Verified by**: audit-compliance, 2026-04-24

---

## Compliance summary (post-reconciliation)

| Category | Count |
|----------|-------|
| PRD FRs covered by spec FRs | 31/31 (100%) |
| Spec FRs implemented + FR-commented | 43/43 (100%) |
| Spec FRs with direct test assertions | 41/43 (95%) — FR-013 fixed; FR-031 MCP-level only |
| Open blockers | 1 (T063 coverage gate) |
| Resolved blockers | 1 (FR-004 shelf-config) |
| Schema invariants (AI-native sizing, confirm-never-silent) | PASS |
| Test quality | Real assertions — no stubs |
| Smoke test | Structural verification only (CLI harness `/kiln:kiln-test plugin-kiln` required for live execution) |
