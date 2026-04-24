# Auditor Friction Notes — prd-derived-from-frontmatter

**Agent**: auditor
**Task**: #3 — Audit + smoke + PR for prd-derived-from-frontmatter
**Date**: 2026-04-23
**Branch**: `build/prd-derived-from-frontmatter-20260424`

## Summary

Fresh-context audit confirms the implementer shipped all 11 FRs and 5 NFRs per the spec + contracts + plan. All 13 tasks are `[X]`. All 8 SCs have implementation + fixture coverage. No blockers.md needed. PR #146 diagnostic continuity (NFR-005) preserved — the exact `grep -E` from `specs/pipeline-input-completeness/SMOKE.md` line 195 still matches the new 8-field diagnostic line (un-anchored at end-of-line).

## Grep Gate 1 — Propose-don't-apply (migration tool)

**Requirement**: the backfill migration (Phase D) MUST NOT call Edit/Write/`perl -i`/`sed -i`/`git mv`/`git apply` against any `docs/features/*/PRD.md` or `products/*/features/*/PRD.md`. Zero hits allowed.

**Command**:

```bash
grep -n -E 'Edit|Write|perl -i|sed -i|git mv|git apply' plugin-kiln/skills/kiln-hygiene/SKILL.md
```

**Raw hits (7 lines 392–649)**:

- Line 392 — `Write OUTPUT_PATH using the exact shape from contract §2` — **in the DEFAULT hygiene audit body** (Step 6, preview rendering). Writes to `$OUTPUT_PATH` (`.kiln/logs/structural-hygiene-*.md`), NOT to any PRD. Not the backfill code path. ✓
- Line 431 — `Each hunk shape (copy the pattern exactly;` `git apply` `must accept the concatenated block)` — **prose in the merged-prd-not-archived bundled-section rendering** (Step 6). Describes hunks the maintainer would apply manually. Not an invocation. ✓
- Line 503 — `The skill ONLY proposes a diff or a command block. It MUST NOT call the Edit/Write tools…` — **prose invariant** describing propose-don't-apply. Not a call. ✓
- Line 515 — `**Propose-don't-apply** — … NEVER calls Edit/Write/perl -i/sed -i/git mv/git apply` — **backfill invariant prose** (Step B preamble). Documents the rule. ✓
- Line 608 — `Step B.3 — Write the bundled preview` — **writes `$OUT` (`.kiln/logs/prd-derived-from-backfill-*.md`)**, NOT any PRD file. Allowed by propose-don't-apply discipline (preview files, not audited files). ✓
- Line 646 — `The subcommand NEVER calls Edit/Write/perl -i/sed -i/git mv/git apply against any docs/features/*/PRD.md or products/*/features/*/PRD.md` — **backfill invariant prose**. Not a call. ✓

**Result**: **PASS**. The backfill subcommand body (lines 513–649) contains only:

1. `cat > $HUNKS_FILE` (writes to temp file — not a PRD).
2. `{ …compose hunk… } >> "$HUNKS_FILE"` (appends to temp file — not a PRD).
3. `{ …compose preview… } > "$OUT"` (writes to `.kiln/logs/…` — allowed).
4. `rm -f "$HUNKS_FILE"` (cleanup — not a PRD).

Zero actual invocations of Edit/Write/perl -i/sed -i/git mv/git apply against any PRD path under `docs/features/` or `products/*/features/`.

## Grep Gate 2 — Diagnostic continuity (NFR-005)

**Requirement**: the 6-field diagnostic from PR #146 (`specs/pipeline-input-completeness/SMOKE.md`) MUST still be emitted by the new Step 4b on every run. Every original field name MUST still appear in the new diagnostic body.

**Commands + results**:

```bash
# The sole grep -E regex present in PR #146's SMOKE.md (line 195):
REGEX='^step4b: scanned_issues=[0-9]+ scanned_feedback=[0-9]+ matched=0 archived=0 skipped=[0-9]+ prd_path='

# Replay against the new 8-field line with matched=0 archived=0:
LINE='step4b: scanned_issues=0 scanned_feedback=0 matched=0 archived=0 skipped=0 prd_path=docs/features/2026-04-23-NONEXISTENT/PRD.md derived_from_source=scan-fallback missing_entries=[]'
echo "$LINE" | grep -Eq "$REGEX"
# → exit 0 — REGEX STILL MATCHES (un-anchored at end-of-line).
```

