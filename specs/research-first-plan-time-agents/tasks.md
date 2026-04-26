# Tasks: Research-First Plan-Time Agents — fixture-synthesizer + output-quality-judge

**Input**: Design documents from `/specs/research-first-plan-time-agents/`
**Prerequisites**: spec.md (✅), plan.md (✅), contracts/interfaces.md (✅), research.md §baseline (✅).

**Tests**: Tests are REQUIRED — anchored to SC-001..SC-010. All tests mock the live agent spawn (per CLAUDE.md Rule 5 — newly-shipped agents are not live-spawnable in the same session); orchestrator-side determinism + envelope shape + lint-script behaviour are the live test surfaces.

**Organization**: Single implementer (`implementer`) executes phases A → B → C → D sequentially. Phases A + D are mostly parallel-friendly (`[P]`); phases B + C have a shared edit point (`/plan` SKILL.md + agent.md files) and run sequentially within phase to avoid file conflicts. The single-implementer rationale is in `agent-notes/specifier.md`.

## Format

`[T###] [P?] [Phase] [Anchor] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Phase]**: A | B | C | D
- **[Anchor]**: FR-* / NFR-* / SC-* / Decision-N anchor for traceability
- Include exact file paths in descriptions

---

## Phase A: Lint scripts + judge config example + frontmatter validator extension

**Purpose**: Land the standalone surfaces that have no dependency on agent prose or SKILL.md wiring. These are the prerequisite gates everything else builds on.

- [ ] **T001** [P] [A] [FR-014 / §5] Author `plugin-kiln/lib/judge-config.yaml.example` (~10 LoC) per contracts §5. Keys: `pinned_model: claude-opus-4-7` + `pinned_model_fallbacks: [claude-sonnet-4-6]`. Verify `python3 -c 'import yaml; yaml.safe_load(open("plugin-kiln/lib/judge-config.yaml.example"))'` returns 0 (NOTE: yaml is NOT a python stdlib module — implementer uses the same hand-rolled regex parser pattern as `plugin-wheel/scripts/agents/compose-context.sh` if PyYAML is unavailable; the verify-step uses a one-liner regex parse instead).
- [ ] **T002** [P] [A] [SC-003 / FR-011 / §9.1] Author `plugin-kiln/scripts/research/lint-judge-prompt.sh` (~30 LoC) per contracts §9.1. Asserts `{{rubric_verbatim}}` literal exists exactly once + no rubric-summarization regex matches. Exit 0 PASS, 2 FAIL with `Bail out! lint-judge-prompt: <reason>`. `chmod +x`.
- [ ] **T003** [P] [A] [FR-008 / §9.2] Author `plugin-kiln/scripts/research/lint-synthesizer-prompt.sh` (~20 LoC) per contracts §9.2. Asserts diversity-prompt verbatim string exists. Exit 0 PASS, 2 FAIL. `chmod +x`.
- [ ] **T004** [P] [A] [NFR-005 / §9.3] Author `plugin-kiln/scripts/research/lint-agent-allowlists.sh` (~30 LoC) per contracts §9.3. Asserts the literal `tools:` allowlist strings on both agent files. Exit 0 PASS, 2 FAIL. `chmod +x`.
- [ ] **T005** [A] [FR-010 / NFR-007 / §3 / SC-007] Extend `plugin-wheel/scripts/harness/parse-prd-frontmatter.sh` with the additive `rubric:` validator: when `metric: output_quality`, require non-empty `rubric:`. On failure exit 2 with `Bail out! output_quality-axis-missing-rubric: <abs-prd-path>`. The existing JSON projection shape is UNCHANGED — the `rubric` field is preserved character-for-character (no normalization). Integrate the new validator stanza inline; do NOT fork the script.

**Checkpoint A**: T001..T005 complete. Run `bash plugin-kiln/scripts/research/lint-judge-prompt.sh` against the existing stub `plugin-kiln/agents/output-quality-judge.md` — EXPECT FAIL (the stub doesn't have the rubric token yet). This is the expected red state until Phase B lands. Run `bash plugin-kiln/scripts/research/lint-synthesizer-prompt.sh` — EXPECT FAIL similarly. Run `bash plugin-kiln/scripts/research/lint-agent-allowlists.sh` — EXPECT PASS (the existing stubs already have the conformant `tools:` strings). Commit Phase A.

---

## Phase B: Agent role-specific operating prose

**Purpose**: Extend the existing stubs at `plugin-kiln/agents/{fixture-synthesizer,output-quality-judge}.md` with the role-specific operating prose. After Phase B, the lint scripts from Phase A turn green for both agents.

- [ ] **T006** [B] [Decision 8] Decide whether the role uses includes (CLAUDE.md "Theme B directive syntax"). If YES: author source files at `plugin-kiln/agents/_src/fixture-synthesizer.md` + `plugin-kiln/agents/_src/output-quality-judge.md`, then run `bash plugin-kiln/scripts/agent-includes/build-all.sh` to compile to the canonical `plugin-kiln/agents/<role>.md` paths. If NO: edit `plugin-kiln/agents/<role>.md` directly and skip the source-file step. Recommendation per Decision 8: USE includes for the SendMessage relay coordination prose; both agents share the boilerplate.
- [ ] **T007** [B] [FR-001 / FR-004 / FR-006 / FR-008 / §6 / SC-004] Extend `plugin-kiln/agents/fixture-synthesizer.md` (or `_src/fixture-synthesizer.md`) with role-specific operating prose:
    1. Verbatim diversity prompt per FR-008: `generate fixtures that exercise edge cases: empty inputs, maximum-size inputs, typical inputs, adversarial inputs`. Lint-asserted by T003.
    2. Input-format contract per §6 (composer-injected variables: `skill_id`, `empirical_quality`, `schema_path`, `target_count`, `proposed_corpus_dir`, `prd_slug`, `existing_fixtures_summary`; regenerate-only: `rejection_reason`, `rejected_fixture_summary`, `regeneration_attempt`, `target_fixture_id`).
    3. Output-format contract per FR-004 + §6: deterministic `fixture-NNN.md` zero-padded naming; YAML frontmatter with `axis_focus`, `shape ∈ {empty, minimal, typical, maximum-size, adversarial}`, `summary`. Body matches per-skill schema.
    4. Regenerate-call handling per FR-006: overwrite `target_fixture_id` file; consult `existing_fixtures_summary` to avoid duplication.
    5. SendMessage relay envelope per §6 final stanza (success/error structured JSON).
    6. Tool-allowlist conformance reminder (NFR-005): `Read, Write, SendMessage, TaskUpdate` only — NO Bash, NO Edit, NO Agent.
    7. `<!-- @include _shared/coordination-protocol.md -->` directive per Decision 8 (if T006 chose includes).
    8. Verify: `bash plugin-kiln/scripts/research/lint-synthesizer-prompt.sh` exits 0; `bash plugin-kiln/scripts/research/lint-agent-allowlists.sh` exits 0.
- [ ] **T008** [B] [FR-009 / FR-011 / FR-012 / §1 / §7 / SC-003 / SC-005] Extend `plugin-kiln/agents/output-quality-judge.md` (or `_src/output-quality-judge.md`) with role-specific operating prose:
    1. Verbatim-rubric invariant per FR-011: prompt template MUST contain literal `{{rubric_verbatim}}` interpolation token; NEVER summarize, paraphrase, truncate. Lint-asserted by T002.
    2. Input-format contract per §7 (composer-injected variables: `output_a`, `output_b`, `rubric_verbatim`, `axis_id`, `fixture_id`, `prd_slug`).
    3. Three-way verdict invariant per FR-012: judge emits `A_better | equal | B_better` (NEVER `candidate_better | equal | baseline_better` — judge doesn't know the assignment per FR-015).
    4. Output envelope shape per §7 final stanza: SendMessage relay with `verdict_envelope: {axis_id, blinded_verdict, fixture_id, model_used, rationale}`.
    5. NO retries, NO abstention (`unsure` is forbidden v1 per OQ-1).
    6. Tool-allowlist conformance reminder (NFR-005): `Read, SendMessage, TaskUpdate` only — judge is read-only by construction. NO Write, NO Bash, NO Edit, NO Agent.
    7. `<!-- @include _shared/coordination-protocol.md -->` directive per Decision 8.
    8. Verify: `bash plugin-kiln/scripts/research/lint-judge-prompt.sh` exits 0; `bash plugin-kiln/scripts/research/lint-agent-allowlists.sh` exits 0.
- [ ] **T009** [B] [Decision 8] If T006 chose includes, run the CI gate `bash plugin-kiln/scripts/agent-includes/check-compiled.sh` — must exit 0 (compiled == build(sources)). Commit BOTH the `_src/` source files AND the compiled `plugin-kiln/agents/<role>.md` outputs.

**Checkpoint B**: T006..T009 complete. All three lint scripts from Phase A pass. Commit Phase B.

---

## Phase C: Orchestrator helper + /plan SKILL.md wiring

**Purpose**: Land the orchestrator-side anti-drift plumbing (`evaluate-output-quality.sh`) and the /plan SKILL.md spawn wiring. Single edit point (SKILL.md) — implementer works in one file at a time.

- [ ] **T010** [C] [FR-013 / FR-014 / FR-015 / FR-016 / §1 / §2 / §4 / NFR-008 / Decision 6 / Decision 7] Author `plugin-wheel/scripts/harness/evaluate-output-quality.sh` (~140 LoC) per contracts §4. CLI surface: `--prd-slug --rubric-verbatim --baseline-outputs --candidate-outputs --fixture-list --judge-config`. Implements:
    1. Parse `judge-config.yaml` per §5 schema; loud-fail on malformation per §4 bail-out table.
    2. Resolve pinned model via probe ladder per FR-014; record `model_used`.
    3. Insert identical-input control fixture per FR-016 (deterministic seeded selection per §2 algorithm).
    4. Per fixture: compute position assignment per FR-015 (deterministic `sha256(prd_slug:fixture_id) mod 2`); construct `output_a`, `output_b`; record in `position-mapping.json` per §2.
    5. For each fixture (control + regular): spawn judge via composer recipe (CLAUDE.md "Composer integration recipe") with role-instance vars per §7; capture SendMessage envelope.
    6. Compute `rubric_verbatim_hash` (sha256 cross-platform per `plugin-kiln/scripts/roadmap/promote-source.sh` precedent); assert equal to hash of rubric the judge received (via composer's prompt_prefix); loud-fail on mismatch per §4 bail-out table.
    7. De-anonymize verdict (FR-015 + Decision 7) into `deanonymized_verdict`.
    8. For control fixture: assert `blinded_verdict ∈ {equal}`; on `A_better` / `B_better` HALT BEFORE write per §1 final stanza + §4 bail-out table; write `judge-drift-report.md` with inputs + verdict + verbatim judge prompt.
    9. Write augmented envelope per §1 to `.kiln/research/<prd-slug>/judge-verdicts/fixture-<id>.json` (`jq -c -S` canonical).
    10. Write `position-mapping.json` per §2.
    11. Stdout: `pass` if every non-control fixture's `deanonymized_verdict ∈ {candidate_better, equal}`; `regression` otherwise. Matches axis-enrichment §4 `evaluate-direction.sh` contract for downstream gate consumption.
    `chmod +x`.
- [ ] **T011** [C] [FR-002 / FR-005 / FR-006 / FR-007 / NFR-006a / NFR-006b / §8 / Decision 1 / Decision 2 / Decision 3] Extend `plugin-kiln/skills/plan/SKILL.md` with new "Phase 1.5: research-first plan-time agents" stanza per §8. Inserted between current Phase 1 and the existing "Stop and report" step (which is the §"Outline" step 4). The stanza MUST:
    1. Probe the parsed PRD frontmatter JSON (already loaded in Phase 0 / Phase 1) for `fixture_corpus: synthesized` AND for any `empirical_quality[].metric == output_quality`. Use jq on the already-parsed JSON — NO new subprocess fork on the skip path (NFR-006a). Fallback to single `grep -E` per §8 invariants if frontmatter not yet parsed.
    2. SKIP-PATH: if neither feature declared, return immediately. NO spawn, NO net-new subprocess. Per NFR-006a structural invariant.
    3. SYNTHESIZER PATH (`fixture_corpus: synthesized`):
        a. Pre-check `plugin-<skill-plugin>/skills/<skill>/fixture-schema.md` exists; loud-fail per Edge Cases.
        b. Resolve agent + compose context per CLAUDE.md "Composer integration recipe" with role-instance vars per §6. Spawn `kiln:fixture-synthesizer` with `name: "synth-<prd-slug>"`.
        c. After synthesizer relays success, surface per-fixture confirm-never-silent prompt per FR-005: render each `proposed/fixture-NNN.md` with its 3-line summary header; user replies `accept | reject [reason] | edit | accept-all | abandon`.
        d. On `reject`: re-spawn synthesizer with regenerate vars per §6 + FR-006; bounded by `max_regenerations` (default 3 per fixture, frontmatter-overridable). On exhaustion bail per Edge Cases.
        e. On finalization: move accepted fixtures to either `.kiln/research/<prd-slug>/corpus/` (default) or `plugin-<skill-plugin>/fixtures/<skill>/corpus/` (when `promote_synthesized: true`). Promotion-target collision check per FR-007 + Edge Cases.
        f. Write `.kiln/research/<prd-slug>/synthesis-report.md` per FR-007 logging which path each fixture landed at + regeneration counter per fixture per NFR-009.
    4. JUDGE PATH (`metric: output_quality`):
        a. The judge is NOT spawned by `/plan` directly. /plan's job at this phase is to ensure the orchestrator (`evaluate-output-quality.sh`) has its prerequisites: `judge-config.yaml` resolved (per §5 resolution order), `rubric_verbatim` extracted from frontmatter (validator from T005 already caught missing).
        b. Surface a research-first run-time banner: `Pinned judge model: <model> (source: .kiln/research/judge-config.yaml | plugin-kiln/lib/judge-config.yaml.example)` so the human reviewer sees the resolved config before downstream gate-eval runs.
- [ ] **T012** [C] [NFR-006a / NFR-006b] Audit T011's edits to confirm the skip-path probe re-uses already-parsed JSON when available. Add a comment in the SKILL.md prose explicitly stating "skip-path: structural no-op — single jq lookup on already-parsed JSON OR single grep -E if JSON unavailable; NEVER spawn python3 / jq cold-fork solely for the probe". This is the documented constraint that T015 perf test will enforce.

**Checkpoint C**: T010..T012 complete. Run `bash plugin-wheel/scripts/harness/evaluate-output-quality.sh --help` (or equivalent dry-run probe) — must NOT crash when invoked with valid args against a mock fixture set. Commit Phase C.

---

## Phase D: Test fixtures

**Purpose**: Land all ten test fixtures anchored to SC-001..SC-010 + skip-perf. All tests are mock-spawn — they exercise orchestrator-side determinism, envelope shape, lint-script behaviour, and skip-path performance, NOT live LLM calls.

- [ ] **T013** [P] [D] [SC-007] Author `plugin-kiln/tests/parse-prd-frontmatter-rubric-required/run.sh` + fixtures. Asserts: PRD declaring `empirical_quality: [{metric: output_quality, direction: equal_or_better}]` (no rubric) → exit 2 with `Bail out! output_quality-axis-missing-rubric: <abs-prd-path>`. Negative case: same PRD with non-empty rubric → exit 0 + JSON projection includes the rubric verbatim.
- [ ] **T014** [P] [D] [SC-005 / §1] Author `plugin-kiln/tests/judge-verdict-envelope/run.sh` + fixtures. Mock the judge spawn by writing a fixed SendMessage envelope to a known path; invoke `evaluate-output-quality.sh` with `--judge-spawn-mock <path>` (or equivalent injection mechanism — implementer's choice, document in run.sh); assert the resulting `fixture-<id>.json` matches the canonical §1 shape (sorted keys, `jq -c -S`-stable, all 8 fields present + correct types).
- [ ] **T015** [P] [D] [SC-006 / NFR-006b] Author `plugin-kiln/tests/plan-time-agents-skip-perf/run.sh` + fixtures. Asserts:
    1. `t_baseline` = median wall-clock over 5 runs of `/plan` against a pre-existing PRD declaring NEITHER feature (e.g., `docs/features/2026-04-25-research-first-foundation/PRD.md`) on the new SKILL.md surface.
    2. `t_skip` = median wall-clock over 5 runs of `/plan` against a fresh fixture PRD (under `fixtures/no-features-prd.md`) declaring NEITHER feature on the new SKILL.md surface.
    3. `t_skip - t_baseline ≤ 50 ms`. Use `python3 -c 'import time; print(time.monotonic())'` for monotonic timing per axis-enrichment NFR-AE-006 precedent.
    4. On regression: report the delta + which probe took the longest. NOTE: live `/plan` invocation is hard to script in a test fixture (interactive prompts); implementer extracts the Phase 1.5 probe block into a callable sub-script `plugin-kiln/scripts/research/probe-plan-time-agents.sh` (~10 LoC) that the perf test invokes directly. The sub-script's existence is itself an FR-NFR-006a aid — it makes the probe surface inspectable.
- [ ] **T016** [P] [D] [SC-004 / FR-004 / NFR-002] Author `plugin-kiln/tests/fixture-synthesizer-stable-naming/run.sh` + fixtures. Mock the synthesizer spawn by writing N synthetic fixture files to a known path; invoke the orchestrator's synthesis-finalization step (extracted as a sub-script if needed); assert the filenames are `fixture-001.md` … `fixture-NNN.md` zero-padded. Re-run twice and assert filenames are byte-identical across runs.
- [ ] **T017** [P] [D] [SC-008 / FR-016] Author `plugin-kiln/tests/judge-identical-input-control-fail/run.sh` + fixtures. Mock the judge spawn to return `A_better` on the identical-input control; assert `evaluate-output-quality.sh` exits 2 with `Bail out! judge-drift-detected: blinded_verdict=A_better` and writes `.kiln/research/<test-prd-slug>/judge-drift-report.md` with control inputs + verdict + verbatim judge prompt.
- [ ] **T018** [P] [D] [SC-009 / FR-015 / NFR-008 / §2] Author `plugin-kiln/tests/judge-position-blinding-deterministic/run.sh` + fixtures. Invoke the position-assignment seed function per §4 with fixed `(prd_slug, fixture_id)` pairs; assert the `position-mapping.json` is byte-identical across two runs. Hand-verify one assignment against the documented `sha256(prd_slug + ':' + fixture_id) mod 2` algorithm.
- [ ] **T019** [P] [D] [SC-010 / FR-006] Author `plugin-kiln/tests/synthesis-regeneration-exhausted/run.sh` + fixtures. Mock the synthesizer to always return a "rejectable" fixture; mock the user-review prompt to always reject; assert /plan halts with `Bail out! regeneration-exhausted: fixture-001 rejected 4 times` (default `max_regenerations: 3` + 1 initial = 4 attempts before bail).
- [ ] **T020** [P] [D] [SC-003 / FR-011 / §9.1] Author `plugin-kiln/tests/judge-prompt-lint/run.sh` + fixtures. Asserts the lint script catches:
    1. Missing `{{rubric_verbatim}}` token (mutate a copy of the agent.md, drop the token, run lint, expect exit 2).
    2. Rubric-summarization regex match (mutate to add `summarize the rubric for the judge`, expect exit 2).
    3. Clean agent.md (positive case, expect exit 0).
- [ ] **T021** [P] [D] [FR-014 / §5] Author `plugin-kiln/tests/judge-config-resolution/run.sh` + fixtures. Asserts:
    1. Override at `.kiln/research/judge-config.yaml` wins over example.
    2. Falls back to `plugin-kiln/lib/judge-config.yaml.example` when override absent.
    3. Bails with `Bail out! judge-config-missing` when both absent.
    4. Bails with `Bail out! judge-config-malformed` when override present but unparseable.
- [ ] **T022** [P] [D] [NFR-005 / §9.3] Author `plugin-kiln/tests/agent-allowlist-lint/run.sh` + fixtures. Asserts the lint script catches a synthesizer.md with `tools: Read, Write, Bash, SendMessage, TaskUpdate` (added Bash) → exit 2 with diff in error message. Positive case: clean files → exit 0.

**Checkpoint D**: T013..T022 complete. Every `plugin-kiln/tests/<test>/run.sh` exits 0. Commit Phase D.

---

## Phase E: Audit + smoke + PR

**Purpose**: Hand off to auditor (Task #3 in team task list).

- [ ] **T023** [E] Mark Task #2 in team task list as `completed`. Notify auditor via SendMessage to start Task #3.

---

## Notes for implementer

- **Single edit point**: both themes share `/plan` SKILL.md as their spawn surface — work serially within Phase C to avoid file conflicts.
- **No new wheel workflow** — see plan.md Decision 1. Spawn happens inline in SKILL.md.
- **Composer recipe** is the canonical spawn pattern — see plan.md Decision 3 for the concrete shape.
- **Live agent spawn out-of-scope for tests** — per CLAUDE.md Rule 5, newly-shipped agents not live-spawnable in same session. All tests mock the spawn output. Live-spawn validation is a follow-on item for the next session.
- **Foundation invariants preserved** — six axis-enrichment files + research-runner.sh + 12 foundation siblings remain BYTE-UNTOUCHED. Only `parse-prd-frontmatter.sh` is modified additively (one new validator stanza, FR-010).
- **NFR-006 reconciliation** — `t_skip - t_baseline ≤ 50 ms` per RECONCILED 2026-04-25 directive in spec.md + research.md §baseline. Implementer MUST use a single jq lookup on already-parsed JSON for the probe (sub-millisecond) OR a single `grep -E` (~5 ms). MUST NOT add a fresh python3 / jq cold-fork solely for the probe (would burn 10ms of the 50ms budget on a no-op decision).
