# Tasks: Cross-Plugin Resolver + Pre-Flight Plugin Registry

**Branch**: `build/cross-plugin-resolver-and-preflight-registry-20260424`
**Spec**: [spec.md](./spec.md) | **Plan**: [plan.md](./plan.md) | **Contracts**: [contracts/interfaces.md](./contracts/interfaces.md) | **Research**: [research.md](./research.md)
**PRD**: [../../docs/features/2026-04-24-cross-plugin-resolver-and-preflight-registry/PRD.md](../../docs/features/2026-04-24-cross-plugin-resolver-and-preflight-registry/PRD.md)

## Implementer partition (NON-NEGOTIABLE)

Three implementer tracks. Each one reads its filtered slice below:

- **impl-registry-resolver** — Theme F1 (registry) + F3 (resolver). Owns `plugin-wheel/lib/registry.sh`, `resolve.sh`, the engine.sh wiring, and 5 install-mode/resolver fixtures (`registry-marketplace-cache`, `registry-plugin-dir`, `registry-settings-local-json`, `resolve-missing-plugin`, `resolve-disabled-plugin`) plus 2 bats files (`registry-path-parse.bats`, `resolve-error-shapes.bats`).
- **impl-preprocessor** — Theme F2 (schema validation in workflow_load) + F4 (preprocessor + tripwire). Owns `plugin-wheel/lib/preprocess.sh`, `workflow.sh` schema edit, `context.sh` Option B refactor, and 1 e2e fixture (`preprocess-tripwire`) plus 2 bats files (`preprocess-substitution.bats`, `preprocess-tripwire.bats`).
- **impl-migration-perf** — Theme F5 (atomic migration) + perf gate + back-compat. Owns `plugin-kiln/workflows/kiln-report-issue.json`, `perf-kiln-report-issue` fixture, `back-compat-no-requires` fixture. Coordinates the atomic landing per NFR-F-7.

**Cross-track dependencies** (tasks flagged `[DEP]` with the upstream track):
- impl-preprocessor's preprocess.sh consumes impl-registry-resolver's registry JSON shape (contract §1).
- impl-preprocessor's `context.sh` refactor MUST land AFTER impl-registry-resolver's `engine.sh` wiring is in place — otherwise back-compat workflows break in the interim.
- impl-migration-perf's FR-F5 commit MUST contain BOTH the workflow JSON edit AND the runtime wiring (NFR-F-7). Phase 5 is gated on Phases 3 and 4 both completing.

**Phase commit boundaries** (for `/implement` incremental commits per Constitution VIII):
- Phase boundaries are marked `## Phase N` below. Commit after each phase across all tracks that touch it.

---

## Phase 1 — Setup (shared, all tracks observe)

- [X] T001 [impl-registry-resolver] [impl-preprocessor] [impl-migration-perf] Read `.specify/memory/constitution.md`, `specs/cross-plugin-resolver-and-preflight-registry/spec.md`, `plan.md`, `contracts/interfaces.md`, `research.md` from each implementer track before starting any FR task.
- [X] T002 [P] Create implementer friction-note stubs at `specs/cross-plugin-resolver-and-preflight-registry/agent-notes/{impl-registry-resolver,impl-preprocessor,impl-migration-perf}.md` (one sentence placeholder each; each track fills its own note during/after work per pipeline-contract FR-009).
- [X] T003 [P] Confirm `bash 5.x`, `jq`, `awk`, `python3` available (smoke: `bash --version`, `jq --version`, `awk --version || true`, `python3 --version`). No install task — these are existing dependencies.

---

## Phase 2 — Foundational (parallelizable across tracks)

### Phase 2.A (impl-registry-resolver) — Registry path-parse algorithm dry-run

