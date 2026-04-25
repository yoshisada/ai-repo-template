# Implementation Plan: Cross-Plugin Resolver + Pre-Flight Plugin Registry

**Spec**: [spec.md](./spec.md) | **Contracts**: [contracts/interfaces.md](./contracts/interfaces.md) | **Research**: [research.md](./research.md) | **Tasks**: [tasks.md](./tasks.md)
**PRD**: [../../docs/features/2026-04-24-cross-plugin-resolver-and-preflight-registry/PRD.md](../../docs/features/2026-04-24-cross-plugin-resolver-and-preflight-registry/PRD.md)

## §1 — Architecture overview

Three new bash libraries under `plugin-wheel/lib/` (single source of truth, sourced by the existing engine):

```
plugin-wheel/lib/
  registry.sh    NEW   — build_session_registry  (Theme F1)
  resolve.sh     NEW   — resolve_workflow_dependencies  (Theme F3 + F2 schema validation)
  preprocess.sh  NEW   — template_workflow_json  (Theme F4 + tripwire)
  context.sh     EDIT  — refactor WORKFLOW_PLUGIN_DIR templating to call preprocess.sh (FR-F4-3)
  workflow.sh    EDIT  — workflow_load gains shape-only schema check for requires_plugins (FR-F2-3)
  engine.sh      EDIT  — wires registry → resolve → preprocess into the activation path
```

Three test homes:

```
plugin-wheel/tests/                       — pure-shell unit tests (no LLM)
  preprocess-substitution.bats            — token + escape grammar (§2.B research)
  preprocess-tripwire.bats                — narrowed-pattern tripwire firing
  registry-path-parse.bats                — Candidate A PATH parsing logic
  resolve-error-shapes.bats               — error text matches FR-F3-3 strings

plugin-kiln/tests/                        — /kiln:kiln-test substrate (real LLM-driven)
  registry-marketplace-cache/             — NFR-F-3 install-mode coverage
  registry-plugin-dir/                    — NFR-F-3 install-mode coverage
  registry-settings-local-json/           — NFR-F-3 install-mode coverage
  resolve-missing-plugin/                 — FR-F3-3 missing dep
  resolve-disabled-plugin/                — EC-1 disabled plugin
  preprocess-tripwire/                    — end-to-end tripwire from real workflow JSON (companion to bats)
  back-compat-no-requires/                — NFR-F-5 byte-identical
  perf-kiln-report-issue/                 — NFR-F-4 + NFR-F-6 perf gate
```

Single workflow JSON migrated:

```
plugin-kiln/workflows/kiln-report-issue.json   EDIT (FR-F5)
```

## §2 — Phasing

### Phase 1 — Setup (shared)

- Read constitution + spec + this plan + contracts.
- Create `agent-notes/{impl-registry-resolver,impl-preprocessor,impl-migration-perf}.md` stubs.
- Confirm dependencies present: `bash 5.x`, `jq`, `awk`, `python3` (all already required by wheel).

### Phase 2 — Foundational (blocks all themes)

**Phase 2.A** (impl-registry-resolver): Author the registry algorithm dry-run script under `plugin-wheel/lib/registry.sh::_internal_path_parse` against the live PATH on the developer's machine. Validates the §1 research finding that PATH gives `name → path` correctly for marketplace mode; commits the algorithm; no caller wires it up yet.

**Phase 2.B** (impl-preprocessor): Author the preprocessor's pure substitution logic in `plugin-wheel/lib/preprocess.sh::template_workflow_json` against a fixed input registry + workflow JSON (no live registry yet). Includes escape-decoding logic (decided per research §2.B + U-1: `awk` for the escape pre-scan, bash for substitution loop). Pure-shell `.bats` tests under `plugin-wheel/tests/preprocess-*.bats` validate it.

These two sub-phases are parallelizable — they don't share files.

### Phase 3 — Theme F1 + F3 wired up (impl-registry-resolver)

- `registry.sh::build_session_registry` becomes the public entrypoint. Adds Candidate B fallback per research §1.D behind `WHEEL_REGISTRY_FALLBACK=1` env var (or auto-fallback when A returns empty).
- `resolve.sh::resolve_workflow_dependencies` reads the registry + workflow JSON, validates each `requires_plugins` entry, exits non-zero with documented FR-F3-3 error text on any failure.
- Integration: `engine.sh` activation path calls `build_session_registry` first, then `resolve_workflow_dependencies`, then proceeds to existing dispatch.
- Diagnostic snapshot at `.wheel/state/<run-id>-registry.json` written; failure-only retention via `engine.sh::cleanup_on_success`.
- Five `/kiln:kiln-test` fixtures land here:
  1. `registry-marketplace-cache/`
  2. `registry-plugin-dir/`
  3. `registry-settings-local-json/`
  4. `resolve-missing-plugin/`
  5. `resolve-disabled-plugin/`

