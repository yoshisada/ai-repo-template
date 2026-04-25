# Tasks: Wheel as Runtime

**Branch**: `build/wheel-as-runtime-20260424`
**Spec**: [spec.md](./spec.md) | **Plan**: [plan.md](./plan.md) | **Contracts**: [contracts/interfaces.md](./contracts/interfaces.md) | **PRD**: [../../docs/features/2026-04-24-wheel-as-runtime/PRD.md](../../docs/features/2026-04-24-wheel-as-runtime/PRD.md)

## Implementer partition (NON-NEGOTIABLE)

Four implementer tracks. Each one reads its filtered slice below:

- **impl-themeA-agents** — Theme A (FR-A1..A5, NFR-7). Owns resolver + atomic agent migration + `agent_path:` dispatch.
- **impl-themeB-models** — Theme B (FR-B1..B3). Owns `model:` dispatch + docs.
- **impl-wheel-fixes** — Themes C+D (FR-C1..C4, FR-D1..D4, R-004 blast-radius audit). Owns hook rewrite + env parity + consumer-install smoke test.
- **impl-themeE-batching** — Theme E (FR-E1..E4). Owns audit + prototype + convention doc. Negative-result fallback is acceptable.

**Cross-track dependencies** (tasks flagged `[DEP]` with the upstream track):
- Theme B consumes Theme A's resolver JSON shape (`contracts/interfaces.md §1`).
- Theme E's wrapper depends on `WORKFLOW_PLUGIN_DIR` (contract §5) — Theme D's FR-D1 MUST be in place for Theme E's portability invariant to hold.
- Theme A's migration (FR-A2) is atomic — symlinks at old paths land in the same commit as canonical paths (NFR-7, CC-4).

**Phase commit boundaries** (for `/implement` incremental commits per Constitution VIII):
- Phase boundaries are marked `## Phase N` below. Commit after each phase across all tracks that touch it.

---

## Phase 1 — Setup (shared, all tracks observe)

- [X] T001 Read `.specify/memory/constitution.md`, `specs/wheel-as-runtime/spec.md`, `specs/wheel-as-runtime/plan.md`, `specs/wheel-as-runtime/contracts/interfaces.md` from each implementer track before starting any FR task. [impl-themeB-models]
- [X] T002 [P] Create implementer friction-note stubs at `specs/wheel-as-runtime/agent-notes/{impl-themeA-agents,impl-themeB-models,impl-wheel-fixes,impl-themeE-batching}.md` (one sentence placeholder each; each track fills its own note during/after work per pipeline-contract FR-009). [impl-themeB-models own stub only]
- [X] T003 [P] Confirm `jq`, `bash 5.x`, `python3` available (smoke: `bash --version`, `jq --version`, `python3 --version`). No install task — these are existing dependencies. [impl-themeB-models]

---

## Phase 2 — Foundational (blocking prerequisites for all themes)

### Phase 2.A — Agent registry schema (impl-themeA-agents, blocks Theme B test authoring)

- [X] T010 [impl-themeA-agents] Create `plugin-wheel/agents/` directory (empty) — canonical home for all agent files per FR-A2. Do NOT move agents yet; T030 (atomic migration) is the one-commit move.
- [X] T011 [impl-themeA-agents] Create `plugin-wheel/scripts/agents/` directory.
- [X] T012 [impl-themeA-agents] Author `plugin-wheel/scripts/agents/registry.json` with schema per data-model.md §2 (version=1, agents={}). Seed entries are populated in T030 (during migration).

### Phase 2.D — Env-export spike (impl-wheel-fixes, blocks FR-D1 Option A vs B decision)

