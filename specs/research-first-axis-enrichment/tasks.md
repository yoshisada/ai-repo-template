# Tasks: Research-First Axis Enrichment — Per-Axis Direction Gate + Time/Cost Axes

**Input**: Design documents from `/specs/research-first-axis-enrichment/`
**Prerequisites**: spec.md (✅), plan.md (✅), contracts/interfaces.md (✅), research.md §baseline (✅).

**Tests**: Tests are REQUIRED — anchored to SC-AE-001..009 + foundation backward-compat re-runs.

**Organization**: Phases A + D run sequentially. Phases B and C are **STRICTLY INTERLEAVED** per NFR-AE-005 atomic-pairing — there is no "axes-only" or "gate-only" subset.

## Format

`[T###] [P?] [Phase] [Anchor] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Phase]**: A | B+C (interleaved) | D | E
- **[Anchor]**: FR-AE-* / NFR-AE-* / SC-AE-* anchor for traceability
- Include exact file paths in descriptions

---

## Phase A: Config files + frontmatter parser + monotonic clock

**Purpose**: Land the data files + the standalone helpers that B+C need before runner extension begins. Phase A is a pure-additive surface — no foundation files are touched.

- [X] **T001** [A] [FR-AE-004 / NFR-AE-007 / §7] Author `plugin-kiln/lib/research-rigor.json` with the exact 4-key shape from contracts §7. Values: isolated `{min_fixtures: 3, tolerance_pct: 5}`, feature `{min_fixtures: 10, tolerance_pct: 2}`, cross-cutting `{min_fixtures: 20, tolerance_pct: 1}`, infra `{min_fixtures: 20, tolerance_pct: 0}`. Verify `jq . plugin-kiln/lib/research-rigor.json` returns 0.
- [X] **T002** [P] [A] [FR-AE-010 / NFR-AE-007 / §8] Author `plugin-kiln/lib/pricing.json` with the **RECONCILED 2026-04-25 pricing values** from contracts §8 (NOT PRD example numbers): opus `{input_per_mtok: 5.00, output_per_mtok: 25.00, cached_input_per_mtok: 0.50}`, sonnet `{input_per_mtok: 3.00, output_per_mtok: 15.00, cached_input_per_mtok: 0.30}`, haiku `{input_per_mtok: 1.00, output_per_mtok: 5.00, cached_input_per_mtok: 0.10}`. Verify `jq . plugin-kiln/lib/pricing.json` returns 0.
- [X] **T003** [P] [A] [FR-AE-001 / FR-AE-004 / FR-AE-006 / §3] Author `plugin-wheel/scripts/harness/parse-prd-frontmatter.sh` (~80 LoC). Hand-rolled YAML frontmatter parser following `plugin-wheel/scripts/agents/compose-context.sh` precedent. Validates metric ∈ {accuracy, tokens, time, cost, output_quality}, direction ∈ {lower, higher, equal_or_better}, priority ∈ {primary, secondary}, blast_radius ∈ {isolated, feature, cross-cutting, infra}. Loud-failure on invalid values. Stdout: `jq -c -S` byte-stable JSON projection. `chmod +x`.
- [X] **T004** [P] [A] [FR-AE-009 / NFR-AE-006 / §6] Author `plugin-wheel/scripts/harness/resolve-monotonic-clock.sh` (~40 LoC). Probe ladder: python3 → gdate → /bin/date → abort with documented `Bail out!`. Probe is deterministic (same host → same result). `chmod +x`.

**Checkpoint A**: All four Phase-A files exist and pass `jq` / shell-syntax checks. No runner code touched yet.

---

## Phase B+C (INTERLEAVED): Gate refactor + time/cost axes

**Purpose**: Land the per-axis direction gate AND the time/cost axes in lock-step. **NFR-AE-005 atomic-pairing forbids carving these out.** Each task either touches both surfaces or is a per-axis test fixture exercising both.

### Helpers (parallel)

- [ ] **T005** [P] [B+C] [FR-AE-002 / FR-AE-005 / §4] Author `plugin-wheel/scripts/harness/evaluate-direction.sh` (~60 LoC). Inputs: `--axis --direction --tolerance-pct --baseline --candidate`. Stdout: `pass` or `regression`. Floating-point comparison via `awk`. Loud-failure on invalid inputs. `chmod +x`.
- [ ] **T006** [P] [B+C] [FR-AE-011 / FR-AE-012 / §5] Author `plugin-wheel/scripts/harness/compute-cost-usd.sh` (~50 LoC). Inputs: `--pricing-json --model-id --input-tokens --output-tokens --cached-input-tokens`. Stdout: 4dp-precision USD float OR `null`. Stderr warning on model-miss; loud-failure (`Bail out!`) on malformed pricing.json.

### Runner extension (sequential — single file)

- [ ] **T007** [B+C] [FR-AE-001 / FR-AE-008 / §2] Extend `plugin-wheel/scripts/harness/research-runner.sh` to add the `--prd <path>` flag. When omitted: take foundation strict-gate codepath (`gate_mode=foundation_strict`). When provided + PRD has `empirical_quality:`: take per-axis-direction codepath (`gate_mode=per_axis_direction`). When provided + PRD has no `empirical_quality:`: take strict-gate codepath but still display `--prd` provenance in report header. Invokes `parse-prd-frontmatter.sh` at startup; surfaces `Bail out!` for invalid PRD per §2 bail-out diagnostics table.
- [ ] **T008** [B+C] [FR-AE-009 / NFR-AE-006 / FR-AE-014] Extend `research-runner.sh` to invoke `resolve-monotonic-clock.sh` at startup, capture `time_seconds` per arm via the resolved invocation, and populate `baseline.time_seconds` + `candidate.time_seconds` + `delta_time_seconds` in the per-fixture JSON shape (§1). Time-axis is always measured + populated regardless of declaration; gate-enforcement is conditional on declaration.
- [ ] **T009** [B+C] [FR-AE-011 / FR-AE-012 / §1] Extend `research-runner.sh` to invoke `compute-cost-usd.sh` per arm with token tuples + model_id from transcript's `message.model`, populating `baseline.cost_usd`, `candidate.cost_usd`, `baseline.model_id`, `candidate.model_id`, `delta_cost_usd` in the per-fixture JSON shape. Surface `pricing-table-miss: <model>` warnings to the per-fixture `warnings` array. Emit `Bail out! cost axis declared but no fixture produced a cost_usd value …` when ALL fixtures null AND cost is declared.
- [ ] **T010** [B+C] [FR-AE-002 / FR-AE-003 / FR-AE-005 / FR-AE-014] Extend `research-runner.sh` to dispatch on `gate_mode`. In `per_axis_direction`, iterate over `empirical_quality` declarations + invoke `evaluate-direction.sh` per axis per fixture using `tolerance_pct` from the resolved rigor row. Emit `accuracy` always (implicit `equal_or_better`); emit declared-but-undeclared axes as `not-enforced` in `per_axis_verdicts`. In `foundation_strict`, take the explicit fall-through codepath (Decision 7) preserving foundation strict-gate output byte-identically modulo `time_seconds`/`cost_usd` columns.
- [ ] **T011** [B+C] [FR-AE-004 / NFR-AE-007 / SC-AE-002] Extend `research-runner.sh` to read `blast_radius:` from PRD frontmatter, look up rigor row from `plugin-kiln/lib/research-rigor.json`, and enforce `min_fixtures` PRE-subprocess. Failure shape: `Bail out! min-fixtures-not-met: <N> < <M> (blast_radius: <radius>[, <K> fixtures excluded])`. NEVER fall back to a hardcoded default rigor row.
- [ ] **T012** [B+C] [FR-AE-006 / FR-AE-007 / SC-AE-006] Extend `research-runner.sh` to honor `excluded_fixtures: [{path, reason}]` — skip fixture-load (no scratch dir), record exclusion in report's "Excluded" section, count AGAINST `min_fixtures`. Emit `excluded-fraction-high: <N>/<M> (<P>%) exceeds 30% threshold` warning when applicable. Loud-failure when excluded path doesn't exist in corpus.
- [ ] **T013** [B+C] [NFR-AE-001] Extend `research-runner.sh` to compute median wall-clock per fixture (across baseline + candidate) and silently un-enforce the time axis when median < 1.0s. Emit `time-axis-skipped: <slug> wall-clock <N.Ns> below 1.0s floor` warning to the fixture's `warnings` array. Other axes still gate-evaluated.

### Per-axis test fixtures (parallel — distinct files)

- [ ] **T014** [P] [B+C] [SC-AE-001] Author `plugin-kiln/tests/research-runner-axis-direction-pass/run.sh` + fixtures. Asserts: PRD declaring `empirical_quality: [{metric: time, direction: lower}, {metric: tokens, direction: equal_or_better}]` + candidate that improves time + holds tokens flat → `Overall: PASS`. Same candidate against single-axis time-only declaration also passes. `chmod +x` run.sh.
- [ ] **T015** [P] [B+C] [SC-AE-002] Author `plugin-kiln/tests/research-runner-axis-min-fixtures-cross-cutting/run.sh` + fixtures. Asserts: 5-fixture corpus + PRD with `blast_radius: cross-cutting` → exit 2 + `Bail out! min-fixtures-not-met: 5 < 20` PRE-subprocess. NO scratch dirs created.
- [ ] **T016** [P] [B+C] [SC-AE-003] Author `plugin-kiln/tests/research-runner-axis-infra-zero-tolerance/run.sh` + fixtures. Asserts: 20-fixture corpus + PRD `blast_radius: infra` + `empirical_quality: [{metric: tokens, direction: equal_or_better}]` + candidate with +1 token on one fixture → `Overall: FAIL`.
- [ ] **T017** [P] [B+C] [SC-AE-004] Author `plugin-kiln/tests/research-runner-axis-cost-mixed-models/run.sh` + fixtures. Asserts: corpus mixing opus + haiku model_ids → per-fixture `cost_usd` matches hand-computed `(in × $/in + out × $/out + cached × $/cached) / 1_000_000` to 4dp. Hand-computed values use RECONCILED pricing (opus 5/25/0.5, haiku 1/5/0.1).
- [ ] **T018** [P] [B+C] [SC-AE-006] Author `plugin-kiln/tests/research-runner-axis-excluded-fixtures/run.sh` + fixtures. Asserts: 4-fixture corpus + `excluded_fixtures: [{path: 002-flaky, reason: "..."}]` + `blast_radius: isolated` (min_fixtures=3) → fixture skipped, recorded in "Excluded" section, run proceeds with 3 active fixtures. Plus negative case: 4-fixture corpus with 2 excluded + min_fixtures=3 → exit 2 with `Bail out! min-fixtures-not-met: 2 < 3`.
- [ ] **T019** [P] [B+C] [FR-AE-012 / Edge case] Author `plugin-kiln/tests/research-runner-axis-pricing-table-miss/run.sh` + fixtures. Asserts: corpus with one fixture whose transcript has `message.model: "<unknown-model>"` → that fixture's `cost_usd: null` + warning `pricing-table-miss: <unknown-model>` in report aggregate. Run still proceeds on other axes.
- [ ] **T020** [P] [B+C] [SC-AE-009] Author `plugin-kiln/tests/research-runner-axis-no-monotonic-clock/run.sh` + fixtures. Asserts: with PATH stripped of python3 + gdate + /bin/date → runner exits 2 at startup with `Bail out! no monotonic %N-precision clock available; install python3 (preferred) or coreutils (gdate)`. NO fixture iteration begins.

**Checkpoint B+C**: 9 new tests pass + foundation strict-gate behavior preserved (verified by SC-AE-005 in Phase D). Atomic-pairing invariant (NFR-AE-005) verified — `git diff main...HEAD --name-only` contains BOTH `plugin-kiln/lib/research-rigor.json` AND `plugin-kiln/lib/pricing.json` AND the runner extensions.

---

## Phase D: Report extensions + backward-compat audit + docs

**Purpose**: Land the report-renderer extensions, run backward-compat verification, update docs.

- [ ] **T021** [D] [FR-AE-015 / FR-AE-016 / §9] Extend `plugin-wheel/scripts/harness/render-research-report.sh` (~134 → ~200 LoC). Add 4 new columns to per-fixture markdown table per Decision 1 (`Time B/C`, `Δ Time`, `Cost B/C`, `Δ Cost`, `Per-Axis Verdict`). Extend aggregate to add `Excluded fixtures`, `PRD`, `Gate mode`, `Blast radius`, `Rigor row`, `Declared axes` lines. Render optional "Excluded Fixtures" + "Warnings" subsections per §9. Verify per-fixture column-budget on a 30-char-slug fixture (≤ 120 cols).
- [ ] **T022** [D] [SC-AE-005 / NFR-AE-003 / §11] Author `plugin-kiln/tests/research-runner-axis-fallback-strict-gate/run.sh` + fixtures. Asserts: invocation WITHOUT `--prd` flag + invocation with `--prd` to a PRD with no `empirical_quality:` → both produce reports byte-identical to foundation strict-gate output modulo §3 exclusion comparator. ALSO re-runs foundation's 5 existing fixtures (`research-runner-pass-path`, `research-runner-regression-detect`, `research-runner-determinism`, `research-runner-missing-usage`, `research-runner-back-compat`) → all 5 pass with their pre-PRD verdicts.
- [ ] **T023** [D] [SC-AE-007 / FR-AE-013] Author `plugin-kiln/tests/research-runner-axis-pricing-stale-audit/run.sh` + fixtures. Asserts: setting `pricing.json` mtime to 200 days ago + running auditor's mtime probe → `agent-notes/audit-compliance.md` gets `pricing-table-stale: 200d since mtime` finding. Also asserts: running the runner itself with the same 200-day-old pricing.json → exits normally (audit-time tripwire, not a gate).
- [ ] **T024** [D] [FR-AE-016 / Foundation NFR-S-009] Extend `plugin-wheel/scripts/harness/README-research-runner.md` (≤ 250 LoC total). Add three new sections: "Authoring `empirical_quality:` in PRD frontmatter", "Configuring blast-radius rigor", "Time + Cost axes in reports". Each section ≤ 50 LoC. Worked example using a synthetic PRD with all four axes declared.
- [ ] **T025** [D] [Foundation §7 / §10 / FR-AE-001] Extend `plugin-kiln/skills/kiln-research/SKILL.md` (~5 LoC added — total stays ≤ 50). Document `--prd <path>` flag + gate-mode dispatch.
- [ ] **T026** [D] [SC-AE-008 / NFR-AE-005] Author audit-compliance subcheck: `git diff main...HEAD --name-only | grep -E 'plugin-kiln/lib/(research-rigor|pricing)\.json'` MUST find BOTH files. If only one is in the diff, audit-compliance teammate REJECTS the PR + surfaces NFR-AE-005-non-compliant blocker in `agent-notes/audit-compliance.md`. Also verify untouchable foundation files via §11 listing.

**Checkpoint D**: Report renderer extended; backward-compat verified via SC-AE-005 (foundation's 5 fixtures + axis-enrichment fallback fixture); README + SKILL extended; atomic-pairing tripwire wired.

---

## Phase E: Audit + smoke + retrospective (orchestrator-driven)

**Purpose**: Final compliance gates. These tasks are owned by separate teammates per the orchestrator's task list — listed here for traceability only.

- [ ] **T027** [E] [audit-compliance teammate] PRD compliance audit per `/kiln:kiln-audit`. Verifies every PRD FR/NFR/SC has a spec FR/NFR/SC + implementation + test anchor. Writes `agent-notes/audit-compliance.md`.
- [ ] **T028** [E] [audit-smoke teammate] End-to-end smoke audit. Runs `bash plugin-wheel/scripts/harness/research-runner.sh --baseline <main> --candidate <main> --corpus <axis-enrichment-seed> --prd <synthetic-prd-with-empirical-quality>` + verifies report shape against §9. Writes `agent-notes/audit-smoke.md`.
- [ ] **T029** [E] [audit-pr teammate] PR creation with reconciled summary. Writes `agent-notes/audit-pr.md`.
- [ ] **T030** [E] [retrospective teammate] Retrospective on prompt/communication effectiveness. Writes `agent-notes/retrospective.md`.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase A** (T001..T004) → no dependencies, all can run in parallel except T001 (sequential because the runner reads it at startup; but T001 is just authoring a static JSON file with no helper dependency, so practically parallel with T002..T004 in this phase).
- **Phase B+C** (T005..T020) → depends on Phase A complete.
- **Phase D** (T021..T026) → depends on Phase B+C complete (T021 extends the renderer based on the per-fixture JSON shape produced by T007..T013).
- **Phase E** (T027..T030) → depends on Phase D complete.

### Within Phase B+C — atomic-pairing constraint (NFR-AE-005)

- T005 + T006 → can run in parallel (distinct helper files).
- T007 + T008 + T009 + T010 + T011 + T012 + T013 → sequential, single shared file (`research-runner.sh`). Implementer commits after each task.
- T014..T020 → all parallel (distinct test-fixture directories).

### Parallel Opportunities

- Phase A: T001..T004 effectively parallel (T001 just needs to land before T011 in B+C, which is many tasks later).
- Phase B+C helpers: T005 || T006 (parallel).
- Phase B+C runner extension: T007 → T008 → T009 → T010 → T011 → T012 → T013 (sequential — single file).
- Phase B+C tests: T014..T020 fully parallel.
- Phase D: T021 → T022 → T023 → T024 || T025 || T026 (T024..T026 parallel).
- Phase E: T027 || T028 (parallel), then T029 → T030.

---

## Implementation Strategy

### Atomic pairing first (NFR-AE-005)

The implementer MUST NOT carve out an "axes-only" or "gate-only" PR. The exit criterion for Phase B+C is: BOTH the gate refactor AND the time/cost axes work end-to-end in the same commit graph. The atomic-pairing tripwire (T026) is the ship-blocking gate — verify before opening the PR.

### Backward-compat verification (NFR-AE-003)

T022 (SC-AE-005) is the load-bearing backward-compat anchor. Foundation's 5 existing fixtures MUST pass post-PRD. If they don't, the implementer pauses + escalates via `specs/research-first-axis-enrichment/blockers.md` rather than papering over with renderer hacks.

### Loud-failure on config malformation (NFR-AE-007)

T001 + T002 + T003 + T011 all enforce loud-failure. The implementer MUST NEVER write a silent fallback when a config file is malformed or missing. Tests T015 + T020 + (parts of T019) are the tripwires.

### Sub-second guard (NFR-AE-001)

T013 is the sub-second guard for the time axis. Implementer MUST surface the warning prominently (per Decision 2, in the aggregate "Warnings" subsection — not the per-fixture table).

### Commit cadence

- After Phase A (T001..T004): one commit, message `axis-enrichment: Phase A — config files + frontmatter parser + monotonic-clock helper`.
- After Phase B+C helpers (T005..T006): one commit, `axis-enrichment: Phase B+C — direction-evaluator + cost-deriver helpers`.
- After each runner-extension task (T007..T013): one commit per task, message `axis-enrichment: T0NN — <description>`.
- After each test-fixture task (T014..T020): one commit per task.
- After Phase D (T021..T026): one commit, `axis-enrichment: Phase D — report extensions + backward-compat audit + docs`.

---

## Notes

- [P] tasks operate on distinct files, no dependencies.
- [Anchor] maps every task to a specific FR-AE-* / NFR-AE-* / SC-AE-* anchor for traceability.
- Atomic-pairing (NFR-AE-005) is the load-bearing structural constraint — Phase B+C is INTERLEAVED, not phased.
- Foundation untouchability (§11): T007..T013 + T021 are the only files that may grow vs main; verify via `git diff main...HEAD --name-only` against the §11 untouchable list.
- Verify all 9 new tests fail BEFORE the runner extensions land (Phase A tests against unmodified runner should fail-fast on `--prd` flag rejection — verify this, then proceed).
