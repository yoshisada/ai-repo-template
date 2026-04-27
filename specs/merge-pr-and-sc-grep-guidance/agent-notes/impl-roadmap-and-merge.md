# impl-roadmap-and-merge — Friction Note

**Agent**: impl-roadmap-and-merge
**Team**: kiln-merge-pr-and-sc-grep
**Task**: #2 — Implement Theme A (kiln-merge-pr skill + auto-flip-on-merge.sh helper + Step 4b.5 refactor + roadmap --check --fix)
**Branch**: `build/merge-pr-and-sc-grep-guidance-20260427`
**Spec**: `specs/merge-pr-and-sc-grep-guidance/`

## Summary

All six commits landed cleanly. Six observables verified — SC-002 (byte-identity fixture), SC-003 (`wc -l` decreased 1502 → 1429), SC-004 (offline simulation of §C-fix passes both skip + ambiguous-fix-all paths). Helper extracted verbatim modulo three tightly-scoped concessions (documented below); zero behavior change at the diagnostic-line / exit-code / frontmatter-mutation level (NFR-002).

## Test substrate cited

**Substrate #2 — pure-shell unit fixtures (run.sh-only).** Per the team-lead's TEST SUBSTRATE HIERARCHY, the kiln-test harness CANNOT discover run.sh-only fixtures (B-1 substrate gap, NOT a discipline failure). My `plugin-kiln/tests/auto-flip-on-merge-fixture/run.sh` falls into substrate #2 — invoked directly:

```
$ bash plugin-kiln/tests/auto-flip-on-merge-fixture/run.sh
--- First run (expect: items=3 patched=3 already_shipped=0) ---
step4b-auto-flip: pr-state=MERGED auto-flip=success items=3 patched=3 already_shipped=0 reason=
--- Second run (expect: items=3 patched=0 already_shipped=3) ---
step4b-auto-flip: pr-state=MERGED auto-flip=success items=3 patched=0 already_shipped=3 reason=
PASS
exit=0
```

