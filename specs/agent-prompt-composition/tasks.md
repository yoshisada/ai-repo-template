# Tasks: Agent Prompt Composition

**Branch**: `build/agent-prompt-composition-20260425`
**Spec**: [spec.md](./spec.md) | **Plan**: [plan.md](./plan.md) | **Contracts**: [contracts/interfaces.md](./contracts/interfaces.md) | **PRD**: [../../docs/features/2026-04-25-agent-prompt-composition/PRD.md](../../docs/features/2026-04-25-agent-prompt-composition/PRD.md)

## Implementer partition (NON-NEGOTIABLE)

Two implementer tracks. Each one reads its filtered slice below:

- **impl-include-preprocessor** — Theme B (FR-B-1..B-8). Owns include resolver + shared module + 2–3 agent refactors + CI gate.
- **impl-runtime-composer** — Theme A (FR-A-1..A-12). Owns composer + validator + task-shape stanzas + 3 research-first agents + plugin manifest extension + CLAUDE.md doc updates.

**File ownership**: per spec.md "Theme Partition" table. NO file is owned by both tracks (NFR-8). Both tracks read `contracts/interfaces.md` as the single source of truth for cross-track interfaces.

**Cross-track dependencies**:
- Theme B's `_shared/coordination-protocol.md` (FR-B-5, T-B-04) is READ by Theme A's composer (FR-A-2). Theme A treats this as a fixed input — Theme B owns authorship; Theme A reads via path. NO write conflict.
- Theme A's CLAUDE.md update (FR-A-12, T-A-15) references Theme B's directive syntax. Both tracks ship in same PR — no temporal dependency.

**Phase commit boundaries** (for `/implement` incremental commits per Constitution VIII):
- Phase boundaries are marked `## Phase N` below. Commit after each phase across all tracks that touch it.

---

## Phase 1 — Setup (shared, both tracks observe)

- [X] **T001** [P] Read `.specify/memory/constitution.md`, `specs/agent-prompt-composition/spec.md`, `specs/agent-prompt-composition/plan.md`, `specs/agent-prompt-composition/contracts/interfaces.md` from each implementer track before starting any FR task. [both]
- [X] **T002** [P] Create implementer friction-note stubs at `specs/agent-prompt-composition/agent-notes/{impl-include-preprocessor,impl-runtime-composer}.md` (one sentence placeholder each; each track fills its own note during/after work per pipeline-contract FR-009). [each track owns its own stub]
- [X] **T003** [P] Confirm `bash 5.x`, `jq`, `awk`, `sed` available (smoke: `bash --version`, `jq --version`, `awk --version`). No install task — these are existing dependencies. [both]

---

## Phase 2 — Theme B foundations (impl-include-preprocessor)

### Phase 2.B — Resolver + shared module (User Story 1, P1)

- [X] **T-B-01** [impl-include-preprocessor] Create `plugin-kiln/scripts/agent-includes/` directory.
- [X] **T-B-02** [impl-include-preprocessor] Author `plugin-kiln/scripts/agent-includes/resolve.sh` per contracts §1 — directive grammar regex, fenced-code-block state machine, single-pass include expansion, error exits 1 with stderr diagnostic. ~80 lines target.
- [X] **T-B-03** [impl-include-preprocessor] Create `plugin-kiln/agents/_shared/` directory.
- [X] **T-B-04** [impl-include-preprocessor] Author `plugin-kiln/agents/_shared/coordination-protocol.md` (FR-B-5) — the SendMessage-relay-results boilerplate currently duplicated across team-mode agents. Pure markdown body, no frontmatter. Body content sourced from one of the existing agents (e.g., `qa-engineer.md` coordination footer) and de-duplicated.
- [X] **T-B-05** [impl-include-preprocessor] Create `plugin-kiln/tests/agent-includes-resolve/` directory + `run.sh` fixture covering: (a) zero-directive file → byte-identical output (I-B1), (b) one directive on its own line → expansion correct, (c) directive-shaped text inside fenced code block → not expanded (R-2), (d) missing target → exit 1, (e) recursive include → exit 1, (f) re-invocation → byte-identical (I-B2, SC-7). All assertions exit 0/1; fixture exits 0 only if all PASS.

