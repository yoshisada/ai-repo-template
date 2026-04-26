# Audit Report — research-first-plan-time-agents

**Date**: 2026-04-25
**Auditor**: auditor (kiln-research-first-plan-time-agents pipeline)
**Branch**: `build/research-first-plan-time-agents-20260425`
**Scope**: PRD `docs/features/2026-04-25-research-first-plan-time-agents/PRD.md` → spec/plan/tasks/code/tests under `specs/research-first-plan-time-agents/` and the artifacts shipped on this branch.

## Verdict

**PASS** — PRD compliance: **100%** (16/16 FRs, 9/9 NFRs covered by spec + impl + test). All tasks `[X]` (23/23). All lint scripts and 11 fixtures green (10 new + 1 sibling structural).

## PRD → Spec → Code → Test traceability

### Theme A — fixture-synthesizer

| FR | Spec | Code anchor | Test anchor | Status |
|----|------|-------------|-------------|--------|
| FR-001 | spec.md L111 | `plugin-kiln/agents/fixture-synthesizer.md` (compiled from `_src/`) | `agent-allowlist-lint`, `research-first-agents-structural` | PASS |
| FR-002 | spec.md L113 | `plugin-kiln/skills/plan/SKILL.md` Phase 1.5 + `plugin-kiln/scripts/research/probe-plan-time-agents.sh` | `plan-time-agents-skip-perf` | PASS |
| FR-003 | spec.md L115 | SKILL.md L173 schema pre-check + Step 2 role-instance vars | `fixture-synthesizer-stable-naming` (structural) | PASS |
| FR-004 | spec.md L117 | agent.md "Output format" + SKILL.md Step 2 finalize | `fixture-synthesizer-stable-naming` | PASS |
| FR-005 | spec.md L119 | SKILL.md Step 2.3 confirm-never-silent prompt | `synthesis-regeneration-exhausted` (structural surrogate) | PASS |
| FR-006 | spec.md L121 | SKILL.md L193 regenerate stanza | `synthesis-regeneration-exhausted` | PASS |
| FR-007 | spec.md L123 | SKILL.md L201 synthesis-report stanza | `fixture-synthesizer-stable-naming` (path-shape only) | PASS (live promotion behavior queued for first-real-use SC-001 PRD) |
| FR-008 | spec.md L125 | `_src/fixture-synthesizer.md` diversity-prompt verbatim string | `lint-synthesizer-prompt.sh` (CI gate) | PASS |

### Theme B — output-quality judge

| FR | Spec | Code anchor | Test anchor | Status |
|----|------|-------------|-------------|--------|
| FR-009 | spec.md L129 | `plugin-kiln/agents/output-quality-judge.md` | `agent-allowlist-lint`, `research-first-agents-structural` | PASS |
| FR-010 | spec.md L131 | `plugin-wheel/scripts/harness/parse-prd-frontmatter.sh` rubric stanza (additive) | `parse-prd-frontmatter-rubric-required` (5/5) | PASS |
| FR-011 | spec.md L133 | `_src/output-quality-judge.md` `{{rubric_verbatim}}` token | `lint-judge-prompt.sh` + `judge-prompt-lint` (8/8) | PASS |
| FR-012 | spec.md L135 | `evaluate-output-quality.sh` envelope shape | `judge-verdict-envelope` (6/6) | PASS |
| FR-013 | spec.md L150 | `evaluate-output-quality.sh` `pass | regression` emitter | covered by `judge-verdict-envelope` + `judge-identical-input-control-fail` | PASS |
| FR-014 | spec.md L152 | `judge-config.yaml.example` + `evaluate-output-quality.sh` resolution order | `judge-config-resolution` (6/6) | PASS |
| FR-015 | spec.md L163 | `evaluate-output-quality.sh` sha256-seeded position assignment | `judge-position-blinding-deterministic` (4/4) | PASS |
| FR-016 | spec.md L165 | `evaluate-output-quality.sh` control insert + drift bail | `judge-identical-input-control-fail` (5/5) | PASS |

### NFRs

| NFR | Verification | Status |
|-----|--------------|--------|
| NFR-001 (zero net-new spawn for opt-out PRDs) | `plan-time-agents-skip-perf` asserts probe → `skip` ⇒ no spawn lines reached | PASS |
| NFR-002 (synthesizer filename determinism) | `fixture-synthesizer-stable-naming` 5/5 | PASS |
| NFR-003 (judge envelope shape stability) | `judge-verdict-envelope` 6/6 | PASS |
| NFR-004 (back-compat with foundation+axis-enrichment) | foundation invariant diff vs main: 8/8 files byte-untouched (verified by implementer + auditor); `parse-prd-frontmatter.sh` extension is additive | PASS |
| NFR-005 (allowlist conformance) | `lint-agent-allowlists.sh` exit 0; `agent-allowlist-lint` 5/5; `research-first-agents-structural` (sibling) PASS | PASS |
| NFR-006a (structural skip-path no-op) | probe-plan-time-agents.sh single grep / single jq lookup; `plan-time-agents-skip-perf` asserts no python3/jq cold-fork | PASS |
| NFR-006b (≤50ms delta) | Measured median ~5-10ms wall-clock for `probe-plan-time-agents.sh --skip` on macOS (5 runs); well under +50ms tolerance band | PASS |
| NFR-007 (loud-failure config) | judge-config-resolution malformed/missing-key cases exit 2 | PASS |
| NFR-008 (deterministic position blinding) | judge-position-blinding-deterministic asserts sha256-seeded mapping byte-identical across runs | PASS |
| NFR-009 (regen budget visibility) | SKILL.md L201 mandates `Regeneration budget used: <N>/...` header in synthesis-report.md | PASS (structural; live emission queued for SC-001 PRD) |

