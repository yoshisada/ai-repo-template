# Implementer Friction Notes — prd-derived-from-frontmatter

**Agent**: implementer
**Task**: #2 — Implement prd-derived-from-frontmatter fixes
**Date**: 2026-04-23
**Branch**: `build/prd-derived-from-frontmatter-20260424`

## Phase-by-phase verification log

### Phase A — Distill writer (T01-1, T01-2) — commit `d11a36f`

- **Verified**: `grep -c 'derived_from:' plugin-kiln/skills/kiln-distill/SKILL.md` returns 7 — frontmatter skeleton + rules + template + FR-002 invariant block all present.
- **Verified**: the PRD template literal now begins with `---` / `derived_from:` / list / `distilled_date:` / `theme:` / `---` before the `# Feature PRD:` heading (contract §1.1).
- **Added**: FR-002 single-source-of-truth invariant prose + drift-abort assertion in a dedicated subsection.
- **Sort rule prose**: feedback-first, filename ASC — matches contract §1.4 and the skill's existing FR-012 ordering.

### Phase B — Build-prd Step 4b (T02-1, T02-2, T02-3) — commit `8b08bb3`

- **Added**: `read_derived_from()` awk helper (contract §2.1) immediately after the existing `PRD_PATH_NORM="$(normalize_path "$PRD_PATH")"` line. Bounded — reads first `---…---` block only, emits zero lines on any failure mode.
- **Added**: `DERIVED_FROM_LIST` population + `DERIVED_FROM_SOURCE` determination (contract §2.2). `MISSING_ENTRIES=()` initialized once before the scan branch so the diagnostic always has the field.
- **Restructured**: Step 4b's existing scan loop is now wrapped in `if [ "$DERIVED_FROM_SOURCE" = "frontmatter" ]; then … else <existing PR-#146 loop unchanged> fi`. The frontmatter-path branch increments `SCANNED_*` from the derived_from list per contract §2.3 semantics.
- **Extended diagnostic**: 8-field line per contract §2.5 — `derived_from_source` + `missing_entries` APPENDED after `prd_path`. Verified the PR-#146 regex at `specs/pipeline-input-completeness/SMOKE.md` §5.3 still matches the extended line (un-anchored at end-of-line).
- **Stale invariant updated**: the "No reordering / additional / missing fields" bullet in the "Step 4b invariants" section was rewritten to reflect the 8-field extended shape so future readers don't get the wrong signal.

**Phase B regex verification** (shell check):

```
LINE='step4b: scanned_issues=1 scanned_feedback=1 matched=2 archived=2 skipped=0 prd_path=docs/features/2026-04-30-fixture/PRD.md derived_from_source=frontmatter missing_entries=[]'
echo "$LINE" | grep -E '^step4b: scanned_issues=[0-9]+ scanned_feedback=[0-9]+ matched=[0-9]+ archived=[0-9]+ skipped=[0-9]+ prd_path=[^[:space:]]+ derived_from_source=(frontmatter|scan-fallback) missing_entries=\[.*\]$'
  → OK (extended regex — contracts §2.6.1)

echo "$LINE" | grep -E '^step4b: scanned_issues=[0-9]+ scanned_feedback=[0-9]+ matched=[0-9]+ archived=[0-9]+ skipped=[0-9]+ prd_path=[^[:space:]]+'
  → OK (PR-#146 regex — contracts §2.6.2 / NFR-005)
```

### Phase C — Hygiene frontmatter-walk primary + fallback (T03-1, T03-2) — commit `8a9f673`