Per-field presence in new Step 4b body (`plugin-kiln/skills/kiln-build-prd/SKILL.md`):

| Field | hits | status |
|---|---|---|
| `scanned_issues=` | 4 | ✓ present |
| `scanned_feedback=` | 4 | ✓ present |
| `matched=` | 4 | ✓ present |
| `archived=` | 4 | ✓ present |
| `skipped=` | 4 | ✓ present |
| `prd_path=` | 4 | ✓ present |

**Result**: **PASS**. All 6 original fields appear in positions 1–6 of the new 8-field template (`DIAG_LINE=` on line 791). Fields 7 (`derived_from_source`) and 8 (`missing_entries`) are APPENDED after `prd_path=${PRD_PATH_NORM}`. No field is reordered, removed, or renamed. PR-#146 grep anchors are preserved.

## Smoke-fixture replay (live)

Ran SMOKE.md §5.1 (distill frontmatter writer) and §5.3 (hygiene backfill) end-to-end in scratch dirs:

- **§5.1 distill** — `head -6 PRD.md` confirms key order `---` / `derived_from:` / list / `distilled_date:` / `theme:` / `---`; frontmatter paths byte-for-byte equal Source Issues table paths (SC-001, SC-006 OK).
- **§5.2 Step 4b** — simulated 8-field lines (frontmatter + scan-fallback); BOTH extended regex (contracts §2.6.1) AND PR-#146 regex (§2.6.2) match BOTH lines (SC-002, SC-003, NFR-005 OK).
- **§5.3 backfill** — ran the Step B.2 body under `bash` (not zsh) against a mixed-state fixture with 1 migrated PRD + 1 unmigrated PRD. `HUNK_COUNT=1` (migrated correctly skipped, unmigrated hunk contains `.kiln/issues/u.md`). Idempotence (FR-010) verified: migrated PRD produced zero hunks. (SC-004, SC-005 OK.)

## Phase F SC-007 verification replay

Ran the `read_derived_from()` helper (contracts §2.1 verbatim) against two real PRDs in this repo:

