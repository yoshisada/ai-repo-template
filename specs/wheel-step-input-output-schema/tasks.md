# Tasks: Wheel Step Input/Output Schema

**Branch**: `build/wheel-step-input-output-schema-20260425`
**Spec**: [spec.md](./spec.md) | **Plan**: [plan.md](./plan.md) | **Contracts**: [contracts/interfaces.md](./contracts/interfaces.md)
**PRD**: [../../docs/features/2026-04-25-wheel-step-input-output-schema/PRD.md](../../docs/features/2026-04-25-wheel-step-input-output-schema/PRD.md)

## Implementer partition (NON-NEGOTIABLE)

Two implementer tracks (per PRD Pipeline guidance + research-baseline ahead of both):

- **researcher-baseline** — captures pre-PRD `/kiln:kiln-report-issue` baseline (TaskList #2). Owns `specs/wheel-step-input-output-schema/research.md` (baseline TSV + audit-context-from + audit-create-issue + audit-dispatch-bg). Phase 2 is gated on its completion.
- **impl-resolver-hydration** — Theme G2 (grammar) + Theme G3 (hydration in dispatch) + tripwire. Owns `plugin-wheel/lib/resolve_inputs.sh`, edits to `dispatch.sh`, `context.sh`, `preprocess.sh`. Authors 6 unit-test fixtures (`resolve-inputs-grammar/`, `resolve-inputs-allowlist/`, `resolve-inputs-error-shapes/`, `hydration-tripwire/`, `hydration-perf/`, `output-schema-extract-regex/`, `output-schema-extract-jq/`) and 1 kiln-test fixture (`resolve-inputs-missing-step/`).
- **impl-schema-migration** — Theme G1 (workflow-load schema validation) + Theme G4 (atomic `kiln-report-issue.json` migration) + Theme G5 (narrowing doc). Owns `plugin-wheel/lib/workflow.sh` edit, `plugin-wheel/docs/context-from-narrowing.md`, `plugin-wheel/docs/workflow-schema.md` updates, `plugin-kiln/workflows/kiln-report-issue.json` edit. Authors 1 unit-test fixture (`back-compat-no-inputs/`) and 1 kiln-test fixture (`kiln-report-issue-inputs-resolved/`).

**Cross-track dependencies** (tasks flagged `[DEP <track> <task-id>]`):
- `impl-schema-migration` sources `_parse_jsonpath_expr` from `impl-resolver-hydration`'s `resolve_inputs.sh`. **Phase 2.A (impl-resolver-hydration) MUST land its parser BEFORE Phase 2.B (impl-schema-migration) starts.**
- `impl-schema-migration`'s Phase 4 atomic-migration commit (NFR-G-6) requires `impl-resolver-hydration`'s Phase 3 dispatch wiring to be in place. Phase 4 is gated on Phase 3 completing.

**Phase commit boundaries** (for `/implement` incremental commits per Constitution VIII):
- Commit after each phase across all tracks that touch it.

---

## Phase 1 — Setup (shared, all tracks observe)

- [ ] T001 [researcher-baseline] [impl-resolver-hydration] [impl-schema-migration] Read `.specify/memory/constitution.md`, `specs/wheel-step-input-output-schema/spec.md`, `plan.md`, `contracts/interfaces.md` from each track before starting any FR task.
- [ ] T002 [P] Create implementer friction-note stubs at `specs/wheel-step-input-output-schema/agent-notes/{researcher-baseline,impl-resolver-hydration,impl-schema-migration,audit-compliance,retrospective}.md` (one sentence placeholder each; each track fills its own note during/after work per FR-009).
- [ ] T003 [P] Confirm `bash 5.x`, `jq`, `python3` available (`bash --version`, `jq --version`, `python3 --version`). No install task — these are existing wheel runtime deps.

---

## Phase 2 — Pre-implementation research (researcher-baseline) + foundational (impl-resolver-hydration parser)

### Phase 2.0 (researcher-baseline) — Pre-PRD baseline + audit

- [X] T010 [researcher-baseline] Capture baseline run #1 of `/kiln:kiln-report-issue` against `5a4fe69` (PR #165 merge). Record `command_log` from `.wheel/history/success/kiln-report-issue-*.json`. Save to `specs/wheel-step-input-output-schema/research.md` §baseline. [Done — researcher used N=3 most-recent real-user runs in lieu of synthetic runs; rationale documented in research.md §Methodology.]
- [X] T011 [researcher-baseline] Capture baseline runs #2 and #3 (N=3 for stability per Assumption #2). Compute median Bash/Read tool-call count + median wall-clock activation→dispatch-background-sync. Save to research.md §baseline as TSV. [Done — see research.md §baseline aggregates table. Median command_log length = 1, median sub-shell-command count = 3, median dispatch-step wall-clock = 36s.]
- [X] T012 [researcher-baseline] Audit `context_from:` uses across all shipped workflows. Classify each use as "pure ordering" (keep) or "data passing" (migrate). Save to research.md §audit-context-from. [Done — 61 entries surveyed: 5 DATA-PASSING, 5 PROBABLE, 51 PURE-ORDERING.]
- [X] T013 [researcher-baseline] Audit `kiln-report-issue.json::create-issue` instruction text for fetch-elimination opportunities. [Subsumed under T012 — `create-issue` classified as PURE-ORDERING (no in-step fetches); FR-G4-4 stands as written.]
- [X] T014 [researcher-baseline] Audit `kiln-report-issue.json::dispatch-background-sync` instruction text — list every disk fetch + its `inputs:` mapping target. [Subsumed under T012 row #1 — the FR-G4-2 5-entry list (ISSUE_FILE, OBSIDIAN_PATH, CURRENT_COUNTER, THRESHOLD, SHELF_DIR) is complete.]
- [X] T015 [researcher-baseline] Write friction note to `agent-notes/researcher-baseline.md`. SendMessage to specifier (informational) and team-lead that #2 is complete; mark TaskList #2 completed via TaskUpdate.

### Phase 2.A (impl-resolver-hydration) — JSONPath subset parser

- [ ] T020 [impl-resolver-hydration] Create `plugin-wheel/lib/resolve_inputs.sh` skeleton with re-source guard, `CONFIG_KEY_ALLOWLIST` declared per contract §7, function header for `_parse_jsonpath_expr` per contract §1. Body returns "unsupported expression" for now.
- [ ] T021 [impl-resolver-hydration] Implement `_parse_jsonpath_expr` per contract §1 — regex dispatcher with the four documented patterns; sets `_PARSED_KIND`/`_PARSED_ARG1`/`_PARSED_ARG2` globals on success.
- [ ] T022 [impl-resolver-hydration] Author `plugin-wheel/tests/resolve-inputs-grammar/run.sh` — covers all four expression types (positive cases) + 6 "unsupported expression" negatives (extra path segments, missing parens, lowercase steps prefix, bare `$`, double `$$`, empty arg). Invoke `/kiln:kiln-test plugin-wheel resolve-inputs-grammar`; cite verdict report path in friction note.
- [ ] T023 [impl-resolver-hydration] Commit Phase 2.A. SendMessage to impl-schema-migration: parser is committed, Phase 2.B unblocked.

### Phase 2.B (impl-schema-migration) — Workflow-load schema validation

- [ ] T030 [impl-schema-migration] [DEP impl-resolver-hydration T021] Source `resolve_inputs.sh` from `workflow.sh`. Add `workflow_validate_inputs_outputs` per contract §5. Validation rules per FR-G1-4 + contract §5 list (8 rules).
- [ ] T031 [impl-schema-migration] Wire `workflow_validate_inputs_outputs` into `workflow_load` AFTER existing validators (after `workflow_validate_requires_plugins`).
- [ ] T032 [impl-schema-migration] Edit `plugin-wheel/docs/workflow-schema.md` (or create if absent) — document `inputs:` and `output_schema:` per contract §6. Document `context_from:` narrowed semantics per FR-G5-1.
- [ ] T033 [impl-schema-migration] Create `plugin-wheel/docs/context-from-narrowing.md` per FR-G5-1 — short doc recording the data-passing → `inputs:` move and the deferred `after:` rename decision.
- [ ] T034 [impl-schema-migration] Commit Phase 2.B.

---

## Phase 3 — Theme G2/G3 hydration wired into dispatch (impl-resolver-hydration)

- [ ] T040 [impl-resolver-hydration] Implement `extract_output_field` per contract §3 — three extractor types (direct JSON path, regex, jq). Errors match contract §3 documented strings byte-for-byte.
- [ ] T041 [impl-resolver-hydration] Implement `resolve_inputs` per contract §2 — iterates `step.inputs`, dispatches each via `_parse_jsonpath_expr`, handles all four expression types. No-op fast path for empty `inputs`.
- [ ] T042 [impl-resolver-hydration] Wire `resolve_inputs` allowlist gate per contract §2 + NFR-G-7 — `$config()` resolutions check `CONFIG_KEY_ALLOWLIST` BEFORE reading the file. Unknown key → documented allowlist-denial error.
- [ ] T043 [impl-resolver-hydration] Implement `substitute_inputs_into_instruction` per contract §4 — extends `preprocess.sh` python3 substitution pass to also replace `{{VAR}}` patterns. Tripwire scan post-substitution per FR-G3-5.
- [ ] T044 [impl-resolver-hydration] Edit `dispatch.sh::_dispatch_agent_step` (or equivalent) — call `resolve_inputs` BEFORE `context_build`. Pass resolved map as 4th argument to `context_build`. On `resolve_inputs` failure, mark step failed, abort dispatch.
- [ ] T045 [impl-resolver-hydration] Edit `context.sh::context_build` — add 4th param `resolved_map_json`. When non-empty, prepend `## Resolved Inputs` block (FR-G3-2) and SUPPRESS the legacy `## Context from Previous Steps` footer (FR-G1-3). When empty (or absent), preserve today's behavior byte-identically (NFR-G-3).
- [ ] T046 [impl-resolver-hydration] Edit `dispatch.sh` substitution call — after `template_workflow_json`, call `substitute_inputs_into_instruction` with the resolved map. On tripwire failure, mark step failed, abort dispatch.
- [ ] T047 [impl-resolver-hydration] Author `plugin-wheel/tests/resolve-inputs-allowlist/run.sh` — positive case (allowed key resolves), negative case (unknown key rejected with documented error), allowlist-mutation tripwire (NFR-G-2 — deliberately mutate the error string and assert the test fails). Invoke `/kiln:kiln-test plugin-wheel resolve-inputs-allowlist`; cite verdict.
- [ ] T048 [impl-resolver-hydration] Author `plugin-wheel/tests/resolve-inputs-error-shapes/run.sh` — exact-string match for ALL 8 documented error shapes in contract §2. NFR-G-2 mutation tripwire on each. Invoke; cite verdict.
- [ ] T049 [impl-resolver-hydration] Author `plugin-wheel/tests/hydration-tripwire/run.sh` — workflow with `{{VAR}}` placeholder NOT declared in `inputs:`. Assert tripwire fires with documented error text + step id. Invoke; cite verdict.
- [ ] T050 [impl-resolver-hydration] Author `plugin-wheel/tests/hydration-perf/run.sh` — synthetic workflow with 5 inputs (one per resolver type). Capture median wall-clock over N=10 runs via `time`. Assert ≤100ms median (NFR-G-5). Also assert ≤5ms no-op fast path. Invoke; cite verdict.
- [ ] T051 [impl-resolver-hydration] Author `plugin-wheel/tests/output-schema-extract-regex/run.sh` — regex extractor positive cases + negative (no match → error) + multi-match (first wins). Invoke; cite verdict.
- [ ] T052 [impl-resolver-hydration] Author `plugin-wheel/tests/output-schema-extract-jq/run.sh` — jq extractor positive + negative (jq parse error) + missing field. Invoke; cite verdict.
- [ ] T053 [impl-resolver-hydration] Author `plugin-kiln/tests/resolve-inputs-missing-step/` (kiln-test fixture) — workflow with `inputs:` referencing a step that hasn't run. Assert: state file shows step in failed state, no agent dispatch, stderr contains documented error, exit non-zero. Invoke `/kiln:kiln-test plugin-kiln resolve-inputs-missing-step`; cite verdict in friction note.
- [ ] T054 [impl-resolver-hydration] Run all 6 unit fixtures + 1 kiln-test fixture; capture results in `agent-notes/impl-resolver-hydration.md` with verdict report paths. Commit Phase 3.

---

## Phase 4 — Theme G4 atomic migration (impl-schema-migration) [DEP impl-resolver-hydration Phase 3 complete]

- [ ] T060 [impl-schema-migration] [DEP impl-resolver-hydration T054] Edit `plugin-kiln/workflows/kiln-report-issue.json::check-existing-issues` — add `output_schema:` per FR-G4-1. (If audit-context-from says no downstream consumer needs the count, omit the field per research.md §audit guidance.)
- [ ] T061 [impl-schema-migration] Edit `kiln-report-issue.json::create-issue` — add `output_schema: { issue_file: { extract: "regex:^\\.kiln/issues/.*\\.md$" } }` per FR-G4-1.
- [ ] T062 [impl-schema-migration] Edit `kiln-report-issue.json::write-issue-note` — add `output_schema: { issue_file: "$.issue_file", obsidian_path: "$.obsidian_path" }` per FR-G4-1.
- [ ] T063 [impl-schema-migration] Edit `kiln-report-issue.json::dispatch-background-sync` — add `inputs:` block with the 5 entries per FR-G4-2.
- [ ] T064 [impl-schema-migration] Rewrite `dispatch-background-sync.instruction:` per FR-G4-3 — delete the 5 disk-fetch commands; replace inline references with `{{ISSUE_FILE}}`, `{{OBSIDIAN_PATH}}`, `{{CURRENT_COUNTER}}`, `{{THRESHOLD}}`, `{{SHELF_DIR}}` placeholders. Keep the bg sub-agent spawn block. Bump workflow version (3.1.0 → 3.2.0).
- [ ] T065 [impl-schema-migration] Author `plugin-wheel/tests/back-compat-no-inputs/run.sh` (NFR-G-3) — pick an unmigrated workflow (e.g. `shelf-sync.json`), run against post-PRD code, capture state file + agent prompt, diff against pre-PRD snapshot. Diff must be empty modulo timestamps. Invoke; cite verdict.
- [ ] T066 [impl-schema-migration] Author `plugin-kiln/tests/kiln-report-issue-inputs-resolved/` (kiln-test fixture) — activates the migrated workflow, asserts: (a) `## Resolved Inputs` block present in dispatched prompt, (b) all 5 values resolved correctly, (c) no `{{VAR}}` residuals in `command_log`, (d) ≥3 fewer Bash/Read tool calls vs baseline (User Story 1 + User Story 5 covered together). Invoke `/kiln:kiln-test plugin-kiln kiln-report-issue-inputs-resolved`; cite verdict in friction note.
- [ ] T067 [impl-schema-migration] Add CI atomic-migration guard to `.github/workflows/wheel-tests.yml` per plan §3.E — fails if `git log -1 --name-only HEAD` doesn't show BOTH `plugin-wheel/lib/resolve_inputs.sh` AND `plugin-kiln/workflows/kiln-report-issue.json`. (Soft-warning form acceptable for local-dev CI runs that don't represent the merge commit.)
- [ ] T068 [impl-schema-migration] Run `back-compat-no-inputs/` + `kiln-report-issue-inputs-resolved/`; capture results in `agent-notes/impl-schema-migration.md` with verdict report paths. Commit Phase 4 — atomic with Phase 3 per NFR-G-6 (single squash-merge target).

---

## Phase 5 — Audit + live-smoke headline metric (audit-compliance)

- [ ] T080 [audit-compliance] Verify every FR-G1..G4 has ≥1 fixture cited in implementer friction notes per NFR-G-1 + Absolute Must #2. Specifically check: each FR has a fixture file AND the friction note cites a `.kiln/logs/kiln-test-<uuid>.md` PASS verdict. Fixture file existence without a verdict report is a BLOCKER.
- [ ] T081 [audit-compliance] Run a fresh `/kiln:kiln-report-issue` against post-PRD code (NFR-G-4 NON-NEGOTIABLE live smoke). Capture `command_log` from the new `.wheel/history/success/kiln-report-issue-*.json`.
- [ ] T082 [audit-compliance] Compare against baseline from `research.md §baseline`. Assert recalibrated SC-G-1: (a) `dispatch-background-sync.command_log` length = 0 (down from baseline median 1), AND (b) zero `bash`/`jq`/`cat`/`grep` references in the post-PRD dispatched instruction text (down from baseline median 3 disk-fetch sub-commands). Assert SC-G-2: dispatch-step wall-clock ≤39.6s (baseline 36s + 10% tolerance). FAIL the audit if any gate fails.
- [ ] T083 [audit-compliance] `git grep -E '\{\{[A-Z][A-Z0-9_]*\}\}' .wheel/history/success/*.json` — assert zero matches post-PRD (FR-G3-5 invariant).
- [ ] T084 [audit-compliance] `git show <merge-commit-sha> --name-only` (or HEAD on the feature branch pre-merge) — assert BOTH `plugin-wheel/lib/resolve_inputs.sh` AND `plugin-kiln/workflows/kiln-report-issue.json` appear (NFR-G-6 atomic invariant).
- [ ] T085 [audit-compliance] Re-run all 8 unit fixtures + 2 kiln-test fixtures against the merged tree (defense-in-depth). All must show PASS verdicts.
- [ ] T086 [audit-compliance] Write friction note to `agent-notes/audit-compliance.md` with: live-smoke results, baseline comparison table, atomic-commit verification, fixture re-run results. Mark TaskList #5 completed.

---

## Phase 6 — Smoke test + create PR (audit-pr) — TaskList #6

- [ ] T090 [audit-pr] Run a final `/kiln:kiln-report-issue` end-to-end smoke test as the user would. Verify zero permission prompts beyond expected (≥3 fewer than baseline per SC-G-4).
- [ ] T091 [audit-pr] Open PR with title `feat(wheel): add inputs:/output_schema: + atomic kiln-report-issue migration`. Body MUST include the verification checklist with NFR-G-4 live-smoke results inline (the audit step's findings).
- [ ] T092 [audit-pr] Mark TaskList #6 completed.

---

## Phase 7 — Retrospective (retrospective) — TaskList #7

- [ ] T100 [retrospective] Read all friction notes under `agent-notes/`. Identify three classes of finding: (a) prompt/communication issues that confused implementers, (b) skill/workflow gaps in `/kiln:kiln-build-prd` or `/kiln:specify`/`/plan`/`/tasks`, (c) live-smoke discipline observations (NFR-G-4 — did it catch issues, or become a checkbox?).
- [ ] T101 [retrospective] File a GitHub issue with `label:retrospective` containing PI blocks (File/Current/Proposed/Why) per `/kiln:kiln-pi-apply` shape. Reference each finding by friction-note path + line.
- [ ] T102 [retrospective] Mark TaskList #7 completed.

---

## Quick reference — task → owner → file

| Task | Owner | Primary file |
|---|---|---|
| T001..T003 | all | (setup) |
| T010..T015 | researcher-baseline | research.md |
| T020..T023 | impl-resolver-hydration | resolve_inputs.sh (parser) |
| T030..T034 | impl-schema-migration | workflow.sh, workflow-schema.md |
| T040..T054 | impl-resolver-hydration | resolve_inputs.sh (resolver), dispatch.sh, context.sh, preprocess.sh |
| T060..T068 | impl-schema-migration | kiln-report-issue.json, CI guard |
| T080..T086 | audit-compliance | (verification only — no source edits) |
| T090..T092 | audit-pr | (PR creation only) |
| T100..T102 | retrospective | retrospective issue |