### Phase 2.B-cont — CI gate + build script

- [ ] **T-B-06** [impl-include-preprocessor] Author `plugin-kiln/scripts/agent-includes/build-all.sh` — walks `plugin-kiln/agents/_src/*.md`, invokes `resolve.sh` on each, writes compiled output to `plugin-kiln/agents/<role>.md`. Idempotent. Exit non-zero if resolver fails on any file.
- [ ] **T-B-07** [impl-include-preprocessor] Author `plugin-kiln/scripts/agent-includes/check-compiled.sh` (FR-B-7) — runs `build-all.sh` to a tempdir, diffs against committed `plugin-kiln/agents/*.md`, exits non-zero if any drift. Stderr names the drifted file.
- [ ] **T-B-08** [impl-include-preprocessor] Create `plugin-kiln/tests/agent-includes-ci-gate/run.sh` (SC-2) — fixture mutates a source file in `_src/` without re-running build, asserts `check-compiled.sh` exits non-zero with the file name in stderr. Then runs `build-all.sh` and asserts re-run exits 0. Cleans up after itself.

---

## Phase 3 — Theme B agent refactors (impl-include-preprocessor)

### Phase 3.B — Refactor 2–3 existing agents (User Story 1, FR-B-6, SC-1)

- [ ] **T-B-09** [impl-include-preprocessor] Create `plugin-kiln/agents/_src/qa-engineer.md` — copy current `plugin-kiln/agents/qa-engineer.md`, replace inline coordination prose with `<!-- @include _shared/coordination-protocol.md -->` directive on a line by itself.
- [ ] **T-B-10** [impl-include-preprocessor] Run `build-all.sh`. Compiled `plugin-kiln/agents/qa-engineer.md` MUST contain the expanded coordination prose at the directive site. Compare against pre-refactor file: byte-identical except for canonical whitespace around the expansion (no behavioral regression).
- [ ] **T-B-11** [impl-include-preprocessor] Repeat T-B-09/T-B-10 for `plugin-kiln/agents/prd-auditor.md`.
- [ ] **T-B-12** [impl-include-preprocessor] Repeat T-B-09/T-B-10 for `plugin-kiln/agents/debugger.md`. (Decision in plan.md: 3 agents in v1. If during refactor it becomes apparent that one of these has fundamentally different coordination prose, drop it from v1 and document in friction-note — minimum 2 required for FR-B-6.)
- [ ] **T-B-13** [impl-include-preprocessor] Run the SC-1 fixture (`agent-includes-resolve/run.sh`) end-to-end. PASS required.

---

## Phase 4 — Theme A foundations (impl-runtime-composer) — RUNS IN PARALLEL WITH PHASES 2/3

### Phase 4.A — Closed vocabularies + stanza files (FR-A-4, FR-A-5, FR-A-8)

- [X] **T-A-01** [impl-runtime-composer] Create `plugin-kiln/lib/task-shapes/` directory.
- [X] **T-A-02** [impl-runtime-composer] Author `plugin-kiln/lib/task-shapes/_index.json` per contracts §7 — version=1, shapes=8.
- [X] **T-A-03** [impl-runtime-composer] Author 8 stanza files (`skill.md`, `frontend.md`, `backend.md`, `cli.md`, `infra.md`, `docs.md`, `data.md`, `agent.md`) per contracts §5 — pure markdown body, 5–15 lines, no frontmatter.
- [X] **T-A-04** [impl-runtime-composer] Create `plugin-wheel/scripts/agents/verbs/` directory.
- [X] **T-A-05** [impl-runtime-composer] Author `plugin-wheel/scripts/agents/verbs/_index.json` per contracts §6 — version=1, verbs=6.

### Phase 4.A-cont — Composer + validator (FR-A-1, FR-A-2, FR-A-7)

- [X] **T-A-06** [impl-runtime-composer] Author `plugin-wheel/scripts/agents/compose-context.sh` per contracts §2 — argument parsing, env validation (WORKFLOW_PLUGIN_DIR), task_spec JSON validation, manifest read, override application, prompt_prefix assembly per the canonical section ordering, deterministic sorting (`LC_ALL=C`) of variables + verbs tables, JSON emission. ~150 lines target. ALL exit codes 0–7 implemented per contract.
- [X] **T-A-07** [impl-runtime-composer] Author `plugin-wheel/scripts/agents/validate-bindings.sh` per contracts §3 — read manifest, walk `agent_bindings:`, refuse on unknown verb. ~60 lines target.