- `docs/features/2026-04-23-pipeline-input-completeness/PRD.md` (pre-migration, no frontmatter) → **empty output → scan-fallback fires** ✓
- `docs/features/2026-04-24-prd-derived-from-frontmatter/PRD.md` (this feature's own PRD; hand-authored, no frontmatter) → **empty output → scan-fallback fires** ✓ (expected per Decision D3: hand-authored PRDs carry no `derived_from:`)

No migrated PRDs currently exist under `docs/features/` — all 40 PRDs are LEGACY, which is consistent with the feature being brand-new. The backfill subcommand is the maintainer's entry point for migrating the existing 40 in one review pass (FR-009, FR-010, FR-011).

## R-1 blessed deviations

### D-1 — POSIX awk `match()` instead of gawk 3-arg form

**Contracts impacted**: §4.2 (backfill table parser), §5.1 (SMOKE distill assertion).

**Original contract**: `match($0, /\]\(([^)]+)\)/, m)` + `m[1]` (gawk-only 3-argument form).

**What implementer shipped**: POSIX-portable `match(s, /\]\([^)]+\)/)` + `RSTART` / `RLENGTH` + `substr` + `sub` to strip `](` prefix and `)` suffix.

**R-1 blessing justification**:

- Strict behavioral superset: identical output byte-for-byte (`](path)` → `path`).
- Plan.md §Architecture explicitly commits to POSIX tools; the 3-arg `match()` form is a gawk extension and therefore VIOLATED the stated constraint. The POSIX form TIGHTENS compliance without changing observable behavior.
- Portability improvement: works on BSD awk (macOS default), gawk, mawk, busybox awk. The original form would silently fail on default macOS installations. Without this fix, SMOKE.md §5.1's assertion 2 would `FAIL` the first time a maintainer ran it on macOS without `brew install gawk`.

**Decision**: BLESSED under R-1 precedent (hygiene rubric's 2× application of the strict-behavioral-superset rule). Contracts §4.2 and §5.1 text stays as-shipped; no revert required.

## Disposition of implementer-flagged items

The implementer's friction notes flagged 5 suggestions for the next pipeline. None require immediate action in this PR:

1. **POSIX awk enforcement** — suggests plugin-level smoke test for gawk-only constructs. Good follow-on PRD material (out of scope here since D-1 resolved the only instance caught in this spec).
2. **Shared `read_derived_from()`** — suggests factoring the helper to `plugin-kiln/scripts/lib/`. Deferred; duplication today is 2 files (build-prd + hygiene). Crossing the abstraction threshold depends on a 3rd consumer or NFR-002 portability discipline for lib scripts. Not blocking.
3. **SMOKE.md E2E harness that actually invokes skills** — today's fixtures simulate expected output. Real invocation would need a harness that Claude can run against a scratch dir. Good retrospective material.
4. **Diagnostic arity invariant helper** — a `plugin-kiln/scripts/assert-step4b-diag.sh` that runs all active regexes would automate NFR-005 replay across future diagnostic extensions. Nice-to-have.
5. **Rubric cross-reference index** — `plugin-kiln/rubrics/README.md` with rule_id → spec-ref table. Editorial, not blocking.

Caveat from the implementer: **SC-007 end-to-end `/kiln:kiln-build-prd` was not run against a live consumer repo** — only load-bearing invariants (helper behavior + diagnostic line shape + both regexes matching) were exercised in isolation. Noted as a retrospective follow-on. This does NOT block merge: the isolated-invariant verification is sufficient per the spec's acceptance bar (SC-007 requires "PR-#146 SMOKE.md §5.3 grep regex against the captured diagnostic line STILL matches" — which it does).

## Ambiguity notes

### A-1 — The feature's own PRD is not migrated

`docs/features/2026-04-24-prd-derived-from-frontmatter/PRD.md` (the PRD for THIS feature) does not carry `derived_from:` frontmatter. This is expected:

- The PRD predates this pipeline shipping. It was hand-authored (or authored before the distill writer could add the block).
- Per Decision D3, hand-authored PRDs are a valid pattern and fall through the scan-fallback path.
- A maintainer who wants this PRD migrated can run `/kiln:kiln-hygiene backfill` after merge, review the generated hunk in `.kiln/logs/prd-derived-from-backfill-*.md`, and apply it manually.

This is the intended bootstrap path — the feature ships with readers able to handle both migrated and legacy PRDs, and the maintainer chooses when to migrate.

## Suggestions for the next pipeline

1. **Run `/kiln:kiln-hygiene backfill` against this repo as a post-merge hygiene task** — 40 LEGACY PRDs under `docs/features/` are a good real-world shakedown for FR-009/FR-010/FR-011. The resulting `.kiln/logs/prd-derived-from-backfill-*.md` would be the first large-scale validation of the backfill subcommand's path-validation, table-parsing, and annotation logic.
2. **Add a `/kiln:kiln-doctor` subcheck that greps SKILL.md files for gawk-only idioms** — the implementer caught D-1 during Phase E, but an earlier tripwire would have caught it in Phase A. See implementer suggestion #1.
3. **Consider the 3rd consumer threshold for `read_derived_from()`** — today it's duplicated in build-prd Step 4b and hygiene Step 5c. Any future PRD that also needs frontmatter reading (e.g., a `kiln-distill` post-hoc validator that checks `derived_from:` ↔ Source Issues table drift) becomes the natural trigger to factor it out.
4. **`/kiln:kiln-distill` smoke fixture that writes to a scratch dir and invokes the SKILL** — the current approach (hand-compose the expected PRD + assert shape) misses regressions where the SKILL body's template diverges from contracts §1. An E2E harness would have caught Phase A body-template drift if any had occurred.
5. **Retrospective scope**: the pipeline kickoff → merge took 3 agents (specifier, implementer, auditor) and 6 phase commits. That's healthy pipeline shape. The specifier's friction notes about "could this be a hygiene subcommand" (Decision D1) turned out to be the right call — consolidating propose-don't-apply under one entry point is a clear win. Good material for the retrospective.

## Deferred pre-merge gates

None. All gates passed.

## Compliance summary

| Dimension | Coverage | Notes |
|---|---|---|
| FRs (11) | 11/11 = 100% | Every FR has code + test + spec coverage |
| NFRs (5) | 5/5 = 100% | NFR-004 (no new MCP calls) verified by grep — no new `mcp__` references in changed files |
| SCs (8) | 8/8 = 100% | All 8 SCs mapped to SMOKE fixture or implementer verification log |
| Blockers | 0 | No blockers.md file created |
| R-1 deviations | 1 (D-1) | Blessed — POSIX awk tightening |