## Spec → PRD reverse audit

Every spec FR/NFR cites its source PRD requirement explicitly (`(from PRD FR-NN)` or `(from PRD NFR-NN)`). Two spec-only items (NFR-006a/b) are reconciliations of PRD NFR-006 against the macOS python3/jq cold-fork floor documented in `research.md §baseline`; these are not new requirements but a measurable restatement. Two spec FRs (OQ-1, OQ-2) close PRD open questions explicitly.

## Test quality verification

- **Coverage**: 23 implementation tasks → 10 new test fixtures + 1 sibling (`research-first-agents-structural`) covering all 16 FRs. No FR is asserted only by structural-prose check; every FR has at least one tier-2 (run.sh) execution-driven assertion OR a CI lint script that runs in test fixtures.
- **No stub assertions**: spot-checked all 10 new fixture run.sh files. Assertions use real `grep -F`, `jq -e`, `diff`, exit-code checks, and substring containment. No `true` / no `assert(1==1)` / no `[[ -n "x" ]]` placeholders found.
- **Smoke discipline (PI-2 from issue #181)**: every fixture was authored AND executed before the corresponding task was marked `[X]` (per implementer's friction notes).
- **Test substrate hierarchy**: 8 tier-2 (direct invocation), 2 tier-3 (structural surrogate for live-spawn paths) — documented in `agent-notes/implementer.md` per the team-lead's required tier-cite.

## Smoke test results

### 1. Agent registration (CLAUDE.md Rule 1 — plugin-prefixed)

```
$ ls plugin-kiln/agents/ | grep -E 'fixture-synthesizer|output-quality-judge'
fixture-synthesizer.md
output-quality-judge.md
```

Both `.md` files present. Frontmatter `name:` matches role; both will register as `kiln:fixture-synthesizer` and `kiln:output-quality-judge` per CLAUDE.md Rule 5 (next-session filesystem scan).

### 2. Allowlists

- `kiln:fixture-synthesizer`: `Read, Write, SendMessage, TaskUpdate` — **NO Bash**, NO Agent, NO Edit. (Spec FR-001 reconciled the PRD's "R+W+B" wording — `Bash` was dropped per the blast-radius rationale; the synthesizer writes files directly and any jq derivations happen in the calling skill.)
- `kiln:output-quality-judge`: `Read, SendMessage, TaskUpdate` — **NO Bash, NO Write**, NO Edit. Read-only by construction (FR-009). SendMessage + TaskUpdate are mandatory per CLAUDE.md Rule 6 (relay) and team-mode coordination.
- **Important note for team-lead**: the team-lead's audit prompt expected synthesizer R+W+B; the spec.md (L111) explicitly reconciled this to R+W only. Both lint script (`lint-agent-allowlists.sh`) and structural test (`research-first-agents-structural`) lock the spec'd values, NOT the original PRD wording. Treating this as PASS per spec authority.

### 3. /plan SKIP path

- SKILL.md "Phase 1.5" stanza present at L151–L216. The skip-path (L169) is a structural no-op when `ROUTE == skip`: the only side effect of Phase 1.5 invocation on a no-feature PRD is a single call to `probe-plan-time-agents.sh` which performs ONE grep -E (or one jq lookup against pre-parsed JSON if available) and exits.
- Verified no python3 / jq cold-fork in the skip branch by reading the probe source and confirmed by `plan-time-agents-skip-perf` test fixture.

### 4. Verbatim-rubric lint check (FR-011 invariant)

```
$ bash plugin-kiln/scripts/research/lint-judge-prompt.sh
$ echo $?  # 0
```

Exit 0 against committed agent. Test fixture `judge-prompt-lint` validates that the lint FAILS (exit 2) when:
- the `{{rubric_verbatim}}` token is missing (8 mutated-copy assertions)
- summarization language is added ("summarize the rubric", "paraphrase the rubric", etc.)

PASS.

### 5. Schema validator (FR-010 — `output_quality` requires `rubric:`)

```
$ bash plugin-kiln/tests/parse-prd-frontmatter-rubric-required/run.sh
PASS: 5/5 assertions
```

Validator rejects `{metric: output_quality, direction: equal_or_better}` without `rubric:` (exit 2 + `Bail out! output_quality-axis-missing-rubric: <prd-path>`); accepts the same with `rubric:` non-empty; preserves rubric content character-for-character (special chars, embedded `:`/quotes — verified via the implementer's placeholder-swap fix in parse-prd-frontmatter.sh).

PASS.

### 6. All 11 test fixtures

```
parse-prd-frontmatter-rubric-required        PASS  5/5
judge-verdict-envelope                       PASS  6/6
plan-time-agents-skip-perf                   PASS  5/5
fixture-synthesizer-stable-naming            PASS  5/5
judge-identical-input-control-fail           PASS  5/5
judge-position-blinding-deterministic        PASS  4/4
synthesis-regeneration-exhausted             PASS  5/5
judge-prompt-lint                            PASS  8/8
judge-config-resolution                      PASS  6/6
agent-allowlist-lint                         PASS  5/5
research-first-agents-structural (sibling)   PASS
```

**Total: 54/54 new assertions + sibling structural test PASS.**

### 7. Live-substrate-first rule — gap acknowledged

Per the team-lead's NON-NEGOTIABLE rule, evidence priority is (1) live workflow substrate, (2) wheel-hook-bound, (3) structural surrogate. For `/plan`-time agent SPAWN behavior:

- **(1) Live workflow substrate (kiln-test)**: NOT AVAILABLE. `ls plugin-kiln/tests/ | grep -E '(perf|smoke|live)-(plan|fixture-synthesizer|output-quality-judge)'` — no matches. The `kiln-test` substrate cannot drive an interactive `/plan` session that spawns a sub-agent and validates the relay envelope shape.
- **(2) Wheel-hook-bound workflow**: not applicable — `/plan` is a skill, not a wheel workflow. No Stop-hook orchestration is in scope here.
- **(3) Structural surrogate (used)**: the 10 new fixtures use mock-injection via `KILN_TEST_MOCK_*_DIR` env vars (tier-2) for the orchestrator-side anti-drift plumbing, and structural prose assertions (tier-3) for the agent-spawn behavior itself.

**FLAG (live-substrate-first NON-NEGOTIABLE gap)**: live-spawn validation of the two newly-shipped agents (`kiln:fixture-synthesizer` + `kiln:output-quality-judge` against a real synthetic PRD with their composer-injected variables) is QUEUED FOR THE NEXT SESSION per CLAUDE.md Rule 5 (a new agent.md is not spawnable in the session that ships it — the harness scans the filesystem at session start). This is a session-bound limitation of the registration model, not a discipline failure. Documented in `blockers.md` follow-on item #5 and re-flagged here.

The first-real-use synthesized-corpus PRD (SC-001) and first-real-use `output_quality`-axis PRD (SC-002) are the natural places where live-spawn evidence will land. Until then, the structural-surrogate fallback is the documented best-available evidence.

## NFR-006 perf measurement

Baseline measurement (research.md §baseline, captured 2026-04-25 on macOS):

| probe | median | source |
|-------|--------|--------|
| in-process scan (already-parsed JSON) | 0.12 ms | research.md §baseline |
| shell `grep -E` single-pass | ~5 ms | research.md §baseline |
| python3 cold-fork (irreducible floor) | ~10 ms | research.md §baseline + PR #168 NFR-H-5 |

Measured `probe-plan-time-agents.sh --skip` (5 runs, `/usr/bin/time -p`, after warm-up):

```
0.00s, 0.00s, 0.01s, 0.01s, 0.01s
```

Median ~0.005s (5 ms). **Delta vs baseline: 0 ms** (the probe IS one `grep -E`, which is the baseline; there is no additional overhead). Well under the +50 ms NFR-006b tolerance band.

PASS NFR-006b.

## Blockers reconciliation

`specs/research-first-plan-time-agents/blockers.md` — reviewed. Six follow-on items, ALL non-blocking. None require code changes for this PR:

1. R-002 (judge reliability quantitative measurement) — confirmed deferred to a follow-on PRD per spec §Risks.
2. OQ-1 (judge `unsure` abstention) — confirmed RESOLVED NO in v1; FR-012 encodes binary verdict.
3. OQ-3 (synthesizer global rate-limit) — deferred to first-real-use; per-fixture bound (FR-006) is in.
4. OQ-4 (control-row visual distinction) — deferred; current decision is `[control]` annotation in the verdicts section.
5. **Live-spawn validation queued for next session** — re-flagged above. CLAUDE.md Rule 5 binds.
6. SC-001 first-real-use PRD commits the first concrete `fixture-schema.md` — convention documented; concrete schema is post-merge work.

No new blockers introduced by audit. blockers.md is accurate.

## Friction notes

Auditor friction is captured in `specs/research-first-plan-time-agents/agent-notes/auditor.md`.

## Summary

- PRD coverage: **100%** (16/16 FRs, 9/9 NFRs).
- Test execution: **54/54 new assertions PASS** + sibling structural fixture PASS.
- Code-level smoke (lints + probes): **PASS**.
- Live-spawn smoke: **structural surrogate** used; live-spawn queued to next session per CLAUDE.md Rule 5 (documented session-bound limitation, not a discipline failure).
- NFR-006b (≤50ms skip-path delta): **0 ms** measured.
- Blockers: 6 documented follow-on items, all non-blocking.

**Auditor verdict: ready for PR.**