**Cross-substrate check**: re-running the existing `plugin-kiln/tests/build-prd-auto-flip-on-merge/run.sh` (escalation-audit's fixture, also substrate #2) against the refactored Step 4b.5 — `PASS=27 FAIL=0`. The existing fixture's awk-based extract pattern continues to parse the single-line replacement and routes through the new helper transparently. This is independent confirmation that the FR-009 refactor is truly zero-behavior-change at the substrate level, not just at the contract level.

## Extraction concessions (FR-008 verbatim → helper)

The FR-008 instruction reads "verbatim extraction of the existing Step 4b.5 inline block." I made three minimal, tightly-scoped concessions to make the extracted block runnable as a standalone script. Each is a structural adaptation, not a logic change. The diagnostic-line / exit-code / frontmatter-mutation observables remain byte-identical (NFR-002 verified by SC-002 fixture).

1. **Positional-arg parsing** — the inline block read `$PR_NUMBER` and `$PRD_PATH` from build-prd's enclosing scope. The standalone script reads them from `$1` and `$2`, with usage-error handling. Spec contract §A.1 mandates this.

2. **Inlined `read_derived_from()`** — the inline block called the function from build-prd's Step 4b body (line ~820). The standalone helper inlines the function verbatim from that source, no logic change. Documented in the script header.

3. **Sibling-script lookup via `$(dirname "$0")`** — the inline block invoked `bash plugin-kiln/scripts/roadmap/update-item-state.sh "$item" ...` (relative path that worked because Step 4b.5 ran from the repo root). The helper now resolves the sibling script via `HELPER_DIR="$(cd "$(dirname "$0")" && pwd)"` so it works from any CWD (canonical invocation: identical relative path; fixture invocation under `$TMP`: absolute path to the real script). No behavior change for the canonical invocation.

## Pre-snapshot source deviation (T013 / SC-002)

The contract §G.1 instructed capturing `golden/pre/<item>.md` from `git show 22a91b10^:.kiln/roadmap/items/<item>.md`. **I deviated**: pre-snapshots are captured from `git show 1c55419d^:...` instead.

**Why**: commit 22a91b10's parent (`22a91b10^` = `1c55419d`) is the **manually-flipped intermediate state** — items have `pr: #189` and `shipped_date:` already, just at a different frontmatter position. Feeding that to the helper short-circuits its idempotency guard (`grep -qE "^pr:[[:space:]]*#?189\b"` matches `pr: #189`) → all three items skipped as `already_shipped`, no mutations, output `items=3 patched=0 already_shipped=3`. The byte-diff against `golden/post` would FAIL because post has bare `pr: 189` at end of frontmatter while pre has `pr: #189` near top.

`1c55419d^` is the TRUE pre-merge state — `state: distilled`, `status: open`, no `pr:`, no `shipped_date:`. Feeding this to the helper produces three patched items matching commit 22a91b10's canonical state byte-for-byte. SC-002 byte-identity holds via this corrected source. Documented in run.sh header so future authors see the rationale.

## T013a conformance (date stability)

The team-lead pre-acked the `<TODAY>` placeholder approach for SC-002 byte-identity across days. Specifier added T013a making this explicit. My initial implementation used a date-stub via PATH (functionally equivalent — pinned `date -u +%Y-%m-%d` to 2026-04-27 inside the helper). Conformed to T013a's literal approach mid-pipeline:

- `golden/post/<item>.md` carries `shipped_date: <TODAY>` placeholder.
- `run.sh` materializes `$TMP/expected/<base>` via `sed "s/<TODAY>/$TODAY/g"` and diffs against the materialized expected file.
- Removed the date stub.

Both approaches yielded PASS. The placeholder approach has the advantage of not requiring a stub for `date`, which keeps the test environment closer to the real invocation environment — only `gh` is stubbed.

## Documentary-references rediscovery (T040 collision)

T040 asserts `grep -F 'git add -A' plugin-kiln/skills/kiln-merge-pr/SKILL.md` returns zero hits. My initial draft contained two **prohibition** references — both telling readers to AVOID the all-stage form, never to use it (e.g., `... — NEVER \`git add -A\` (retro #187 PI-1)`). The grep gate cannot distinguish prohibition prose from imperative usage.

This is **the exact same anti-pattern Theme C documents** for `${WHEEL_PLUGIN_<name>}` / `${WORKFLOW_PLUGIN_DIR}` documentary references. I rewrote both occurrences using "the all-stage form" rather than the literal token, preserving the exact-path discipline message without tripping the grep. Lesson: when reading impl-docs's Theme C output land, this lesson should land in the spec-template's authoring note too — grep-based SC sentinels are bidirectional tripwires (they catch usage and they catch prohibition prose). For PI consideration in retro: the spec-template note should explicitly warn authors that "MUST return zero hits" greps trip on prohibition prose.

## §C-fix DRIFT_LINES capture mechanism

The contract §C.2 says §C-fix "runs after Check 5's report assembly." I implemented this as: when the dispatch sees `--check --fix`, it sets `FIX_MODE=true` and the team-lead is expected to capture §C's stdout into `DRIFT_LINES` before invoking §C-fix. This is implicit in the dispatch instruction (line 150) and explicit in §C-fix's leading prose. **No changes to §C** — the existing Check 5 block emits identically, preserving NFR-004 backward-compat byte-identity.

For audit-tests: validating this requires the team-lead executing the dispatch correctly. The bash blocks themselves are recipes the team-lead orchestrates; they are not directly executable end-to-end without the team-lead's interpretation. T056 covers the §C-fix block in isolation by feeding pre-computed `DRIFT_LINES` directly.

## T056 simulation outcome (offline §C-fix exercise)

A full live `--check --fix` walk would mutate the working tree; instead, I exercised §C-fix directly with synthesized inputs:

- **Test 1 (empty input → skip)**: `Drift detected: 1 items. Choose action: [fix all / pick / skip]` → empty input → `fix=skipped items=0 patched=0 already_shipped=0 ambiguous=0`. NFR-004 confirm-never-silent ✓.
- **Test 2 ('fix all' with zero-match gh stub)**: `[ambiguous] 2026-04-27-fake-drift branch=build/fake-20260427 pr-matches=0 (skipped — implementer must NOT guess per FR-011)` → `fix=success items=0 patched=0 already_shipped=0 ambiguous=1`. Item NOT mutated; FR-011 ambiguity rule ✓.

This validates the dual confirm-never-silent + ambiguity-skip contract end-to-end without polluting any real roadmap items.

## Auto-staged ancillary files (version-increment hook)

Each phase commit pulled in 11 auto-staged files (VERSION + 5 plugin manifests + 5 package.jsons) bumped by the `version-increment.sh` hook. This is documented behavior per CLAUDE.md §"Versioning" — the hook auto-increments the 4th edit segment on every Edit/Write. The hook stages these files automatically; my `git add` calls only added the exact-path files I intended. **No `-A` was used.** The version-bump pre-staged set is not a discipline violation — it's the documented hook behavior. Logging here for auditor awareness.

## Plugin.json no-op (T037)

Confirmed pre-pipeline that `plugin-kiln/.claude-plugin/plugin.json` has no `skills` array. Skills are filesystem-auto-discovered from `plugin-kiln/skills/`. The team-lead corrected the file ownership mid-pipeline (dropped plugin.json from my scope, updated tasks.md). T037 is a no-op confirmation.

## Suggestions for retrospective (PI candidates)

1. **Spec-template authoring note should warn about the bidirectional grep tripwire** — sentinels of the form "grep MUST return zero hits" trip on prohibition prose just like usage. Theme B's authoring note should include this caveat alongside the date-bound qualifier rule. (PI for spec-template / impl-docs; out of my scope.)

2. **§C-fix's DRIFT_LINES capture is implicit** — the orchestration "team-lead captures §C stdout into DRIFT_LINES before running §C-fix" is described in prose, not encoded as a code recipe. Future maintainers may miss this. A possible PI: extract the drift-detection logic into a shared helper script (`plugin-kiln/scripts/roadmap/check-merged-pr-drift.sh`) so both §C and §C-fix call it directly, eliminating the implicit capture step.

3. **Date-stability via stubs vs placeholders** — the placeholder approach (T013a) is cleaner because it isolates test infrastructure from the helper's real invocation environment. Worth surfacing as a substrate convention for any future fixture that asserts byte-identity against a date-stamped artifact.

4. **Pre-snapshot capture path was wrong in the contract** — the contract §G.1 specified `22a91b10^` for the pre-merge state, but the actual commit predecessor in the chain has the manually-flipped intermediate state. Future fixtures asserting byte-identity against an auto-flip output need to capture pre-state from BEFORE the manual-flip-then-revert chain (here, `1c55419d^`). The specifier may want to revise §G.1's path guidance for any similar future fixture.

## Files touched

- NEW `plugin-kiln/skills/kiln-merge-pr/SKILL.md`
- NEW `plugin-kiln/scripts/roadmap/auto-flip-on-merge.sh`
- NEW `plugin-kiln/tests/auto-flip-on-merge-fixture/run.sh`
- NEW `plugin-kiln/tests/auto-flip-on-merge-fixture/golden/{prd.md,pre/*.md,post/*.md}`
- MOD `plugin-kiln/skills/kiln-build-prd/SKILL.md` (Step 4b.5 refactor: 80-line block → 5-line helper invocation; -73 net lines)
- MOD `plugin-kiln/skills/kiln-roadmap/SKILL.md` (frontmatter description, dispatch, §C-fix added)
- AUTO `VERSION`, `plugin-{kiln,clay,shelf,trim,wheel}/{.claude-plugin/plugin.json,package.json}` (version-increment hook on every edit, per CLAUDE.md §Versioning)

## Commits

1. `8ba6b3ee feat(roadmap): extract Step 4b.5 auto-flip block to shared helper (FR-008, NFR-002)`
2. `2972329d refactor(build-prd): step 4b.5 calls shared auto-flip-on-merge.sh helper (FR-009, SC-003)`
3. `b9685a66 feat(merge-pr): add /kiln:kiln-merge-pr skill — atomic merge + auto-flip (FR-001..FR-007, NFR-001)`
4. `3ff43bb3 feat(roadmap): --check --fix confirm-never-silent drift fixer (FR-010, FR-011)`
5. (this commit) `chore(specs): impl-roadmap-and-merge friction note + tasks.md [X] marks`

Phase 5 is the only Phase that lacked a fixture (the skill is end-to-end-tested via SC-001 / SC-007 live-fire on the PR for THIS PRD). Structural greps T038-T040 cover skill body shape.