### Phase 4 — Theme F2 + F4 wired up (impl-preprocessor)

- `workflow.sh::workflow_load` extended with shape-only schema validation for `requires_plugins`. (Per research §7 U-2: keep registry-aware checks in resolve.sh; workflow_load only validates JSON shape.)
- `preprocess.sh::template_workflow_json` becomes the canonical templating call. Wired into `engine.sh` AFTER resolve_workflow_dependencies.
- `context.sh::context_build` is refactored to delegate `WORKFLOW_PLUGIN_DIR` templating to the preprocessor. The Option B inline `runtime_env_block` is REMOVED (its absolute-path emission is no longer needed because the instruction text already contains literal absolute paths). Backward-compat note: workflows that DO mention `${WORKFLOW_PLUGIN_DIR}` literally for documentation purposes get the legacy Theme D block restored only via the documented `$${WORKFLOW_PLUGIN_DIR}` escape.
- Tripwire fires post-substitution per FR-F4-5.
- One `/kiln:kiln-test` fixture lands here:
  6. `preprocess-tripwire/` — end-to-end (companion to the pure-shell bats coverage).

### Phase 5 — Theme F5 atomic migration + perf + back-compat (impl-migration-perf)

- `kiln-report-issue.json` is updated per FR-F5-1: `requires_plugins: ["shelf"]` + three `${WHEEL_PLUGIN_shelf}/scripts/...` substitutions.
- This migration commit MUST contain BOTH the workflow JSON edit AND the resolver/registry/preprocessor wiring (per NFR-F-7). The implementer coordinates with impl-registry-resolver and impl-preprocessor to land all three in one commit (or as a stacked PR landing in one merge).
- Two `/kiln:kiln-test` fixtures land here:
  7. `back-compat-no-requires/` — NFR-F-5 byte-identical
  8. `perf-kiln-report-issue/` — NFR-F-4 + NFR-F-6 perf gate

### Phase 6 — Validation