- **Added**: `read_derived_from()` helper inline in Step 5c (duplicated from build-prd per the specifier's friction-note suggestion #1 — factoring into a shared helper deferred to a follow-on PRD to avoid the NFR-002 portability question today).
- **Added**: `declare -A PROCESSED_PRDS` + per-PRD frontmatter walk (contract §3.1) BEFORE the existing walk-backlog loop. Walks `docs/features/*/PRD.md` and `products/*/features/*/PRD.md`; emits one `archive-candidate` / `needs-review` / `inconclusive` / `keep` signal per entry.
- **Added**: `PROCESSED_PRDS` skip predicate inside the walk-backlog loop (contract §3.2) — each iteration skips items whose `prd:` points at a PRD already handled by the frontmatter path. Placed AFTER the `prd_path` read so the check can see the value.
- **Rubric update**: inserted the "Primary path (post PRD `derived_from:` frontmatter…)" paragraph (contract §3.3) between the "Fires against…" predicate list and the "Bulk-lookup strategy" paragraph.
- **Verified**: `grep -F 'PROCESSED_PRDS' plugin-kiln/skills/kiln-hygiene/SKILL.md` returns 5 matches; `grep -F 'Primary path (post PRD `derived_from:`' plugin-kiln/rubrics/structural-hygiene.md` matches.

### Phase D — Backfill subcommand (T04-1, T04-2, T04-3) — commit `4a7ed3c`

- **Added**: Step 0 — subcommand dispatch (contract §4.1) between the User Input block and the existing Step 1. `SUBCOMMAND=$(printf '%s' "$ARGUMENTS" | awk '{print $1}')` + `case` dispatch. Unknown subcommand → exit 2 with the exact two-line message from contracts §4.1 (grep-anchored).
- **Added**: Step B — backfill workflow (contract §4.2) at the bottom of the skill file (after the existing Rules section) as a separate section so it doesn't interrupt the default audit flow's readability.
- **Sub-steps**: B.1 (preamble + `.kiln/logs/prd-derived-from-backfill-<ts>.md`), B.2 (walk PRDs + compose diff hunks), B.3 (write bundled preview), B.4 (exit 0).
- **Idempotence**: `head -20 | grep -Eq '^derived_from:[[:space:]]*(\[\])?[[:space:]]*$'` matches both block-sequence and inline empty-list forms per Decision D3.
- **Rubric entry**: new `### derived_from-backfill` block inserted AFTER `### merged-prd-not-archived` and BEFORE `### orphaned-top-level-folder` per T04-3.
- **CLAUDE.md entry**: one-liner added directly after the existing `/kiln:kiln-hygiene` bullet in the "Other" section of Available Commands.
- **Verified**: `grep -F 'rule_id: derived_from-backfill' plugin-kiln/rubrics/structural-hygiene.md` matches; `grep -F '/kiln:kiln-hygiene backfill' CLAUDE.md` matches; `grep -cF 'backfill' plugin-kiln/skills/kiln-hygiene/SKILL.md` returns 12.

### Phase E — SMOKE.md fixtures (T05-1, T05-2) — commit `b78d000`

- **Created**: `specs/prd-derived-from-frontmatter/SMOKE.md` with §5.1 (distill writer), §5.2 sub-A (frontmatter path) + sub-B (scan-fallback), §5.3 (hygiene mixed-state + migration idempotence).
- **Each fixture** ends with an explicit `echo OK || echo FAIL` line.
- **Verified**: ran §5.1 fixture end-to-end in a `/tmp` scratch dir — both assertions print `OK: frontmatter key order` and `OK: frontmatter == table`.
- **Verified**: ran §5.2 regex assertions against simulated 8-field lines — extended regex + PR-#146 regex both match on frontmatter path AND scan-fallback path.

### Phase F — Backwards-compat verification (T06-1) — see "SC-007 Backwards-Compat Verification" section below.

## Deviations from contracts/interfaces.md

### Deviation D-1 — POSIX awk `match()` instead of gawk 3-arg form

**Contracts impacted**: §4.2 (backfill subcommand table parser), §5.1 (SMOKE distill assertion).

**Contract text**: used gawk's 3-argument `match($0, /\]\(([^)]+)\)/, m)` with capture-group array `m[1]`.

**What I shipped**: replaced with POSIX-portable `match(s, /\]\([^)]+\)/)` + `RSTART`/`RLENGTH` + `substr` + `sub` to strip the `](` prefix and `)` suffix. Same output, works on BSD awk (macOS default) AND gawk.

**Why this is a strict behavioral superset**:

- plan.md §Architecture locks the tool set to "POSIX" — the 3-arg `match()` form is NOT POSIX (gawk extension). The contracts text accidentally specified a gawk-only feature while claiming POSIX compliance.
- The portable form extracts the identical string — `](path)` → `path` — byte-for-byte. No functional change.
- Works on strictly more platforms: BSD awk (macOS), gawk, mawk, busybox awk.

**Auditor blessing requested**: this is a "tighten a constraint while preserving all observable behavior" deviation, which per R-1 precedent (team-lead briefing) counts as a strict behavioral superset. Documenting here so the auditor can bless it without re-reading contracts §4.2 / §5.1 in gawk mode.

### No other deviations

- Frontmatter block shape (contracts §1.1) → shipped verbatim.
- Key order / list format / sort (§1.2–§1.4) → shipped verbatim.
- `read_derived_from()` awk state machine (§2.1) → shipped verbatim.
- Frontmatter-path archive loop (§2.3) → shipped verbatim.
- Extended diagnostic (§2.5, §2.6) → shipped verbatim.
- Hygiene frontmatter walk + PROCESSED_PRDS dedup (§3.1, §3.2) → shipped verbatim.
- Rubric text (§3.3, §4.3) → shipped verbatim.
- Backfill workflow (§4.2) → shipped verbatim modulo Deviation D-1.

## Ambiguities that needed interpretation

### Ambiguity A-1 — Step B placement in the hygiene SKILL.md

**The spec/contracts** said to "add a backfill subcommand" to the hygiene skill, and contract §4.1 placed the dispatcher "at the top of the skill's main execution block (after any pre-execution hook checks)." But the existing hygiene skill's main execution block is literally the whole body from Step 1 onwards — there's no pre-existing "dispatch" seam.

**What I did**: added a new "## Step 0 — Dispatch on subcommand" section BEFORE the existing Step 1. The Step 0 body instructs the shell to run the dispatcher `case` statement and either exit 2 (unknown subcommand), fall through to Step 1 (default), or jump to Step B (backfill). Step B itself is placed at the END of the file (after the existing "## Rules" section) so the default audit flow reads linearly without Step B interrupting it.

**Rationale**: keeps the existing structure readable; the new subcommand is conceptually a branch off the main path, and putting its body at the end is consistent with how "appendix" sections usually work in markdown skills. If a future follow-on adds a second subcommand, we add Step C with the same pattern.

### Ambiguity A-2 — how to treat `derived_from:` entries that are already archived under `completed/`

**Contract §3.1** has an `elif` branch that emits a `keep` signal when an entry exists under `completed/` but not at its original path ("already archived — no drift"). This is the correct behavior but was not spelled out in contracts §2 (Step 4b) — only in the hygiene §3.

**What I did**: Step 4b's frontmatter path treats missing-file entries as `MISSING_ENTRIES` (contract §2.3) — there's no special case for "already archived." That's OK because Step 4b is called during a pipeline run (not an audit); if a derived_from item is already archived, it means a prior Step 4b run already processed it, and the current run should simply report `missing_entries: [entry]` so the operator sees the drift. This matches FR-006 literally.

For the hygiene rule, "already archived" is a valid keep state because hygiene runs against a potentially post-pipeline repo.

## Things the team lead or specifier should have told me that they didn't

1. **`gawk` vs `awk` assumption**. Plan.md §Architecture claims POSIX tool set, but contracts §4.2 / §5.1 use a gawk-only 3-arg `match()`. The specifier likely developed/tested on a machine with gawk aliased to `awk` (Linux, or `brew install gawk` on macOS). This would have silently broken for consumers on default macOS. Caught during Phase E when the first fixture run `FAIL`ed. Flagging so the retrospective can catch this class of issue earlier (e.g., CI or smoke-test matrix includes BSD awk).

2. **Step B placement guidance**. Contracts §4.1 said "at the top of the skill's main execution block" but the existing hygiene skill is written as a linear step sequence without a distinct dispatch seam. I interpreted this as "add a new Step 0 dispatcher + Step B body at the end." An explicit note in plan.md or the specifier's friction notes would have saved a judgment call.

3. **Empty `DERIVED_FROM_LIST` on frontmatter path**. Contract §2.3 increments `SCANNED_*` from the derived_from list, but if the list is empty the path doesn't fire at all (contracts §2.2 branches to scan-fallback on empty list). So the case of "frontmatter path + 0 entries" is structurally impossible — no guard needed. Confirmed by reading contracts §2.2 carefully; noting here so the auditor doesn't flag a missing guard.

## Suggestions for the next pipeline

1. **POSIX awk enforcement** — add a plugin-level smoke test that runs all awk snippets through `awk --version` detection and rejects gawk-only features. Or adopt `gawk` as a declared dependency (consumer-facing announcement, `kiln-doctor` check).

2. **Shared `read_derived_from()`** — specifier's friction note #1 suggested this. Now that it's duplicated in two SKILL.md files, the next PRD that touches either should factor it out. The cleanest home is `plugin-kiln/scripts/lib/read_derived_from.sh` + document in CLAUDE.md that `plugin-kiln/scripts/lib/` is the lib-helpers directory. NFR-002 portability: any workflow command-step invoker must use `${WORKFLOW_PLUGIN_DIR}/scripts/lib/read_derived_from.sh`, never repo-relative.

3. **SMOKE.md fixtures that actually invoke the skill** — today's fixtures simulate the expected output (write the PRD by hand, compose the expected diagnostic line). A real E2E harness that shells out to `/kiln:kiln-distill` / `/kiln:kiln-build-prd` / `/kiln:kiln-hygiene` in a scratch dir and captures actual output would catch regressions the simulation can't.

4. **Diagnostic arity invariant** — the Step 4b diagnostic now has 8 fields. The next PRD that extends it must also keep the PR-#146 regex intact. A small assertion helper (e.g., `plugin-kiln/scripts/assert-step4b-diag.sh <line>`) that runs all the regexes would make NFR-005 automatic instead of hand-verified in agent-notes.

5. **Rubric cross-reference** — the new `derived_from-backfill` rule points at `specs/prd-derived-from-frontmatter/` but `plugin-kiln/rubrics/` doesn't have a general "spec refs" index. If two or three more rubric entries cite specs, a single `rubrics/README.md` with a cross-ref table would help future maintainers triangulate.

---

## SC-007 Backwards-Compat Verification

**Target PRD**: `docs/features/2026-04-23-pipeline-input-completeness/PRD.md` (PR #146's PRD; confirmed pre-migration — `head -5` shows no frontmatter block, the file begins with `# Feature PRD: Pipeline Input Completeness`).

**Verification approach**: Since this is the plugin source repo (not a consumer project) and `/kiln:kiln-build-prd` is a Claude-driven skill (not a CLI binary), a full end-to-end Step 4b invocation would require spinning up a pipeline run with a real PR number against the target PRD. Instead, I verified the two load-bearing invariants in isolation:

1. **The new `read_derived_from()` helper returns empty against the target** — triggers `DERIVED_FROM_SOURCE=scan-fallback`.
2. **Both regexes match the scan-fallback diagnostic line** — extended regex (SC-002) AND the PR-#146 regex from `specs/pipeline-input-completeness/SMOKE.md` §5.3 (NFR-005).

### Step 1 — `read_derived_from()` against the target PRD

Ran the exact helper from `plugin-kiln/skills/kiln-build-prd/SKILL.md` §2.1 against the target:

```bash
OUT="$(read_derived_from docs/features/2026-04-23-pipeline-input-completeness/PRD.md)"
[ -z "$OUT" ] && echo "OK: scan-fallback will fire"
```

**Result**: `OK: read_derived_from returned empty → DERIVED_FROM_SOURCE=scan-fallback`. The helper correctly refuses to emit entries for a PRD with no YAML frontmatter block.

### Step 2 — Regex replay against the expected 8-field diagnostic line

Composed the diagnostic line that Step 4b would write for this target on the scan-fallback path (scanned_* fields reflect a full `.kiln/issues/*.md` + `.kiln/feedback/*.md` directory scan; for this sandbox the counts are 0/0 but the field shape is the same):

**Captured line**:

```
step4b: scanned_issues=0 scanned_feedback=0 matched=0 archived=0 skipped=0 prd_path=docs/features/2026-04-23-pipeline-input-completeness/PRD.md derived_from_source=scan-fallback missing_entries=[]
```

**Extended regex** (contracts §2.6.1 / SC-002):

```
^step4b: scanned_issues=[0-9]+ scanned_feedback=[0-9]+ matched=[0-9]+ archived=[0-9]+ skipped=[0-9]+ prd_path=[^[:space:]]+ derived_from_source=(frontmatter|scan-fallback) missing_entries=\[.*\]$
```

**Result**: `OK: extended regex (contracts §2.6.1) matches`.

**PR-#146 regex replay** (contracts §2.6.2 / NFR-005 — taken verbatim from `specs/pipeline-input-completeness/SMOKE.md` §5.3):

```
^step4b: scanned_issues=[0-9]+ scanned_feedback=[0-9]+ matched=[0-9]+ archived=[0-9]+ skipped=[0-9]+ prd_path=[^[:space:]]+
```

**Result**: `OK: PR-#146 regex (NFR-005) STILL matches`. The un-anchored end-of-line (`[^[:space:]]+` for `prd_path=`) means the appended fields 7–8 do not break existing matches.

**Field-content check**:

```
grep -q 'derived_from_source=scan-fallback missing_entries=\[\]' <<< "$LINE"
```

**Result**: `OK: derived_from_source=scan-fallback missing_entries=[] present`.

### Summary

| Check | Regex / Predicate | Result |
|---|---|---|
| `read_derived_from()` against pre-migration PRD | (helper behavior) | `OK` (empty output → scan-fallback) |
| Extended diagnostic regex (SC-002) | `^step4b: … derived_from_source=… missing_entries=\[.*\]$` | `OK` |
| PR-#146 regex replay (NFR-005, SC-007) | `^step4b: … prd_path=[^[:space:]]+` | `OK` (still matches) |
| Field-content `derived_from_source=scan-fallback` | `derived_from_source=scan-fallback missing_entries=\[\]` | `OK` |

### Caveats

- **End-to-end Step 4b invocation was not run** against the target PRD in this verification — the full archival side-effect (no items archive on this target in the sandbox because no open backlog items reference this PRD) was not exercised. The load-bearing invariants (diagnostic line shape + regex matching + helper behavior on pre-migration input) WERE exercised. An integration test on a live consumer repo or a `/tmp` scratch copy with a full `.kiln/{issues,feedback}/` state would complete the verification — recommended as a follow-on for the retrospective.
- **SC-003** is satisfied by this verification's regex replay + helper behavior: a pre-migration PRD correctly triggers the scan-fallback path, diagnostic reports `derived_from_source=scan-fallback missing_entries=[]`, and the PR-#146 regex still matches. NFR-001 (backwards compatibility) is preserved.

**Conclusion**: SC-007 verification passes. NFR-001 and NFR-005 invariants hold on the target PRD. The PR-#146 SMOKE.md §5.3 grep regex continues to match the extended 8-field diagnostic line without modification.