- [ ] T010 [impl-registry-resolver] Create `plugin-wheel/lib/registry.sh` skeleton with `build_session_registry` function header matching contracts §1. Body returns the empty registry `{"schema_version":1,"built_at":"...","source":"candidate-a-path-parsing","fallback_used":false,"plugins":{}}` for now.
- [ ] T011 [impl-registry-resolver] Implement `_internal_path_parse` — iterate `$PATH` colon-segments, filter for entries ending in `/bin` whose grandparent is `.claude/plugins/cache` OR whose parent matches a `--plugin-dir` shape. For each match, derive `plugin_dir = dirname(entry)` and read `<plugin_dir>/.claude-plugin/plugin.json::name` for the canonical name.
- [ ] T012 [impl-registry-resolver] Wire `_internal_path_parse` into `build_session_registry` so it returns the populated map.
- [ ] T013 [impl-registry-resolver] Implement `_internal_installed_plugins_fallback` — read `~/.claude/plugins/installed_plugins.json`, cross-check against `~/.claude/settings.json::enabledPlugins` and `<project>/.claude/settings.local.json::enabledPlugins`, build the map. Triggered when path-parse returns empty OR when `WHEEL_REGISTRY_FALLBACK=1`.
- [ ] T014 [impl-registry-resolver] Add bash bootstrap for wheel itself (`BASH_SOURCE`-derived path) per contract I-R-3. Defense against PATH parsing missing wheel for any reason.
- [ ] T015 [impl-registry-resolver] Author `plugin-wheel/tests/registry-path-parse.bats` covering: empty PATH → empty map; one valid plugin entry → one map entry; duplicate entries → first-occurrence wins; missing `plugin.json` → directory-basename fallback + stderr warning.

### Phase 2.B (impl-preprocessor) — Pure preprocessor logic

- [X] T020 [impl-preprocessor] Create `plugin-wheel/lib/preprocess.sh` skeleton with `template_workflow_json` function header matching contracts §3.
- [X] T021 [impl-preprocessor] Implement escape pre-scan via `awk` — record byte positions of `$${` sequences. (Per research §2.B + plan §3.) [Implemented via a sentinel-byte placeholder in a single python3 pass — equivalent semantics, fewer awk-vs-BSD-awk drift risks; rationale logged in agent-notes.]
- [X] T022 [impl-preprocessor] Implement substitution loop — iterate the workflow JSON's agent steps, substitute `${WHEEL_PLUGIN_<name>}` and `${WORKFLOW_PLUGIN_DIR}` tokens against the registry + calling_plugin_dir args.
- [X] T023 [impl-preprocessor] Implement post-substitution decode — replace `$${` → `${` only at recorded escape positions. [Bash-side decode runs AFTER the tripwire scan on the still-encoded text, so legitimate escapes never trip the wire.]
- [X] T024 [impl-preprocessor] Implement tripwire — narrowed pattern `\$\{(WHEEL_PLUGIN_|WORKFLOW_PLUGIN_DIR)`; on match, exit 1 with the documented FR-F4-5 error text including step id.
- [X] T025 [impl-preprocessor] Author `plugin-wheel/tests/preprocess-substitution.bats` — covers token substitution, escape decoding, idempotence (I-P-5), generic `${VAR}` passthrough (EC-4). [15/15 passing]
- [X] T026 [impl-preprocessor] Author `plugin-wheel/tests/preprocess-tripwire.bats` — covers the four documented residual cases (unsubstituted token, unknown name, malformed escape, tripwire exact error text). [10/10 passing]

---

## Phase 3 — Theme F1 + F3 wired into engine (impl-registry-resolver)