- Run all 8 `/kiln:kiln-test` fixtures + all 4 `.bats` files. All green.
- Run `git grep -E '\$\{(WORKFLOW_PLUGIN_DIR|WHEEL_PLUGIN_)[^}]*\}' .wheel/history/success/*.json` after a fresh `kiln-report-issue` run. Zero matches (SC-F-6).
- Compare perf fixture output against `b81aa25` baseline. Within 120% (SC-F-4).
- Audit (Task #6) verifies all FRs/NFRs/SCs land with passing tests.

## §3 — Tech stack

Per Absolute Must #1: **Bash 5.x + `jq` + `awk` + `python3` (existing) + POSIX**. No new runtime dependencies.

- `registry.sh` — pure bash + `jq` (parse `installed_plugins.json` and `plugin.json`).
- `resolve.sh` — pure bash + `jq`.
- `preprocess.sh` — `awk` for escape pre-scan (§2.B), bash for substitution loop, `jq` for JSON manipulation. `python3` is permitted as a fallback if `awk`-based escape decoding hits a portability issue on macOS BSD awk vs gawk.

## §4 — File-by-file edit list

**New files**:

| File | Owner | Purpose |
|---|---|---|
| `plugin-wheel/lib/registry.sh` | impl-registry-resolver | Theme F1 — `build_session_registry` |
| `plugin-wheel/lib/resolve.sh` | impl-registry-resolver | Theme F3 — `resolve_workflow_dependencies` + schema validation reused from workflow_load |
| `plugin-wheel/lib/preprocess.sh` | impl-preprocessor | Theme F4 — `template_workflow_json` + tripwire |
| `plugin-wheel/tests/preprocess-substitution.bats` | impl-preprocessor | Pure-shell tripwire grammar tests |
| `plugin-wheel/tests/preprocess-tripwire.bats` | impl-preprocessor | Tripwire firing on residuals |
| `plugin-wheel/tests/registry-path-parse.bats` | impl-registry-resolver | Candidate A PATH parsing logic |
| `plugin-wheel/tests/resolve-error-shapes.bats` | impl-registry-resolver | FR-F3-3 error text exact-match |
| `plugin-kiln/tests/registry-marketplace-cache/` | impl-registry-resolver | NFR-F-3 |
| `plugin-kiln/tests/registry-plugin-dir/` | impl-registry-resolver | NFR-F-3 |
| `plugin-kiln/tests/registry-settings-local-json/` | impl-registry-resolver | NFR-F-3 |
| `plugin-kiln/tests/resolve-missing-plugin/` | impl-registry-resolver | FR-F3-3 |
| `plugin-kiln/tests/resolve-disabled-plugin/` | impl-registry-resolver | EC-1 |
| `plugin-kiln/tests/preprocess-tripwire/` | impl-preprocessor | FR-F4-5 e2e |
| `plugin-kiln/tests/back-compat-no-requires/` | impl-migration-perf | NFR-F-5 |
| `plugin-kiln/tests/perf-kiln-report-issue/` | impl-migration-perf | NFR-F-4 + NFR-F-6 |

**Edited files**:

| File | Owner | Change |
|---|---|---|
| `plugin-wheel/lib/workflow.sh` | impl-preprocessor | Add `requires_plugins` shape validation in `workflow_load` |
| `plugin-wheel/lib/context.sh` | impl-preprocessor | Remove inline Option B `runtime_env_block`; delegate to preprocess.sh |
| `plugin-wheel/lib/engine.sh` | impl-registry-resolver | Wire registry → resolve → preprocess into activation |
| `plugin-kiln/workflows/kiln-report-issue.json` | impl-migration-perf | FR-F5-1 substitution + `requires_plugins: ["shelf"]` |

## §5 — Cross-track dependencies

- impl-preprocessor's `preprocess.sh` consumes the registry JSON shape produced by impl-registry-resolver's `registry.sh`. Both implementers must match `contracts/interfaces.md §1` (registry shape) and `contracts/interfaces.md §3` (preprocessor input).
- impl-migration-perf's atomic-commit requirement (NFR-F-7) means impl-registry-resolver AND impl-preprocessor must produce a green build BEFORE impl-migration-perf opens the FR-F5 PR. Coordinate via Task #4's `blockedBy` on Tasks #2 and #3.
- The `context.sh` edit (impl-preprocessor) removes Option B's inline templating. impl-registry-resolver's `engine.sh` integration must already call the preprocessor at the right point in the activation path BEFORE this removal lands, or workflows break in the interim. Land the engine.sh wiring (Phase 3) before the context.sh refactor (Phase 4).

## §6 — Risk register (delta from PRD)

- **R-F-1 (perf gate)**: PRD risk preserved. Mitigation: perf fixture (#8) catches regression; resolver design uses single-pass PATH walk + `jq` (no quadratic loops).
- **R-F-2 (test scaffolding)**: PRD risk preserved. Mitigation: research §5.A documents HOME isolation pattern; verified in plan §3.
- **R-F-3 (tripwire false positives)**: PRD risk preserved. Mitigation: narrowed pattern in FR-F4-5 + EC-4 fixture in `back-compat-no-requires/` containing legitimate `${VAR}` syntax.
- **R-F-4 (NEW — context.sh refactor blast radius)**: removing Option B's inline `runtime_env_block` may affect background sub-agents that depend on the explicit "## Runtime Environment" header. Mitigation: in `back-compat-no-requires/` fixture, include a workflow whose agent step spawns a `run_in_background: true` sub-agent and assert it still resolves paths correctly via the preprocessor's literal substitution.
- **R-F-5 (NEW — atomic migration coordination)**: NFR-F-7 requires three implementers' work to land in one commit. Mitigation: impl-migration-perf authors a stacked PR that lands all three implementers' changes together; team-lead coordinates via Task #4's blockers.

## §7 — Constitutional checks

- **Article I (Spec-First)**: spec.md complete, FRs numbered, acceptance scenarios present. ✅
- **Article II (80% coverage)**: every new bash file has corresponding `.bats` or `/kiln:kiln-test` fixture. ✅
- **Article III (PRD as source of truth)**: this plan does not contradict PRD; both `installed_plugins.json` shape and Candidate A primary decision are consistent with PRD §"Open Questions". ✅
- **Article IV (Hooks)**: no hook changes required by this PRD; existing 4-gate enforcement applies to the new bash files (must be in src-equivalent locations — they are under `plugin-wheel/lib/`, which is plugin source). ✅
- **Article V (E2E required)**: `/kiln:kiln-test` fixtures exercise the full activation path with real `claude --print` invocations. ✅
- **Article VI (Small files)**: each new lib file expected <300 lines (registry.sh ~80, resolve.sh ~100, preprocess.sh ~200). ✅
- **Article VII (Interface contracts)**: `contracts/interfaces.md` defines bash signatures for all three new functions. ✅
- **Article VIII (Incremental task completion)**: tasks.md groups tasks by phase; commits land at phase boundaries. ✅