### Phase 4.A-cont — Plugin manifest extension (FR-A-7)

- [X] **T-A-08** [impl-runtime-composer] Modify `plugin-kiln/.claude-plugin/plugin.json` — add `agent_bindings:` section per contracts §3 example (research-runner / fixture-synthesizer / output-quality-judge with v1 placeholder verb command-templates). Run `validate-bindings.sh` on the updated manifest — MUST exit 0.

---

## Phase 5 — Theme A agents + tests (impl-runtime-composer)

### Phase 5.A — 3 research-first agent.md files (FR-A-10, FR-A-11, SC-6)

- [X] **T-A-09** [impl-runtime-composer] Audit existing `plugin-kiln/agents/research-runner.md` — confirm frontmatter (`name`, `description`, `tools: Read, Bash, SendMessage, TaskUpdate, TaskList`, NO `model:`) and body (no verb tables, no tool references, no model selection, no step-by-step task prose). If non-conformant, refactor in-place. Document any divergence in `agent-notes/impl-runtime-composer.md`.
- [X] **T-A-10** [impl-runtime-composer] Author `plugin-kiln/agents/fixture-synthesizer.md` — frontmatter (`name: fixture-synthesizer`, `description: ...`, `tools: Read, Write, SendMessage, TaskUpdate`, NO `model:`). Body: pure role identity per FR-A-11.
- [X] **T-A-11** [impl-runtime-composer] Author `plugin-kiln/agents/output-quality-judge.md` — frontmatter (`name: output-quality-judge`, `description: ...`, `tools: Read, SendMessage, TaskUpdate`, NO `model:`). Body: pure role identity per FR-A-11.

### Phase 5.A-cont — Test fixtures (SC-3, SC-4, SC-5, SC-6)

- [X] **T-A-12** [impl-runtime-composer] Create `plugin-wheel/tests/compose-context-shape/run.sh` (SC-3) — invokes composer with sample task_spec, asserts JSON shape per contracts §2, asserts re-invocation byte-identical (NFR-6).
- [X] **T-A-13** [impl-runtime-composer] Create `plugin-wheel/tests/validate-bindings-unknown-verb/run.sh` (SC-4) — fixture manifest with unknown verb, asserts validator exits 4.
- [X] **T-A-14** [impl-runtime-composer] Create `plugin-wheel/tests/compose-context-unknown-override/run.sh` (SC-5) — fixture PRD with override referencing unknown agent, asserts composer exits 5.
- [X] **T-A-15** [impl-runtime-composer] Create `plugin-kiln/tests/research-first-agents-structural/run.sh` (SC-6) — for each of 3 agents: assert frontmatter has `tools:`, no `model:`; body has no verb tables (grep for `| Verb |`), no enumerated tool references (grep for `Bash(`, etc.), no `## Steps` / `1.` numbered task lists.

---

## Phase 6 — CLAUDE.md documentation (impl-runtime-composer, FR-A-12, FR-B-8, SC-8)

- [X] **T-A-16** [impl-runtime-composer] Add a section to CLAUDE.md "Active Technologies" (or a sibling "Architectural Rules" section) documenting the 6 rules from FR-A-12: (a) NEVER use `general-purpose` for specialized roles in production; (b) one role per registered subagent_type, multiple spawns per run with different injected variables; (c) injection is prompt-layer NOT system-prompt-layer; (d) top-level orchestration is correct, not nested; (e) agent registration is session-bound; (f) plain-text output is invisible to team-lead — always relay via `SendMessage`. Use canonical phrasings reviewers can grep for.
- [X] **T-A-17** [impl-runtime-composer] Append to the same CLAUDE.md section: Theme B directive syntax + resolver location + module convention (FR-B-8). One paragraph.
- [X] **T-A-18** [impl-runtime-composer] Append to the same CLAUDE.md section: composer integration recipe (per plan.md §"Integration recipe"). Code block + one-paragraph guidance.
- [X] **T-A-19** [impl-runtime-composer] Create `plugin-kiln/tests/claude-md-architectural-rules/run.sh` (SC-8) — greps CLAUDE.md for canonical phrases (`never use \`general-purpose\``, `injection is prompt-layer`, `agent registration is session-bound`, `relay via SendMessage`, `<!-- @include`, `compose-context.sh`); fails if any is missing.