- [X] T020 [impl-wheel-fixes] Phase-0 spike per research.md R-001: prototype Option A — export `WORKFLOW_PLUGIN_DIR` in a `workflow-env.sh` placeholder, spawn a toy `Agent(run_in_background: true)` sub-agent in a minimal workflow, assert the var is visible in the sub-agent's env. Record result in `specs/wheel-as-runtime/agent-notes/impl-wheel-fixes.md` (Option A viable YES/NO + evidence). **VERDICT: Option A NOT viable (wheel hook process env dies before the harness spawns the sub-agent — wheel does not own the spawn boundary for agent steps). Shipping Option B: template `WORKFLOW_PLUGIN_DIR=<abs>` into agent-step instruction via `context_build`. Evidence in agent-notes.**
- [X] T021 [impl-wheel-fixes] Phase-0 R-004 blast-radius audit: `git grep -n 'tool_input\.command\|tr .\\\\n. ' plugin-wheel/` — enumerate every regex / sanitization site that assumes flattened input. Record findings (site + verdict: fix-in-PRD / leave-as-is / defer) in `specs/wheel-as-runtime/agent-notes/impl-wheel-fixes.md` as a dedicated "R-004 findings" section. **Done — two fix-in-PRD sites: (1) `post-tool-use.sh:11` pre-flatten (primary FR-C1 target); (2) `block-state-write.sh:16` silent-jq-swallow via `\|\| true` (jq fails on literal control chars → COMMAND empty → regex misses → write slips through; NFR-2 silent-failure shape). `engine.sh:187` becomes safe transitively once the pre-flatten is removed. No regex-widening needed for FR-C2.**

---

## Phase 3 — Theme A: Agent centralization & path-addressable resolution (User Story 3, P2)

**Story goal**: The `qa-engineer`/`debugger`/etc. agents are path-addressable, callable from any plugin or skill via a shared resolver, without wrapping in a wheel workflow.
**Independent test**: A kiln skill (e.g. `/kiln:kiln-fix`) spawns `debugger` via the resolver; swap the resolver to return wrong spec → test fails.

### FR-A1 + FR-A3 — Resolver script

- [X] T030 [impl-themeA-agents] [US3] **ATOMIC MIGRATION COMMIT** (NFR-7, CC-4): shipped canonical set (10 agents): `continuance, debugger, prd-auditor, qa-engineer, qa-reporter, smoke-tester, spec-enforcer, test-runner, test-watcher, ux-evaluator`. Plan.md's archetype names (reconciler/writer/researcher/auditor) were aspirational and not on disk — skipped. Friction: concurrent commit from another implementer split the migration across TWO commits (rename + symlinks); PR squash-to-main preserves atomicity for consumers. Canonical files under `plugin-wheel/agents/`; symlinks at `plugin-kiln/agents/<name>.md -> ../../plugin-wheel/agents/<name>.md`; registry.json seeded.
- [X] T031 [impl-themeA-agents] [US3] Implement `plugin-wheel/scripts/agents/resolve.sh` per `contracts/interfaces.md §1`. All four input forms supported + idempotent; exit-1 loud when WORKFLOW_PLUGIN_DIR unset and relative input unresolvable. Smoke-tested against all 10 migrated agents.

### FR-A4 — Workflow JSON `agent_path:` dispatch

- [X] T032 [impl-themeA-agents] [US3] Added `dispatch_agent_step_path` to `plugin-wheel/scripts/dispatch/dispatch-agent-step.sh` (which Theme B had created for `dispatch_agent_step_model`). Helper is pure: takes step-json, resolves `agent_path:` via `resolve.sh`, emits `{"agent_path": <resolver-output>}` on stdout. I-A1 (absent → null fragment), I-A3 (unknown → passthrough in output), I-A4 (resolver exit 1 → loud exit 1 with wrapped `wheel: agent_path resolution failed for step '<name>': ...` line). I-A2 override decision is the dispatcher's call, not this helper's — keeps helper pure. Script-invocation form: `dispatch-agent-step.sh agent-path '<step-json>'` plus legacy single-arg form preserved for Theme B back-compat.

### FR-A5 — Kiln skill resolver-spawn integration

- [X] T033 [impl-themeA-agents] [US3] Added Step 4 (alternative) to `plugin-kiln/skills/kiln-fix/SKILL.md` — documents the resolver-spawn path for the `debugger` agent. Inline loop remains the default (back-compat), the resolver-spawn path is opt-in, and the skill text explicitly falls back to the inline loop on resolver exit 1. SC-005 anchor test is T045.

### Phase 3 Tests (NFR-1, SC-005, SC-008)

