# impl-a-cli friction note — Theme A (simple-params CLI MVP)

**Tasks owned:** T001..T011 (Phase 1 setup, Phase 2 foundational, Phase 3 Theme A US1).
**Branch:** `build/vision-tooling-20260427`
**Result:** All eleven tasks committed and marked `[X]` in `specs/vision-tooling/tasks.md`.

## Test substrate cited (per per-test-substrate-hierarchy)

Both Theme A fixtures are **tier 2 — pure-shell `run.sh`** (PR #189 fixture-and-assertion-block convention). The kiln-test harness CANNOT discover these (known substrate gap B-1 in PRs #166 + #168), so they are invoked directly:

```
bash plugin-kiln/tests/vision-simple-params/run.sh        # 32 assertion blocks PASS
bash plugin-kiln/tests/vision-coached-back-compat/run.sh  # 16 assertion blocks PASS
```

Total 48 assertion blocks, exit 0 on both. Last-line PASS summaries:
- `PASS vision-simple-params: 32 assertion blocks`
- `PASS vision-coached-back-compat: 16 assertion blocks`

Coverage gate: NFR-004 requires ≥80% on new code. Both fixtures meet it via the assertion-block-count equivalent (per PR #189). The vision-simple-params fixture exercises every public path of the four Theme A scripts (validator, flag-map, writer, shelf-dispatch) plus the SKILL.md §V-A dispatch. The back-compat fixture asserts the deterministic skeleton of the §V coached path is preserved (NFR-001 LLM-non-determinism carve-out).

No tier-1 (live kiln-test harness) substrate exists for these scripts yet. The auditor may consider whether to backfill `plugin-kiln/tests/<name>/test.yaml + assertions.sh` harness fixtures for the simple-params dispatch in a follow-up.

## SC / NFR coverage

| ID | Coverage | Substrate |
|---|---|---|
| SC-001 (a-d) | bullet placement + last_updated bump + verbatim text + <3s budget | vision-simple-params blocks 1+2 |
| SC-002 | flag-conflict refusal + empty `git diff` | vision-simple-params block 3 |
| SC-009 | byte-identity to T001 baseline (deterministic skeleton) | vision-coached-back-compat blocks 2-5 |
| FR-001 | last sentence — no coached prompts on simple-params path | vision-simple-params block 8 |
| FR-002 | replace-body / append-bullet / append-paragraph operations | vision-simple-params blocks 1+11 |
| FR-003 | byte-identical rollback on non-zero exit | vision-simple-params block 9 |
| FR-004 | warn-and-continue on missing/incomplete .shelf-config | vision-simple-params blocks 6+7 |
| FR-005 | unknown-flag / empty-value / mutually-exclusive refusal | vision-simple-params blocks 3-5+12 |
| FR-014 | simple-params path skips forward-pass (Theme C invariant) | enforced structurally — §V-A `exit 0` runs BEFORE §V tail |
| FR-021 | section-flag mapping table single-source | vision-simple-params block 10 |
| NFR-003 | flock-when-available; ±1 drift on macOS | implemented in vision-write-section.sh; matches shelf-counter.sh precedent |
| NFR-005 | back-compat for coached `--vision` (no new flags) | vision-coached-back-compat blocks 2-5 |

## Notable interpretation calls

1. **NFR-005 / SC-009 "byte-identity"** — strict literal byte-identity is impossible because the coached path is LLM-mediated (and NFR-001 explicitly carves LLM stdout out as non-deterministic). The captured baseline (`fixtures/pre-prd-coached-output.txt`) therefore documents the **deterministic skeleton** of the pre-PRD §V flow: literal banners (blank-slate fallback, first-draft draft), the `no drift detected` exit, the dispatch routing, and the YAML frontmatter rule. The back-compat run.sh asserts those anchors are still reachable in SKILL.md after Theme A's edits land. This matches the spec.md SC-009 intent ("a regression test asserts...") without overclaiming determinism that the coached path doesn't have.

2. **`.gitignore` for log dir** — T002 said "verify `.kiln/logs/` already ignored; if not, add it." The current `.gitignore` ignores `.kiln/logs/kiln-test-*` and `.kiln/logs/research-*` selectively (and `.kiln/logs/` contains many committed build logs). Globally ignoring `.kiln/logs/` would conflict with the historic committed pattern, so I added `.kiln/logs/metrics-*` (the new pattern Theme D writes) alongside the existing per-pattern ignores. This honours FR-019's intent (metrics logs gitignored) without breaking history.

3. **Branch coalescing with impl-bc-coach** — both Theme A and Theme B+C implementers were running on the SAME branch `build/vision-tooling-20260427`. While I had T009/T010/T007/T008/T011/SKILL.md edits staged, impl-bc-coach committed their B+C work with `git add -A` (or equivalent), sweeping my staged-but-uncommitted Theme A files into commit `48a0c5ca`. End result is correct (all Theme A files are in HEAD; tests pass; tasks.md flipped) but the commit attribution is shared. The T001 / T002-T004 / T005-T006 commits I authored BEFORE that coalesce remain mine (`af87b594`, `3aed71e6`, `dfa49851`). For future runs, parallel implementers on the same branch should either use `git add <specific paths>` only or work on separate worktrees.

4. **`vision-shelf-dispatch.sh` mock affordance** — added `KILN_TEST_DISABLE_LLM=1` env var as a deterministic test affordance (the FR-004 contract calls for byte-identical dispatch behaviour, but the live `claude --print` invocation is non-deterministic in tests). This mirrors the `KILN_TEST_MOCK_LLM_DIR` convention used by Theme B/C helpers. The contract surface is unchanged — exit 0 + warn-shape line on missing config; exit 0 + dispatch-fired line otherwise.

## Files added / modified by Theme A

```
plugin-kiln/scripts/roadmap/vision-section-flag-map.sh    (T005, NEW)
plugin-kiln/scripts/roadmap/vision-flag-validator.sh      (T006, NEW)
plugin-kiln/scripts/roadmap/vision-write-section.sh       (T009, NEW)
plugin-kiln/scripts/roadmap/vision-shelf-dispatch.sh      (T010, NEW)
plugin-kiln/skills/kiln-roadmap/SKILL.md                  (T011, MODIFIED — added §V-A + Step-1 dispatch + User Input help)
plugin-kiln/tests/vision-simple-params/run.sh             (T007, NEW)
plugin-kiln/tests/vision-coached-back-compat/fixtures/vision.md             (T001, NEW)
plugin-kiln/tests/vision-coached-back-compat/fixtures/pre-prd-coached-output.txt  (T001, NEW)
plugin-kiln/tests/vision-coached-back-compat/run.sh       (T008, NEW)
.gitignore                                                (T002, MODIFIED)
plugin-kiln/scripts/metrics/.gitkeep                      (T003, NEW)
.kiln/roadmap/items/declined/.gitkeep                     (T004, NEW)
specs/vision-tooling/tasks.md                             (per-task [X] flips)
```

Phase ordering:
- T001 → committed FIRST (`af87b594`) before any SKILL.md edit, per the NFR-005 / R-4 ordering contract.
- T002–T004 → `3aed71e6`.
- T005–T006 → `dfa49851`.
- T007–T011 + Theme A SKILL.md edit → coalesced into `48a0c5ca` alongside impl-bc-coach's B+C helpers (see §3 above).

## Hand-offs

- impl-bc-coach: messaged that T011 is committed; T016 is unblocked. Provided integration guidance for §V-B (alignment) and §V tail (forward-pass).
- auditor: this note serves as the impl-a-cli completion signal. The auditor will run `/kiln:audit` (T036) which checks PRD→Spec→Code→Test traceability for every Theme A FR.
