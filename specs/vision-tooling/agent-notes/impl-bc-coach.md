# Friction note — impl-bc-coach (Themes B + C)

**Agent**: impl-bc-coach
**Tasks owned**: T012–T015 (Theme B), T017–T022 (Theme C, including T016 + T022 SKILL.md edits)
**Substrate cited**: pure-shell unit fixtures (`bash plugin-kiln/tests/<feature>/run.sh`) per the test-substrate-hierarchy convention. `kiln-test` cannot discover these fixtures (substrate gap B-1 in PRs #166/#168), but `bash run.sh` is fully self-contained and reports `PASS=N FAIL=M` on the last line plus exit `0`/`1` for the harness.

## Substrate evidence

| Test | Substrate | Last line | Exit | Assertions |
|---|---|---|---|---|
| `plugin-kiln/tests/vision-alignment-check/run.sh` | pure-shell `run.sh` | `PASS: vision-alignment-check (13 assertions)` | 0 | 13 PASS / 0 FAIL |
| `plugin-kiln/tests/vision-forward-pass/run.sh`    | pure-shell `run.sh` | `PASS: vision-forward-pass (18 assertions)`    | 0 | 18 PASS / 0 FAIL |

Live `kiln-test` substrate not used: it does not discover `plugin-kiln/tests/<name>/run.sh` fixtures (only the `test.yaml + assertions.sh + inputs/` shape). This is the documented gap B-1 — a known substrate limitation, NOT a PR-introduced regression.

## Notable friction

1. **Concurrent commit collision with impl-a-cli.** When I staged my Theme B + C files via explicit `git add <paths>`, the commit picked up `plugin-kiln/skills/kiln-roadmap/SKILL.md` + Theme A scripts that impl-a-cli had already `git add`-ed but not yet committed. The commit at SHA `48a0c5ca` therefore bundles T011 (impl-a-cli) alongside T012-T015 + T017-T021 (mine). This silently delivered T011 ahead of the coordination message; downstream effect is benign (T011 was complete and tested) but the commit boundary is ambiguous. Recommend the coordinator add an explicit "do not stage SKILL.md until T011 commit handshake fires" rule for parallel implementer agents in future builds.

2. **macOS BSD `grep -P` portability.** First pass of `tests/vision-forward-pass/run.sh` used `grep -qP '^…\t…$'` (PCRE) for a tab-separated assert. BSD grep on macOS doesn't support `-P`. Switched to `awk -F'\t'`. Recurring trap — every macOS-targeting test fixture should use `awk` for tab-separated assertions, not `grep -P`.

3. **The `--promote` hand-off is `accept` only by message.** The Theme C accept routing does NOT directly invoke `/kiln:kiln-roadmap --promote` from inside the SKILL.md — instead it surfaces `Promote-pending: <title> ...` to stdout and lets the user re-invoke the promote skill. Reason: `/kiln:kiln-roadmap` is calling itself, and shelling into the same skill from within is a cycle the runtime doesn't model cleanly. Alternative ergonomic improvement (V2): the accept arm could write the suggestion as a `.kiln/issues/<date>-<slug>.md` capture and let the next `/kiln:kiln-roadmap --promote` flow pick it up. Captured as a follow-on candidate for the next cycle.

4. **SC-010 / FR-014 simple-params guard is double-enforced.** The FR-014 invariant ("forward-pass MUST NOT fire on simple-params") is enforced structurally by §V-A.4's `exit 0` (which exits before reaching §V-C). I also added a defensive `case "$ARGUMENTS"` guard at the top of §V-C as a belt-and-braces second line so a future refactor that lets simple-params fall through to §V cannot silently regress SC-010. The dual enforcement is intentional; the comment in §V-C.1 documents it.

5. **LLM-mediated helpers (FR-007 mapper, FR-011 forward-pass) are fully mock-injected for tests.** Both `vision-alignment-map.sh` and `vision-forward-pass.sh` honour `KILN_TEST_MOCK_LLM_DIR` per CLAUDE.md Rule 5. No live `claude --print` calls fire from inside the test fixtures. Live-spawn validation of the LLM grounding (with real `claude --print`) is an auditor follow-on.

## SKILL.md edit ordering

- Phase 4 helpers + tests committed at SHA `48a0c5ca` (also bundled T009/T010/T011).
- Phase 5 helpers + tests committed at SHA `48a0c5ca` (same commit).
- T016 (§V-B alignment-check) + T022 (§V-C forward-pass tail) committed in a follow-on commit — sequenced AFTER T011 was visible in the index, honouring the SKILL.md serialization rule.

## What I didn't touch

- Phase 1 (T001–T004) — owned by setup; verified file presence only.
- Phase 2 (T005–T006) — owned by impl-a-cli; verified by `vision-flag-validator.sh` invocation in §V-A.1.
- Phase 3 helpers (T009/T010) and SKILL.md edit (T011) — owned by impl-a-cli; bundled into my Phase 4+5 commit due to the staging collision noted above.
- Phase 6 (T023–T035, Theme D) — owned by impl-d-metrics; verified by `git log` showing SHA `0825b94c`.
- Phase 7 (T036–T040) — auditor + smoke-tester scope.