---

## Phase 7 — Final validation (both tracks observe)

- [ ] **T-V-01** [both] Run all 6 fixtures end-to-end:
  - `plugin-kiln/tests/agent-includes-resolve/run.sh` (SC-1, SC-7)
  - `plugin-kiln/tests/agent-includes-ci-gate/run.sh` (SC-2)
  - `plugin-wheel/tests/compose-context-shape/run.sh` (SC-3)
  - `plugin-wheel/tests/validate-bindings-unknown-verb/run.sh` (SC-4)
  - `plugin-wheel/tests/compose-context-unknown-override/run.sh` (SC-5)
  - `plugin-kiln/tests/research-first-agents-structural/run.sh` (SC-6)
  - `plugin-kiln/tests/claude-md-architectural-rules/run.sh` (SC-8)
  All MUST PASS.
- [ ] **T-V-02** [both] Each implementer fills `specs/agent-prompt-composition/agent-notes/<track>.md` with friction observations per pipeline-contract FR-009.
- [ ] **T-V-03** [both] Confirm spec.md "Theme Partition" table matches actual file edits — no file should have been edited by both tracks (NFR-8 disjoint partition).

---

## Theme B filtered view (impl-include-preprocessor)

Tasks owned: T-B-01..T-B-13, plus T-V-01 (Theme B fixtures) + T-V-02 + T-V-03.

Files owned (per spec.md "Theme Partition"):
- `plugin-kiln/scripts/agent-includes/resolve.sh`
- `plugin-kiln/scripts/agent-includes/build-all.sh`
- `plugin-kiln/scripts/agent-includes/check-compiled.sh`
- `plugin-kiln/agents/_shared/coordination-protocol.md`
- `plugin-kiln/agents/_src/qa-engineer.md`
- `plugin-kiln/agents/_src/prd-auditor.md`
- `plugin-kiln/agents/_src/debugger.md`
- `plugin-kiln/agents/qa-engineer.md` (compiled output)
- `plugin-kiln/agents/prd-auditor.md` (compiled output)
- `plugin-kiln/agents/debugger.md` (compiled output)
- `plugin-kiln/tests/agent-includes-resolve/`
- `plugin-kiln/tests/agent-includes-ci-gate/`
- `specs/agent-prompt-composition/agent-notes/impl-include-preprocessor.md`

## Theme A filtered view (impl-runtime-composer)

Tasks owned: T-A-01..T-A-19, plus T-V-01 (Theme A fixtures) + T-V-02 + T-V-03.

Files owned (per spec.md "Theme Partition"):
- `plugin-wheel/scripts/agents/compose-context.sh`
- `plugin-wheel/scripts/agents/validate-bindings.sh`
- `plugin-wheel/scripts/agents/verbs/_index.json`
- `plugin-kiln/lib/task-shapes/_index.json`
- `plugin-kiln/lib/task-shapes/{skill,frontend,backend,cli,infra,docs,data,agent}.md`
- `plugin-kiln/agents/research-runner.md` (audit/refactor — exists)
- `plugin-kiln/agents/fixture-synthesizer.md` (NEW)
- `plugin-kiln/agents/output-quality-judge.md` (NEW)
- `plugin-kiln/.claude-plugin/plugin.json` (`agent_bindings:` add)
- `plugin-wheel/tests/compose-context-shape/`
- `plugin-wheel/tests/compose-context-unknown-override/`
- `plugin-wheel/tests/validate-bindings-unknown-verb/`
- `plugin-kiln/tests/research-first-agents-structural/`
- `plugin-kiln/tests/claude-md-architectural-rules/`
- `CLAUDE.md` (architectural rules section — FR-A-12)
- `specs/agent-prompt-composition/agent-notes/impl-runtime-composer.md`