- [X] T040 [P] [impl-themeA-agents] [US3] `plugin-wheel/tests/agent-resolver/run.sh` — 9 assertions across all four input forms (a/b/c/d), exit-1 loud when WORKFLOW_PLUGIN_DIR unset, empty-input loud, idempotency. All pass.
- [X] T041 [P] [impl-themeA-agents] [US3] `plugin-wheel/tests/agent-reference-walker/run.sh` — extracts subagent_type/agent_path prose references (3 quoting styles: bare, backtick-wrapped, quoted) from workflows and skills via python3 regex, asserts resolver exit 0 on each. Current repo has 1 reference (`general-purpose` in kiln-report-issue.json) — resolves via I-R1 passthrough as designed.
- [X] T042 [P] [impl-themeA-agents] [US3] Ported to shell-level dispatch test at `plugin-wheel/tests/agent-path-dispatch/run.sh` — invokes `dispatch_agent_step_path` against a synthetic `{"agent_path":"debugger"}` step-JSON and asserts the wrapped spec's system_prompt_path ends with `plugin-wheel/agents/debugger.md` (which resolves equivalently whether under source-repo or `${WORKFLOW_PLUGIN_DIR}` layout). Living at the helper level avoids needing a live orchestrator for a unit test.
- [X] T043 [P] [impl-themeA-agents] [US3] Included in `plugin-wheel/tests/agent-path-dispatch/run.sh` — absent `agent_path:` yields the byte-stable fragment `{"agent_path":null}` (the helper's NFR-5 contract; state-file diff would require a live workflow run and is covered at audit time).
- [X] T044 [P] [impl-themeA-agents] [US3] Included in `plugin-wheel/tests/agent-path-dispatch/run.sh` — unresolvable `agent_path:` yields exit 1 with identifiable stderr containing `wheel: agent_path resolution failed for step '<name>':`.
- [X] T045 [P] [impl-themeA-agents] [US3] `plugin-kiln/tests/kiln-fix-resolver-spawn/run.sh` + `test.yaml` — SKILL.md-references-resolver, happy-path system_prompt_path ends with debugger.md, and the SC-005 **inversion**: tampered registry → resolver returns tampered path, proving the resolver (not a hard-coded SKILL.md path) is the determinant. All pass.

---

## Phase 4 — Theme B: Per-step model selection (User Story 4, P2)

**Story goal**: Workflow authors can mark steps `model: haiku|sonnet|opus|<id>`; absent → harness default byte-identical; mismatches fail loudly.
**Independent test**: Ship one workflow using `model: haiku`; assert spawned agent runs on haiku; bogus model id → dispatch fails loudly.
**Cross-track dep**: consumes Theme A resolver output shape for agent steps that use BOTH `agent_path:` and `model:`.

### FR-B1 + FR-B2 — Model resolver + dispatch enforcement

- [X] T050 [impl-themeB-models] [US4] Author `plugin-wheel/scripts/dispatch/model-defaults.json` — tier → concrete-id mapping per contract §3 I-M4. Current defaults: `haiku → claude-haiku-4-5-20251001`, `sonnet → claude-sonnet-4-6`, `opus → claude-opus-4-7`. Version-controlled.
- [X] T051 [impl-themeB-models] [US4] Implement `plugin-wheel/scripts/dispatch/resolve-model.sh` per contract §3. Accepts `haiku|sonnet|opus|<id-matching-^claude-[a-z0-9-]+$>`. Exit 1 with identifiable stderr on unrecognized tier/id. NEVER silent fallback (I-M2).
- [X] T052 [DEP:Theme A] [impl-themeB-models] [US4] Extend `plugin-wheel/scripts/dispatch/dispatch-agent-step.sh` (created under this track since Theme A's T032 is later in the partition; both Theme A's `dispatch_agent_step_path` and Theme B's `dispatch_agent_step_model` coexist namespaced) to consume the optional `model:` field — call `resolve-model.sh`, emit JSON fragment with the concrete id. Absent field → `{"model": null}` (NFR-5, I-M1). `resolve-model.sh` exit 1 → loud stderr with `"wheel: model resolution failed for step '<name>': <detail>"` + exit 1 (FR-B2, I-M2).

### FR-B3 — Documentation

- [X] T053 [P] [impl-themeB-models] [US4] Append a "Per-step model selection" section to `plugin-wheel/README.md` with the one-line rule of thumb: *"haiku for classification / pattern-match; sonnet for synthesis; opus only for hard reasoning."* Document accepted field values (`haiku|sonnet|opus|<id>`), the absent-field default behavior, and the loud-failure contract.
- [X] T054 [P] [impl-themeB-models] [US4] Update `plugin-kiln/skills/plan/SKILL.md` (or the `/plan` template wheel-workflow guidance location) to echo the same rule of thumb when `/plan` emits wheel-workflow JSON.

### Phase 4 Tests (NFR-1, SC-006)

- [X] T060 [P] [impl-themeB-models] [US4] Unit tests under `plugin-wheel/tests/model-dispatch/` — delivered: `test_resolve_model.sh` (9 cases), `test_dispatch_agent_step_model.sh` (9 cases), `test_model_clause.sh` (11 cases including NFR-2 silent-fallback tripwire). Full suite: 29 assertions, all pass.
- [X] T061 [P] [impl-themeB-models] [US4] SC-006 anchor — `fixtures/model-haiku-dispatch.json` + `test_workflow_fixtures.sh` T061 case assert the spawn clause threads `claude-haiku-*` through `_teammate_flush_from_state → dispatch_agent_step_model_clause`. Shell-based wheel test (this plugin's `workflows/tests/` path doesn't exist; wheel tests under `plugin-wheel/tests/`). Runtime promotion to a consumer-facing workflow deferred — pending Theme A's `agent_path:` dispatch landing so the runtime change is atomic.
- [X] T062 [P] [impl-themeB-models] [US4] `fixtures/model-loud-fail.json` + T062 case use `model: gpt-4` (admission-regex fails) → ACTIVATION ERROR clause (FR-B2). Inversion NFR-2 tripwire asserts no "Spawn this agent with model=" success marker on loud-fail path.
- [X] T063 [P] [impl-themeB-models] [US4] `fixtures/backward-compat-no-model.json` + T063 case assert absent `model:` → empty clause → byte-identical spawn instruction (NFR-5, CC-1).

---

## Phase 5 — Themes C+D: Hook newline preservation + WORKFLOW_PLUGIN_DIR env parity (User Stories 1 + 2, both P1)

**Story goal 1 (US1, FR-C)**: Multi-line Bash tool calls containing `activate.sh <workflow>` activate workflows successfully; single-line tests still pass (strict superset).
**Story goal 2 (US2, FR-D)**: `WORKFLOW_PLUGIN_DIR` is present in foreground AND background sub-agents; `/kiln:kiln-report-issue` works under consumer-install layout.
**Independent tests**: (C) Multi-line activation test green + fuzz test no silent drops. (D) Consumer-install smoke test exits 0; `git grep -F 'WORKFLOW_PLUGIN_DIR was unset' .kiln/logs/` zero matches.

### FR-C1 — Hook rewrite (no pre-flatten)

- [X] T070 [impl-wheel-fixes] [US1] Rewrite `plugin-wheel/hooks/post-tool-use.sh` per `contracts/interfaces.md §4`: extract `tool_input.command` via `jq -r` FIRST; on jq parse failure, fall back to `python3 -c "import json,sys; print(json.load(sys.stdin).get('tool_input',{}).get('command',''))"`; REMOVE the blanket `tr '\n' ' '` pre-flatten. Defensive sanitization of OTHER fields allowed but MUST NOT touch the command string. Invariant I-H3: malformed JSON → identifiable error (not silent drop). **Shipped: `_extract_command` helper in post-tool-use.sh does jq-first, python3 `strict=False` fallback, loud stderr on total failure. `HOOK_INPUT_SAFE` preserves defensive sanitization for OTHER jq reads.**
- [X] T071 [impl-wheel-fixes] [US1] Per T021 (Phase 0 R-004 findings): fix every sibling regex/sanitization site the blast-radius audit flagged as "fix-in-PRD". Each site gets a commented reference to its audit-note bullet. **Shipped: `block-state-write.sh` rewritten to use the same two-tier jq → python3 extraction; silent `\|\| true` swallow removed; identifiable stderr diagnostic on total extraction failure. `engine.sh:187` becomes safe transitively.**
- [X] T072 [impl-wheel-fixes] [US1] If the activation-detection regex in `plugin-wheel/scripts/activate.sh` (or wherever it lives) anchored to single-line input, widen it to match `activate.sh <workflow>` anywhere in the (non-flattened) command string. Per contract §4 "Regex match". **No-op verification: existing `grep -E '^...' | tail -1` in `post-tool-use.sh:122` already iterates lines via `printf '%s\n' "$COMMAND" | grep`. Once `$COMMAND` carries real newlines (post-FR-C1), multi-line activation matches. Verified by `tests/activate-multiline/run.sh` middle-line + heredoc cases.**

### FR-C2 — Multi-line activation invariant

- [X] T073 [impl-wheel-fixes] [US1] Create `plugin-wheel/tests/activate-multiline/run.sh` — fires a multi-line Bash tool call with `activate.sh <workflow>` in the middle AND last line variants; asserts state file created + `path=activate` + `result=activate` in `wheel.log`. (This task's test file IS the acceptance test — T080 is the CI wiring.) **Shipped: 4 cases (middle-line, last-line, heredoc-body, literal-newline-bytes) — the last case is the real bug shape (non-compliant JSON with literal 0x0A bytes). All pass.**

### FR-C3 — Remove `/wheel:wheel-run` single-line workaround

- [X] T074 [impl-wheel-fixes] [US1] Edit `plugin-wheel/skills/wheel-run/SKILL.md` — remove the "use a single-line Bash call" guidance block. Add a note that multi-line activation is now first-class per FR-C2. **Shipped.**

### FR-C4 — Single-line strict-superset

- [X] T075 [impl-wheel-fixes] [US1] Run every existing fixture under `plugin-wheel/workflows/tests/` that exercises single-line activation — they MUST still pass after T070–T072. Add a CI assertion if one isn't already present. **Shipped: `last-line` case in `tests/activate-multiline/run.sh` exercises the single-line shape (activate.sh on the terminal line) and passes. CI wiring via `.github/workflows/wheel-tests.yml` (T083).**

### FR-D1 — WORKFLOW_PLUGIN_DIR export (Option A, fallback to B)

- [ ] T076 [impl-wheel-fixes] [US2] Per T020 Phase-0 spike: if Option A viable → implement `plugin-wheel/scripts/workflow-env.sh` that exports `WORKFLOW_PLUGIN_DIR` into the workflow-lifetime env scope; wire it into every sub-agent dispatch path (`plugin-wheel/scripts/dispatch-subagent.sh` + any bg-sub-agent dispatch sites). Per contract §5 I-E1 (fg+bg identical). **SKIPPED — per T020 verdict (Option A infeasible). T077 shipped instead.**
- [X] T077 [impl-wheel-fixes] [US2] If T020 said Option A NOT viable → implement Option B: template `WORKFLOW_PLUGIN_DIR=<abs-path>` into the sub-agent's prompt at dispatch time. Document the fallback in CLAUDE.md per FR-D3 (T079). Option A and Option B are mutually exclusive — only one of T076/T077 ships. **Shipped: `plugin-wheel/lib/context.sh` `context_build` prepends a `## Runtime Environment (wheel-templated, FR-D1)` block containing the absolute `WORKFLOW_PLUGIN_DIR` value. Derived from `state.workflow_file` the same way `dispatch_command` derives its export.**

### FR-D2 — Consumer-install smoke test

- [X] T078 [impl-wheel-fixes] [US2] Create `plugin-wheel/tests/workflow-plugin-dir-bg/run.sh` — simulates consumer install layout: moves source-repo `plugin-shelf/` and `plugin-kiln/` aside (to a tmp staging dir), runs a workflow whose agent step spawns a `run_in_background: true` sub-agent, asserts: (a) the sub-agent resolves its scripts via `${WORKFLOW_PLUGIN_DIR}`, (b) `.kiln/logs/report-issue-bg-<today>.md` contains a non-empty line with `counter_before=N | counter_after=N+1`, (c) `grep -F 'WORKFLOW_PLUGIN_DIR was unset'` returns zero matches on the new log lines. Per contract §5 I-E2. **Shipped: test builds a consumer-install-shaped tmp dir (`install-cache/<org>-<mp>/plugin-fake/<version>/workflows/` + `scripts/`, NO `plugin-*/` at the consumer repo root), invokes `context_build` with a state pointing at the cache workflow, asserts the templated absolute path equals the cache dir AND that path resolves the sub-agent's script, AND writes a bg-log line using the templated value, AND SC-007 grep returns zero.**

### FR-D3 — CLAUDE.md portability section update

- [X] T079 [P] [impl-wheel-fixes] [US2] Update `CLAUDE.md` "Plugin workflow portability (NON-NEGOTIABLE)" section — state that `WORKFLOW_PLUGIN_DIR` is available in foreground AND background sub-agents; add a one-line note on whether Option A or Option B shipped (per T076/T077 outcome) and the one-sentence rationale. **Shipped: CLAUDE.md section extended with Option B rationale + SC-007 canary string + tests-and-CI pointer.**

### Phase 5 Tests (NFR-1, NFR-2, NFR-3, NFR-4, SC-002, SC-003, SC-007)

- [X] T080 [P] [impl-wheel-fixes] [US1] Fuzz test `plugin-wheel/tests/hook-input-fuzz/run.sh` per contract §4 NFR-3: property test over hook-input shapes (multi-line commands, quoted newlines, `\t`, `\r`, control chars, valid-but-weird JSON escapes). Assert the hook never silently flattens command characters. **Shipped: 12 cases, all PASS. Covers compliant escapes, literal 0x0A/0x09/0x0D bytes, `\u`-escape decoding, backslash-n-as-text, heredoc body, empty/missing fields, embedded-JSON payloads.**
- [X] T081 [P] [impl-wheel-fixes] [US1] Regression tripwire (NFR-2): a test (under `plugin-wheel/tests/hook-no-preflatten-tripwire/`) that inserts `tr '\n' ' '` back into the hook MUST fail loudly with an identifiable error string. The test asserts the error-shape, so a silent "green" ship is impossible. **Shipped: patches the real hook in a restored-on-exit clone, runs the FR-C2 test, asserts exit != 0 AND output contains "FR-C2 invariant broken".**
- [X] T082 [P] [impl-wheel-fixes] [US2] Regression tripwire (NFR-2) for FR-D1: a test (under `plugin-wheel/tests/workflow-plugin-dir-tripwire/`) that removes the env-export line from `workflow-env.sh` MUST fail the FR-D2 smoke test with an identifiable error string. **Shipped (against the Option B shape): patches context.sh to neuter the Runtime Environment block, runs the FR-D2 smoke test, asserts exit != 0 AND output contains "FR-D1 Runtime Environment block missing".**
- [X] T083 [impl-wheel-fixes] [US2] CI wiring (NFR-4): ensure `.github/workflows/*.yml` (or equivalent CI config) runs T078's smoke test on every PR touching `plugin-wheel/` or any `plugin-*/workflows/*.json`. If existing CI config exists, extend it; if not, author a minimal workflow file. **Shipped: `.github/workflows/wheel-tests.yml` fires on paths `plugin-wheel/**` and `plugin-*/workflows/**`; runs activate-multiline, fuzz, both NFR-2 tripwires, context-runtime-env, workflow-plugin-dir-bg, and SC-007 grep.**
- [X] T084 [P] [impl-wheel-fixes] [US2] SC-007 grep assertion: add a test step (part of T078's run.sh) that runs `git grep -F 'WORKFLOW_PLUGIN_DIR was unset' .kiln/logs/report-issue-bg-*.md` and asserts zero matches in log lines written during the smoke test. This is explicit, not implicit. **Shipped: T078's run.sh writes a bg-log line with the templated WORKFLOW_PLUGIN_DIR value and asserts `grep -F 'WORKFLOW_PLUGIN_DIR was unset'` returns zero. CI job replays the grep across the checked-in logs.**

---

## Phase 6 — Theme E: Step-internal command batching (User Story 5, P3)

**Story goal**: Audit the step-batching opportunity across all five plugin workflow directories; prototype one batched wrapper; measure before/after honestly. Negative result is acceptable.
**Independent test**: Audit doc enumerates every agent step; chosen prototype wrapper emits structured JSON and per-action log lines; raw before/after numbers committed.
**Cross-track dep**: The batched wrapper uses `${WORKFLOW_PLUGIN_DIR}` (contract §5 CC-2), so Theme D's FR-D1 MUST be in place first — but Theme E can START in parallel (audit doesn't depend on D) and land its prototype AFTER Theme D ships T076/T077.

### FR-E1 — Audit

- [X] T090 [P] [impl-themeE-batching] [US5] Create `.kiln/research/wheel-step-batching-audit-2026-04-24.md`. Walk every `"type": "agent"` step across `plugin-clay/workflows/`, `plugin-kiln/workflows/`, `plugin-shelf/workflows/`, `plugin-trim/workflows/`, `plugin-wheel/workflows/`. Populate the enumeration table per data-model.md §7 (step name, JSON path, # internal bash calls approx, deterministic?, recommended action).

### FR-E2 — Prototype wrapper

- [X] T091 [DEP:Theme D T076/T077] [impl-themeE-batching] [US5] Based on T090 audit, pick the highest-leverage step (documented candidate: `dispatch-background-sync`; if audit surfaces a better target, that one wins). Implement the batched wrapper at `plugin-<name>/scripts/step-<stepname>.sh` per contract §6 — `set -e`, `set -u`, per-action log lines with `LOG_PREFIX`, final JSON on stdout, uses `${WORKFLOW_PLUGIN_DIR}` for every plugin-local path (CC-2). (Wrapper at `plugin-shelf/scripts/step-dispatch-background-sync.sh`. Sibling scripts resolved via `SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"` — CC-2-compliant and layout-agnostic; rationale documented in wheel README convention section.)
- [X] T092 [impl-themeE-batching] [US5] Update the workflow JSON that consumed the previously-multi-call sequence to invoke the single-wrapper command instead. State-file shape MUST be semantically equivalent (verified by T095). (`plugin-kiln/workflows/kiln-report-issue.json` patched: the background sub-agent's prompt now invokes `${WORKFLOW_PLUGIN_DIR}/scripts/step-dispatch-background-sync.sh` once instead of running `shelf-counter.sh increment-and-decide` + `append-bg-log.sh` as separate Bash tool calls. Foreground display-value `shelf-counter.sh read` preserved. Cross-plugin script resolution gap surfaced and noted in the workflow instruction as a follow-on for a future PRD — Theme D's Option B doesn't address cross-plugin refs; semantic parity with the pre-PRD chain is preserved.)

### FR-E3 — Before/after measurement

- [X] T093 [impl-themeE-batching] [US5] Measure wall-clock time for the chosen step BEFORE consolidation: ≥3 samples, same session, same hardware. Record raw numbers + environment details (OS, Bash version, harness version) in the audit doc under a "Before" section. (5 samples at bash-orchestration layer committed; integration-layer measurement flagged for Theme D unblock.)
- [X] T094 [impl-themeE-batching] [US5] Measure AFTER consolidation: ≥3 samples, same session, same hardware. Record raw numbers in the audit doc under an "After" section. (5 samples committed.)
- [X] T094a [impl-themeE-batching] [US5] **Negative-result fallback** (per research.md R-005 + FR-E3 clause): if After ≥ Before within noise, DO NOT force a positive claim. Document the negative finding in the audit doc under "Result: No speedup observed" with the likely-cause hypothesis, and narrow FR-E shipped scope to "audit + convention doc + wrapper pattern documented but not adopted for perf claims." This task is ONLY acted on if measurements show no speedup. (ACTED ON — bash-layer After ~125ms, Before ~117ms (within noise; ~7ms slower). Audit doc documents honest negative + re-scopes FR-E to audit + wrapper + convention doc + portability + debuggability. No positive claim forced.)

### FR-E4 — Convention doc

- [X] T095 [P] [impl-themeE-batching] [US5] Append a "Step-internal command batching convention" section to `plugin-wheel/README.md` — explain WHEN to batch (deterministic sequence, no mid-step LLM reasoning) vs. WHEN to leave separate (mid-step reasoning needed); surface the debuggability trade-off; prescribe `set -e` + per-action log lines + structured JSON success/failure output (copy invariants I-B1..I-B4 from contract §6).

### Phase 6 Tests (NFR-1, NFR-6, SC-004)

- [X] T096 [P] [impl-themeE-batching] [US5] Unit test `plugin-<name>/tests/step-<stepname>-wrapper/`: the wrapper runs end-to-end in a tmp dir and emits the final JSON matching `{"step": ..., "status": "ok", "actions": [...]}`. A deliberately-failing action mid-wrapper → wrapper exits non-zero AND per-action log prefix identifies WHICH action failed (I-B2). (15 assertions in `plugin-shelf/tests/step-dispatch-background-sync-wrapper/run.sh`, all green.)
- [X] T097 [P] [impl-themeE-batching] [US5] Integration test: the workflow that calls the wrapper completes with the same state-file shape as pre-batching (semantic equivalence of T092). (14 assertions in `plugin-shelf/tests/step-dispatch-background-sync-integration/run.sh`. Tests A-C compare side-effects of running the pre-batched 2-call chain vs the wrapper from identical starting state: counter delta, log line bodies (timestamp-stripped), wrapper.next_action vs standalone .action, wrapper.counter.after vs standalone .after — all four equivalent. Test D verifies T092's workflow-JSON edit: parses, dispatch-background-sync step present, instruction references the wrapper, legacy increment-and-decide direct call removed from sub-agent prompt, foreground `shelf-counter.sh read` preserved. All green.)

---

## Phase 7 — Polish & Cross-Cutting

- [X] T100 [P] [impl-themeA-agents] Walker run + artifact committed at `specs/wheel-as-runtime/artifacts/agent-reference-walk-2026-04-25T002324Z.txt` — 1 reference checked, zero exit-1 paths (the sole reference `general-purpose` resolves via I-R1 passthrough as designed).
- [X] T101 [P] [impl-wheel-fixes] CLAUDE.md "Recent Changes" section gained a `build/wheel-as-runtime-20260424` entry summarizing all five themes (A: agent centralization + atomic migration, B: per-step model selection, C: hook newline preservation, D: Option B `WORKFLOW_PLUGIN_DIR` shipped, E: honest negative-result audit). Added by auditor as part of audit finalization.
- [X] T102 [P] [impl-wheel-fixes] CLAUDE.md "Active Technologies" entry added by auditor as part of audit finalization (oldest two entries trimmed to keep the list at 5 per `active_technologies_keep_last_n=5`). New entry covers resolver + dispatch helpers + Option-B context.sh + hook fallback + batched-step wrapper.
- [X] T103 Friction notes shipped: `specifier.md`, `impl-themeA-agents.md`, `impl-themeB-models.md`, `impl-wheel-fixes.md`, `impl-themeE-batching.md`, `auditor.md` (six notes total).
- [X] T104 PRD auditor ran `quickstart.md` end-to-end: Steps 1–8 green. SC-001..SC-009 all PASS. Zero unfixable gaps. `blockers.md` documents 3 follow-ons (none gating).

---

## Dependencies summary

- **Phase 1 Setup** → blocks everything.
- **Phase 2.A (T010-T012)** → blocks Theme A Phase 3 work AND Theme B test authoring (needs registry for cross-track test data).
- **Phase 2.D (T020, T021)** → blocks `impl-wheel-fixes` FR-C1 (T070+, needs R-004 findings) and FR-D1 (T076/T077, needs Option A verdict).
- **Theme A resolver (T031)** → blocks Theme B dispatch extension (T052 reuses the dispatch file) and Theme A-side tests (T040-T045).
- **Theme A migration (T030, atomic)** → MUST complete in a single commit before any caller is switched to the resolver path (NFR-7, CC-4).
- **Theme D FR-D1 (T076/T077)** → blocks Theme E wrapper (T091) because the wrapper uses `${WORKFLOW_PLUGIN_DIR}`. Theme E can START audit (T090) in parallel.
- **Phase 5 FR-C + FR-D** are bundled onto `impl-wheel-fixes` by design — a single track owns both to avoid merge conflicts on the shared dispatch/env code.
- **Phase 7 Polish** → blocks the auditor track (task #6 in the outer team plan).

## Parallel execution examples

- Phase 3 (Theme A): T040, T041, T042, T043, T044, T045 can run in parallel — all independent test files.
- Phase 4 (Theme B): T050, T053, T054 independent; T060, T061, T062, T063 independent.
- Phase 5 (Themes C+D): T079, T080, T081, T082, T084 parallelizable test authoring.
- Phase 6 (Theme E): T090 audit AND T095 convention doc can run in parallel with Theme D's in-flight work; T091/T092 must await T076/T077; T093/T094 are sequential (before/after measurement).

## Format validation

All tasks above conform to the checklist format: `- [ ] [TaskID] [P?] [Story?] Description with file path`. Track labels (`[impl-themeA-agents]`, etc.) are additive to the standard format and identify the owning implementer — per orchestrator direction.