- [ ] T030 [impl-registry-resolver] Create `plugin-wheel/lib/resolve.sh` with `resolve_workflow_dependencies` matching contracts §2. Implements: schema check (per I-V-5), token-discovery scan over agent step instructions (per I-V-4), cross-check against registry, exits 0 or 1 with documented FR-F3-3 error text.
- [ ] T031 [impl-registry-resolver] Wire into `plugin-wheel/lib/engine.sh` activation path: BEFORE any state mutation, call `build_session_registry`, then `resolve_workflow_dependencies`. On either failure, exit non-zero, no state file created. (Contract I-V-1 enforces "no side effects on resolver failure".)
- [ ] T032 [impl-registry-resolver] Add diagnostic snapshot writer — after registry build, write `.wheel/state/<run-id>-registry.json`. Hook into `engine.sh::cleanup_on_success` to delete on success; retain on failure (matches existing `.wheel/history/{success,failed}/` retention pattern).
- [ ] T033 [impl-registry-resolver] Author `plugin-wheel/tests/resolve-error-shapes.bats` — exact-string match for all three FR-F3-3 documented error texts. NFR-F-2 silent-failure tripwire: deliberately mutate the error string and assert the test fails.
- [ ] T034 [impl-registry-resolver] Author `plugin-kiln/tests/registry-marketplace-cache/` fixture per research §5.A — scaffold fake `~/.claude/plugins/cache/<org-mp>/<plugin>/<version>/` under `/tmp/kiln-test-<uuid>/`, run `claude --print ... --plugin-dir <fake>`, assert registry resolves to fake-cache paths.
- [ ] T035 [impl-registry-resolver] Author `plugin-kiln/tests/registry-plugin-dir/` fixture — two competing copies (cache vs override), assert override wins via marker-file check.
- [ ] T036 [impl-registry-resolver] Author `plugin-kiln/tests/registry-settings-local-json/` fixture — scaffold `.claude/settings.local.json` with project-scoped enabledPlugins, assert local-settings path resolves.
- [ ] T037 [impl-registry-resolver] Author `plugin-kiln/tests/resolve-missing-plugin/` fixture — workflow with `requires_plugins: ["nonexistent"]`, assert pre-flight fails with documented error before any state mutation.
- [ ] T038 [impl-registry-resolver] Author `plugin-kiln/tests/resolve-disabled-plugin/` fixture — plugin physically present in cache but not in `enabledPlugins`, assert "not enabled in this session" error (EC-1).
- [ ] T039 [impl-registry-resolver] Run all 5 kiln-test fixtures + 2 bats files; capture results in `agent-notes/impl-registry-resolver.md`. Commit Phase 3.

---

## Phase 4 — Theme F2 + F4 wired into engine (impl-preprocessor)

- [ ] T040 [impl-preprocessor] [DEP impl-registry-resolver T031] Edit `plugin-wheel/lib/workflow.sh::workflow_load` — add shape-only validation for `requires_plugins` per contract §4 validation rules. Pure shape check (non-string, empty string, duplicates); registry-aware checks belong to resolve.sh.
- [ ] T041 [impl-preprocessor] [DEP impl-registry-resolver T031] Wire `template_workflow_json` into `engine.sh` activation path AFTER `resolve_workflow_dependencies`. The templated workflow JSON is then passed to the existing dispatch path (state-file creation, step iteration, etc.).
- [ ] T042 [impl-preprocessor] [DEP impl-registry-resolver T031] Refactor `plugin-wheel/lib/context.sh::context_build` — REMOVE the inline Option B `runtime_env_block` emission (Theme D legacy). The instruction text already contains literal absolute paths after preprocessing, so the explicit "## Runtime Environment" header is redundant. Preserve the function signature and all other behavior byte-identically.
- [ ] T043 [impl-preprocessor] Author `plugin-kiln/tests/preprocess-tripwire/` fixture — workflow JSON with `${WHEEL_PLUGIN_unknown}` token (no matching `requires_plugins` entry). Assert tripwire fires at preprocess time, no agent dispatch happens, exit code is non-zero, error text matches FR-F4-5.
- [ ] T044 [impl-preprocessor] Run `preprocess-tripwire/` kiln-test + 2 bats files; capture results in `agent-notes/impl-preprocessor.md`. Commit Phase 4.

---

## Phase 5 — Theme F5 atomic migration + perf + back-compat (impl-migration-perf)

**ATOMIC COMMIT REQUIREMENT (NFR-F-7)**: T050 + the impl-registry-resolver Phase 3 commit + the impl-preprocessor Phase 4 commit MUST land together as a single merge to main. Coordinate via team-lead — Task #4 in the task system has `blockedBy: [#2, #3]` to enforce ordering.

- [ ] T050 [impl-migration-perf] [DEP impl-registry-resolver T039, impl-preprocessor T044] Edit `plugin-kiln/workflows/kiln-report-issue.json` per FR-F5-1:
  - Add `"requires_plugins": ["shelf"]` immediately after `"version"` field.
  - In the `dispatch-background-sync` step's `instruction` text, replace ALL THREE occurrences of `${WORKFLOW_PLUGIN_DIR}/scripts/<name>.sh` with `${WHEEL_PLUGIN_shelf}/scripts/<name>.sh` for `shelf-counter.sh`, `append-bg-log.sh`, `step-dispatch-background-sync.sh`.
