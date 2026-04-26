# Tasks: Research-First Completion — schema + distill + build-prd routing + classifier + E2E gate

**Input**: Design documents from `/specs/research-first-completion/`
**Prerequisites**: spec.md (✅), plan.md (✅), contracts/interfaces.md (✅). Baseline checkpoint SKIPPED per spec.md §"Baseline rationale" (byte-identity NFRs, no numeric perf budget).

**Tests**: Tests are REQUIRED — anchored to SC-001..SC-011. All tests mock the live agent spawn (per CLAUDE.md Rule 5 — newly-shipped agents are not live-spawnable in the same session); orchestrator-side determinism + propagation + validator + classifier behaviour are the live test surfaces. The E2E fixture (Phase D) mocks the LLM-spawning steps via shell scripts; live `claude` CLI invocation is forbidden (NFR-008).

**Organization**: Single implementer (`implementer`) executes phases A → B → C → D sequentially. Phase A is foundation for B, C, D; phases B + C share file-edit points (SKILL.md files) so MUST run sequentially within phase to avoid file conflicts; phase D depends on A+B+C. Phase E is friction notes + final commit + smoke-pass per the team-lead's launch directive (PI-2 from issue #181). Single-implementer rationale is in `agent-notes/specifier.md`.

## Format

`[T###] [P?] [Phase] [Anchor] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Phase]**: A | B | C | D | E
- **[Anchor]**: FR-* / NFR-* / SC-* / Decision-N anchor for traceability
- Include exact file paths in descriptions

---

## Phase A: Schema extensions (foundation)

**Purpose**: Land the shared validation helper, extend the four validators (item / issue / feedback / PRD), extend `parse-prd-frontmatter.sh` with three more field projections. After Phase A, every artifact-write surface validates the research block correctly.

- [X] **T001** [A] [FR-001 / FR-002 / FR-003 / Decision 3 / §2] Author `plugin-kiln/scripts/research/validate-research-block.sh` (~120 LoC) per contracts §2. CLI: `validate-research-block.sh <frontmatter-json>` accepts a JSON string (NOT a path). Stdout: `{"ok": bool, "errors": [...], "warnings": [...]}` byte-stable. Exit 0 always (matches `validate-item-frontmatter.sh` precedent). Implements all 10 validation rules from §2 (metric/direction/priority enums, rubric-required-when-output_quality, fixture_corpus_path repo-relative, unknown-key warn-but-pass, etc.). `chmod +x`. **DONE**: shipped at the contract path; sibling `parse-research-block.sh` ships alongside (necessary because parse-item-frontmatter.sh's awk parser cannot handle nested-flow YAML — see implementer.md friction note).

- [X] **T002** [A] [FR-001 / NFR-001 / §2 / SC-009] Extend `plugin-kiln/scripts/roadmap/validate-item-frontmatter.sh` to call the shared helper from T001 after the existing item-schema validation. Pass through any `errors[]` from the helper into the existing `errors[]` output; merge `warnings[]` similarly (or emit them to stderr if the existing validator doesn't surface warnings). The existing JSON output shape `{"ok": bool, "errors": [...]}` is preserved for backward compatibility; warnings are additive. Verify: existing `plugin-kiln/tests/back-compat-no-requires/` and similar item-validator fixtures continue to pass (NFR-001 backward compat). **DONE**: validator wired through new parse-research-block.sh extractor → shared helper. Warnings emit to stderr; errors merge into existing errors[]; back-compat fixtures (back-compat-no-requires / distill-gate-grandfathered-prd / distill-gate-accepts-promoted) all green.

- [X] **T003** [A] [FR-002 / Decision 3 / §2] Discover whether `.kiln/issues/*.md` and `.kiln/feedback/*.md` have existing write-time validators. Search via `find plugin-kiln/scripts -name "*validate*" -o -name "*frontmatter*" 2>&1`. If validators exist: extend each to call the shared helper from T001 (same pattern as T002). If validators do NOT exist: create ONE new validator at `plugin-kiln/scripts/issues-feedback/validate-frontmatter.sh` that handles both surfaces, calls the shared helper, and emits the same JSON shape. Wire the new validator into `/kiln:kiln-report-issue` and `/kiln:kiln-feedback` SKILL.md files at write-time. If creating brand-new validators is judged out-of-scope (e.g., the existing skills don't have a write-time hook surface), document the gap in `specs/research-first-completion/blockers.md` AND ship the shared helper anyway (used by item + PRD validators in this PR; issue + feedback hooks deferred to follow-on). **DONE**: outcome (b) — discovery confirmed no pre-existing issue/feedback validators. Created `plugin-kiln/scripts/issues-feedback/validate-frontmatter.sh` (thin wrapper around parse-research-block.sh + validate-research-block.sh). Skill-level write-time wiring documented in blockers.md as deferred (skills are SKILL.md prose-driven, not script-pipelined writes — direct invocation is the live integration path for v1).

- [X] **T004** [A] [FR-004 / NFR-001 / §3 / Decision 6] Extend `plugin-wheel/scripts/harness/parse-prd-frontmatter.sh` with three additive field projections per contracts §3: `needs_research`, `fixture_corpus`, `fixture_corpus_path`, `promote_synthesized`. Existing `blast_radius`, `empirical_quality[]`, `excluded_fixtures[]` projections are UNCHANGED in shape and exit codes. Sort all projection keys ASC alphabetically (`json.dumps(..., sort_keys=True)` — already in place). Loud-fail per NFR-007 on malformed values (`unknown fixture_corpus`, `fixture-corpus-path-must-be-relative`, `needs_research must be true|false`, etc.). **DONE**: four new projections added (needs_research / fixture_corpus / fixture_corpus_path / promote_synthesized); loud-fail on malformed values; back-compat verified via parse-prd-frontmatter-rubric-required test (5/5 still pass).

- [X] **T005** [A] [FR-004 / Decision 6] Wire the PRD frontmatter validation into the existing PRD-load surface. The implementer chooses one of:
    (a) Extend an existing PRD-load helper (e.g., wherever `prd-derived-from-frontmatter` validation currently fires).
    (b) Add a thin wrapper `plugin-kiln/scripts/research/validate-prd-frontmatter.sh` that calls `parse-prd-frontmatter.sh` then T001's shared helper.
    Document the choice in plan.md Decision 6 follow-up notes and in this task's commit message. **DONE**: outcome (b) — added thin wrapper at `plugin-kiln/scripts/research/validate-prd-frontmatter.sh`; calls parse-prd-frontmatter.sh → shared helper. Same JSON shape as the item + issue/feedback validators. Distill / build-prd may invoke this wrapper at PRD-load time when validation is desired (Phase B + C reference paths).

**Checkpoint A**: T001..T005 complete. Run the existing test fixtures (`plugin-kiln/tests/back-compat-no-requires/`, `plugin-kiln/tests/distill-gate-grandfathered-prd/`, etc.) — all MUST still pass (NFR-001 backward compat invariant). Run `bash plugin-kiln/scripts/research/validate-research-block.sh '{"needs_research": "yes"}'` — EXPECT errors `[needs_research must be true|false]`. Run with `'{"empirical_quality": [{"metric": "tokens", "direction": "lower"}]}'` — EXPECT ok=true. Commit Phase A.

---

## Phase B: Distill propagation + build-prd routing

**Purpose**: Land the FR-005..FR-008 distill propagation logic and the FR-009..FR-012 build-prd Phase 2.5 stanza. Both edit SKILL.md files; sequential within phase to avoid edit conflicts.

- [X] **T006** [B] [FR-005 / FR-006 / FR-007 / FR-008 / NFR-003 / NFR-005 / Decision 5 / §5 / §6] Extend `plugin-kiln/skills/kiln-distill/SKILL.md` with the propagation step run BEFORE the existing PRD-emission step. The step:
    1. Loads frontmatter JSON projections for every selected source (using the appropriate parser per artifact type — `parse-item-frontmatter.sh` for items, `parse-prd-frontmatter.sh` for PRDs, the new sibling parser from T003 if created for issues + feedback).
    2. Detects conflicts via the §5 conflict-detection jq expression. If conflicts exist, surface the §6 prompt and resolve via stdin input. On `abandon` / EOF, exit 2 without writing the PRD.
    3. Computes the union-merged `empirical_quality[]` via the §5 canonical jq expression (sorted ASC by metric, ties on direction; priority promotion `primary > secondary`).
    4. Propagates scalar keys (`fixture_corpus`, `fixture_corpus_path`, `promote_synthesized`) verbatim per FR-007. Detects scalar conflicts and surfaces §6 prompt similarly.
    5. Propagates `excluded_fixtures[]` via union-merge on `path`; detects duplicate-path-with-different-reason conflicts and surfaces §6 prompt similarly.
    6. If ANY source declares `needs_research: true`, sets the propagated `needs_research: true` AND emits the research-block keys in the PRD frontmatter per the §1 authoritative key order (FR-004).
    7. If NO source declares `needs_research: true`, OMITS the research-block keys entirely — PRD frontmatter is byte-identical to pre-PR (NFR-005 / FR-008).

- [X] **T007** [B] [FR-009 / FR-010 / FR-011 / FR-012 / NFR-002 / Decision 2 / Decision 4 / Decision 7 / §7] Extend `plugin-kiln/skills/kiln-build-prd/SKILL.md` with the new "Phase 2.5: research-first variant" stanza inserted between the existing `/tasks` step and the existing `/implement` step. **DONE**: shipped as Step 2.5 in build-prd SKILL.md (between Step 2 "Create Team and Tasks" and Step 3 "Spawn Teammates" — that team-orchestrated structure is the moral equivalent of "between /tasks and /implement"). Skip-path is structural no-op (single jq lookup, no stdout); variant path orchestrates baseline → worktree-implement → measure → gate inline; gate-pass routes to existing audit + PR; gate-fail halts before audit/PR with verbatim per-axis report and `Bail out! research-first-gate-failed:` banner. The stanza:
    1. Probes the projected PRD frontmatter JSON for `needs_research: true` via single jq lookup (already-parsed JSON; NO new subprocess fork on skip path per NFR-002).
    2. SKIP-PATH (NFR-002 byte-identity, Decision 7): if `needs_research: true` is absent or false, return immediately. NO stdout, NO log line, NO observable side-effect. Add a comment in SKILL.md prose: "skip-path: structural no-op — single jq lookup on already-parsed JSON; NEVER emit stdout on skip path".
    3. VARIANT PATH (`needs_research: true`):
        a. **establish-baseline** — invoke `plugin-wheel/scripts/harness/research-runner.sh` against the declared corpus (`fixture_corpus: declared|promoted`) OR the synthesizer's accepted output (`fixture_corpus: synthesized` — produced by plan-time-agents PR's synthesizer). Capture metrics to `.kiln/research/<prd-slug>/baseline-metrics.json`.
        b. **implement-in-worktree** — `git worktree add <tempdir> <branch>` (Decision 4). Run `/implement` in the worktree. Record path for cleanup. Loud-fail with `Bail out! research-first-worktree-failed: <error>` if `git worktree add` fails (NO silent fallback per NFR-007).
        c. **measure-candidate** — invoke `research-runner.sh` against the candidate plugin-dir (from worktree) against the SAME corpus. Capture metrics to `.kiln/research/<prd-slug>/candidate-metrics.json`.
        d. **gate** — invoke `evaluate-direction.sh` for mechanical axes; invoke `evaluate-output-quality.sh` for `output_quality` axis. Capture per-axis verdicts to `.kiln/research/<prd-slug>/per-axis-verdicts.json`.
        e. **gate-pass branch (FR-012)** — every axis returns `pass`. Continue to `/audit` + PR creation. Auditor receives extra inputs: path to `per-axis-verdicts.json` AND path to research report (`.kiln/logs/research-<uuid>.md`). Auditor's PR body MUST insert the `## Research Results` heading + per-axis pass-status table.
        f. **gate-fail branch (FR-011)** — ANY axis returns `regression`. HALT BEFORE invoking `/audit` or PR-creation. Surface the verbatim per-axis report from `per-axis-verdicts.json` to stdout. Emit `Bail out! research-first-gate-failed: <prd-slug>` to stderr; exit 2.
        g. **worktree cleanup** — `git worktree remove --force <tempdir>` runs in a `trap` block to survive interruptions, on BOTH gate-pass and gate-fail paths.
    4. The SKILL.md prose MUST explicitly forbid spawning the auditor or PR-creator agents on the gate-fail path (FR-011 reviewer-visible invariant).

**Checkpoint B**: T006..T007 complete. Manual smoke check: pick a no-research-block PRD already in `docs/features/`, regenerate via distill, diff the new frontmatter against `main` — EXPECT zero diff (NFR-005 byte-identity). Pick a fictional research-needing PRD fixture, run the build-prd skip-path probe — EXPECT no stdout. Commit Phase B.

---

## Phase C: Classifier inference + coached-capture interview

**Purpose**: Land the FR-013/FR-014 classifier extension and the FR-015 coached-capture interview hooks across three capture skills. Three SKILL.md edits; sequential within phase.

- [ ] **T008** [C] [FR-013 / FR-014 / FR-016 / Decision 8 / §4] Extend `plugin-kiln/scripts/roadmap/classify-description.sh` with the comparative-improvement signal-word detector + axis-inference table per contracts §4. The existing JSON output gains an OPTIONAL `research_inference` key. When NO signal matches, the key is OMITTED entirely (NOT `null`, NOT `{}` — false-negative recovery is structural). Implements:
    1. Case-insensitive whole-word matching for the FR-013 signal word list (extended with FR-014 axis-only signals: `latency`, `tokens`, `cost`, `expensive`, `smaller`, `concise`, `verbose`, `accurate`, `wrong`, `clearer`, `better-structured`, `more actionable`).
    2. Multi-signal handling: union-merge proposed_axes by `metric`; collect all matched signals into `matched_signals[]`.
    3. Default `priority: primary` for every inferred axis.
    4. For axes including `metric: output_quality`, the rationale string includes the verbatim FR-016 warning on a separate line.
    5. Existing `surface`/`kind`/`confidence`/`alternatives` JSON keys are UNCHANGED. New `research_inference` key is appended (jq-emit ordering).

- [ ] **T009** [C] [FR-016 / SC-011 / §10] Author `plugin-kiln/scripts/research/lint-classifier-output-quality-warning.sh` (~30 LoC) per contracts §10. Asserts the verbatim FR-016 warning appears in classifier output JSON when `output_quality` is in proposed axes. Exit 0 PASS, 2 FAIL with `Bail out! lint-classifier-output-quality-warning: missing verbatim warning`. `chmod +x`.

- [ ] **T010** [C] [FR-015 / NFR-006 / Decision 9 / §8] Extend `plugin-kiln/skills/kiln-roadmap/SKILL.md` with ONE new question stanza in the coached-capture interview. The stanza is conditional on `research_inference != null` in the classifier output JSON; absent → silently skipped. The stanza renders the FR-015 question per the §5.0 template (Q line, Proposed line, Why line citing matched signal verbatim, accept/tweak/reject/skip/accept-all menu). The §5.0a response parser is consumed unchanged from `coach-driven-capture-ergonomics`. On `accept`: write proposed research-block keys verbatim into the item frontmatter. On `reject`/`skip`: write NO research-block keys (NFR-006 structural absence). For `output_quality` axes, the Why line includes the FR-016 verbatim warning on a second line.

- [ ] **T011** [C] [FR-015 / NFR-006 / Decision 9 / §8] Extend `plugin-kiln/skills/kiln-report-issue/SKILL.md` with the SAME question stanza as T010, adapted for the issue capture surface. The stanza follows the same conditional-rendering, accept/tweak/reject/skip/accept-all behavior, and FR-016 warning rule. Note: `/kiln:kiln-report-issue` has a "lean foreground path" per CLAUDE.md (4 steps); the new question is inserted as a fifth coached-capture step BEFORE the dispatch-background-sync step, conditional on research_inference being present.

- [ ] **T012** [C] [FR-015 / NFR-006 / Decision 9 / §8] Extend `plugin-kiln/skills/kiln-feedback/SKILL.md` with the SAME question stanza as T010/T011, adapted for the feedback capture surface. CLAUDE.md notes feedback "writes the local file and exits" with no wheel workflow; the question is inserted as a coached-capture step before the file-write.

**Checkpoint C**: T008..T012 complete. Run the lint script from T009 against synthetic classifier output containing `output_quality` without the warning — EXPECT FAIL. Against output with the warning — EXPECT PASS. Manual smoke: invoke `classify-description.sh "make claude-md-audit cheaper"` — EXPECT JSON with `research_inference.proposed_axes` containing both `cost` and `tokens` axes. Commit Phase C.

---

## Phase D: Test fixtures + E2E

**Purpose**: Land all 11 test fixtures anchored to SC-001..SC-011 + the E2E fixture (load-bearing for SC-005 and phase-complete declaration). All tests mock LLM-spawning steps; orchestrator-side determinism is the live test surface.

- [ ] **T013** [P] [D] [SC-001 / FR-013 / FR-014] Author `plugin-kiln/tests/classifier-research-inference/run.sh` + fixtures. Asserts: descriptions containing `cheaper` produce `research_inference` JSON with both `cost` and `tokens` axes; `faster` produces `time` axis; absence of signal words produces NO `research_inference` key.

- [ ] **T014** [P] [D] [SC-002 / FR-005 / FR-007 / §5] Author `plugin-kiln/tests/distill-research-block-propagation/run.sh` + fixtures. Mock the distill step by invoking the §5 jq expression directly (or a thin wrapper script) against a fixture set of source frontmatter JSON projections; assert the resulting PRD frontmatter contains the union-merged `empirical_quality[]` (sorted ASC by metric) AND the verbatim scalar keys (`fixture_corpus`, etc.).

- [ ] **T015** [P] [D] [SC-003 / FR-009 / FR-010] Author `plugin-kiln/tests/build-prd-research-routing/run.sh` + fixtures. Invoke the build-prd Phase 2.5 stanza (extracted as a callable sub-script if needed) against a PRD fixture declaring `needs_research: true`; assert stdout contains the literal token `research-first variant invoked` (or equivalent verbatim banner from T007's SKILL.md edits).

- [ ] **T016** [P] [D] [SC-004 / FR-009 / NFR-002] Author `plugin-kiln/tests/build-prd-standard-routing-bytecompat/run.sh` + fixtures. Invoke the build-prd Phase 2.5 stanza against a no-research-block PRD fixture (e.g., a copy of `docs/features/2026-04-25-research-first-foundation/PRD.md` with research keys stripped); assert stdout is EMPTY (NFR-002 byte-identity, Decision 7 — no log line on skip path) AND the stanza returns immediately.

- [ ] **T017** [D] [SC-005 / FR-017 / FR-018 / FR-019 / NFR-008 / Decision 10 / §9] Author `plugin-kiln/tests/research-first-e2e/run.sh` + fixtures. **LOAD-BEARING for phase-complete declaration.** The fixture:
    1. Accepts `--scenario=happy` and `--scenario=regression` flags. Default invocation runs BOTH sequentially with temp-dir reset between them.
    2. Scaffolds a `mktemp -d` test repo with a mocked `kiln-init` (copies `.kiln/`, `plugin-kiln/scripts/`, `plugin-wheel/scripts/` subset).
    3. Creates a roadmap item declaring `needs_research: true` + `empirical_quality: [{metric: tokens, direction: lower}]` + `fixture_corpus: declared` + `fixture_corpus_path: fixtures/corpus/`.
    4. Provides two fixture files at `fixtures/corpus/`.
    5. Runs distill (direct script invocation OR mocked SKILL.md execution); asserts PRD frontmatter inherits the research block.
    6. Runs build-prd (similarly); the variant pipeline runs against mocked baseline + candidate outputs.
    7. **Happy path**: candidate outputs match-or-improve baseline; gate returns pass. Asserts stdout contains `research-first variant invoked`, `gate pass`, and `PR created (mocked)`. Asserts `.kiln/logs/research-<uuid>.md` exists.
    8. **Regression path**: candidate outputs deliberately worse on `metric: tokens` (e.g., 10x larger). Gate returns regression. Asserts stdout contains `research-first variant invoked` AND `gate fail` AND does NOT contain `PR created`. Pipeline halted before audit + PR.
    9. Both sub-paths must pass for the fixture to emit `PASS` on its last line and exit 0. Self-contained per NFR-008 — no real `claude` CLI, no real GitHub API.

- [ ] **T018** [P] [D] [SC-006 / FR-006 / NFR-004 / §6] Author `plugin-kiln/tests/distill-axis-conflict-prompt/run.sh` + fixtures. Provide two fixture items declaring `metric: tokens` with different directions (one `lower`, one `equal_or_better`). Run the distill propagation logic; mock stdin to provide `abandon` as the user's response. Assert distill exits 2 WITHOUT writing the PRD AND stdout contains both source paths AND both `direction` values per the §6 verbatim shape.

- [ ] **T019** [P] [D] [SC-007 / NFR-003 / §5] Author `plugin-kiln/tests/distill-research-block-determinism/run.sh` + fixtures. Run the distill propagation step twice on the same conflict-free fixture backlog; assert `cmp` of the two output PRD frontmatters returns 0 (byte-identity).

- [ ] **T020** [P] [D] [SC-008 / FR-015 / NFR-006] Author `plugin-kiln/tests/classifier-research-rejection-recovery/run.sh` + fixtures. Mock the coached-capture interview by invoking the question stanza with a `reject` response; assert the resulting written artifact has NO research-block keys at all (not `needs_research: false`, not empty `empirical_quality: []`). Structural-absence verified by `grep -F` returning zero matches for `needs_research:`, `empirical_quality:`, etc.

- [ ] **T021** [P] [D] [SC-009 / FR-001 / FR-003 / §2] Author `plugin-kiln/tests/research-block-schema-validation/run.sh` + fixtures. Asserts:
    1. Clean item with all six research-block fields → validator ok.
    2. `metric: foo` → validator NOT ok with error `unknown metric: foo`.
    3. Absolute `fixture_corpus_path: /absolute/path` → validator NOT ok with error containing `fixture-corpus-path-must-be-relative`.
    4. Unknown research-block key (`needs_review: true`) → validator ok (warn-but-pass) with warnings array containing `unknown research-block field`.
    5. `metric: output_quality` without `rubric:` → validator NOT ok with error `output_quality-axis-missing-rubric`.

- [ ] **T022** [P] [D] [SC-010 / FR-014] Author `plugin-kiln/tests/classifier-axis-inference-mapping/run.sh` + fixtures. For each row in the FR-014 axis-inference table, provide a fixture description containing the matching signal word and assert the classifier's `proposed_axes[]` JSON exactly matches the expected axes (including `metric`, `direction`, default `priority: primary`).

- [ ] **T023** [P] [D] [SC-011 / FR-016] Author `plugin-kiln/tests/classifier-output-quality-warning/run.sh` + fixtures. Provide a description containing `clearer`; assert classifier output's `research_inference.rationale` contains the verbatim FR-016 warning string. Run the lint script from T009 against the same JSON; assert exit 0. Mutate the rationale to drop the warning; assert the lint script exits 2.

**Checkpoint D**: T013..T023 complete. Every `plugin-kiln/tests/<test>/run.sh` exits 0. CRITICAL: T017 (`research-first-e2e`) must pass BOTH happy and regression sub-paths. Commit Phase D.

---

## Phase E: Friction notes + final commit + smoke pass

**Purpose**: Per team-lead's launch directive (PI-2 from issue #181) — write friction notes, commit final state, smoke-pass at least one E2E fixture.

- [ ] **T024** [E] [FR-009-PRD] Write `specs/research-first-completion/agent-notes/implementer.md` with: friction encountered during the four phases, decisions deviated from plan.md (with rationale), gaps documented in blockers.md (if any), handoff notes for the auditor.

- [ ] **T025** [E] Run `bash plugin-kiln/tests/research-first-e2e/run.sh` standalone (per FR-019 PASS-cite fallback). Assert exit 0 + `PASS` on last line. Capture stdout to `specs/research-first-completion/agent-notes/e2e-smoke-output.txt` for auditor evidence.

- [ ] **T026** [E] Mark Task #2 in team task list as `completed`. Notify auditor via SendMessage to start Task #3.

---

## Notes for implementer

- **Single edit point per phase**: schema validators (Phase A), SKILL.md files (Phases B + C), test fixtures (Phase D). Work serially within phase to avoid file conflicts.
- **No new wheel workflow** — see plan.md Decision 2. Build-prd routing branches inline within the existing skill.
- **Composer recipe** is the canonical spawn pattern when any agent IS spawned. This PR does NOT spawn new agents (the variant pipeline reuses existing `/implement` agent flow); but if any decision changes that, consult plan.md Decision 3 of plan-time-agents PR for the recipe.
- **Foundation invariants preserved** — listed in plan.md §"Foundation invariants preserved" (NFR-009). Verify with `git diff` post-implementation that none of the listed files have non-trivial changes.
- **Skip-path byte-identity** (NFR-002) — pick a no-research-block PRD already in `docs/features/`, regenerate distill output, diff against `main`. EXPECT zero diff. This is the smoke-test for NFR-005.
- **Live agent spawn out-of-scope for tests** — per CLAUDE.md Rule 5, newly-shipped agents not live-spawnable in same session. All E2E mocks the LLM steps. Live-spawn validation is a follow-on item.
- **R-004 schema-drift mitigation** — Decision 3 commits to the shared validation helper approach. If during T003 the implementer discovers the issues + feedback validators must be brand-new, document in blockers.md and proceed; the shared helper still covers item + PRD validators in this PR.
- **R-005 missing fixture_corpus warning** — T001's helper rule #10 emits the warning when `needs_research: true` but `fixture_corpus:` absent. Ensure T002's wiring surfaces this warning to the user (stderr output is acceptable).
- **PI-2 from issue #181** — at least one E2E fixture must smoke-pass before final commit (T025). The standalone `bash plugin-kiln/tests/research-first-e2e/run.sh` is the canonical evidence path.