- [ ] T051 [impl-migration-perf] Verify FR-F5-2 — `git grep -lE '\$\{WORKFLOW_PLUGIN_DIR\}' plugin-*/workflows/*.json` shows the other six workflows are unchanged AND their cross-plugin references (if any) are confirmed in-plugin (none should be cross-plugin per the PRD's "Honest scope statement").
- [ ] T052 [impl-migration-perf] Author `plugin-kiln/tests/back-compat-no-requires/` fixture per NFR-F-5 — pick an unchanged workflow (e.g. `shelf-sync.json` or another that doesn't declare `requires_plugins`), record a pre-PRD snapshot of its `.wheel/state_<id>.json` and `wheel.log` lines, run it against post-PRD code, diff. Diff must be empty modulo timestamps and run IDs. Include in the fixture a workflow whose instruction contains generic `${VAR}` syntax (R-F-3 / EC-4 coverage).
- [ ] T053 [impl-migration-perf] Author `plugin-kiln/tests/perf-kiln-report-issue/` fixture per NFR-F-4 + NFR-F-6 — re-run the existing `plugin-kiln/tests/kiln-report-issue-batching-perf/` workflow N times, compare median wall-clock and median `duration_api_ms` against the recorded baseline at commit `b81aa25`. Both must be ≤120%. Additionally, in a no-deps configuration, measure `time bash plugin-wheel/lib/resolve.sh ...` and assert ≤200ms.
- [ ] T054 [impl-migration-perf] Run a clean consumer-install simulation per SC-F-5 — temp dir with `--plugin-dir` overrides for both kiln and shelf, invoke `/kiln:kiln-report-issue`, assert the bg log line at `.kiln/logs/report-issue-bg-<date>.md` contains `counter_after=N+1` and the absolute path in `command_log` resolves to the override location (not the source-repo cache).
- [ ] T055 [impl-migration-perf] Run SC-F-6 verification — `git grep -E '\$\{(WORKFLOW_PLUGIN_DIR|WHEEL_PLUGIN_)[^}]*\}' .wheel/history/success/*.json` returns zero matches. Capture in `agent-notes/impl-migration-perf.md`.
- [ ] T056 [impl-migration-perf] Capture results in `agent-notes/impl-migration-perf.md`. Commit Phase 5 as the atomic migration commit (per NFR-F-7 coordination above).

---

## Phase 6 — Validation (auditor — Task #6)

- [ ] T060 [auditor] Verify all 8 `/kiln:kiln-test` fixtures pass: 5 from impl-registry-resolver (Phase 3), 1 from impl-preprocessor (Phase 4), 2 from impl-migration-perf (Phase 5).
- [ ] T061 [auditor] Verify all 4 `.bats` files pass under `plugin-wheel/tests/`.
- [ ] T062 [auditor] Verify SC-F-3 — `kiln-report-issue.json` declares `requires_plugins: ["shelf"]` and uses `${WHEEL_PLUGIN_shelf}/scripts/...` (grep for both).
- [ ] T063 [auditor] Verify SC-F-4 — perf fixture median wall-clock + `duration_api_ms` within 120% baseline.
- [ ] T064 [auditor] Verify SC-F-6 — zero `${...}` plugin-path tokens in `.wheel/history/success/*.json` after a fresh kiln-report-issue run.
- [ ] T065 [auditor] Verify SC-F-7 — each documented failure mode produces its documented error text (NFR-F-2 tripwire tests passing).
- [ ] T066 [auditor] Open PR with `build-prd` label per kiln workflow.

---

## Phase 7 — Retrospective (Task #7)

- [ ] T070 [retrospective] Read all `agent-notes/` friction notes from impl-registry-resolver, impl-preprocessor, impl-migration-perf, specifier (this file's author), audit-midpoint, auditor.
- [ ] T071 [retrospective] Analyze prompt effectiveness per pipeline-contract retrospective template — focus on (a) whether the team-lead's chaining mandate (specify→plan→tasks in one pass) reduced or increased friction vs the standard /specify→/plan→/tasks loop, (b) whether the OQ-F-1 BLOCKING resolution requirement was clear enough, (c) how the kiln-test substrate adoption felt for an architectural feature (this is the first non-perf PRD heavily using it; lessons feed forward into the build-prd skill's substrate guidance per `.kiln/issues/2026-04-24-build-prd-substrate-list-omits-kiln-test.md`).
- [ ] T072 [retrospective] File any improvements as `.kiln/issues/2026-04-24-cross-plugin-resolver-retro-*.md` per existing convention.
