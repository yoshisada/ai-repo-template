# impl-registry-resolver — friction notes (FR-009)

Track friction encountered while implementing Theme F1 (registry) + F3 (resolver).
Filled in incrementally during work; finalized before marking task #2 completed.

## 2026-04-25 — Phases 2.A + 3 wrap-up

### What worked smoothly

- **Candidate A (PATH parsing) verification.** Research §1.A's claim that
  marketplace-cache mode surfaces every loaded plugin's `/bin` on `$PATH` held
  exactly. The first sanity check (`echo $PATH | grep cache`) returned all
  seven enabled plugins immediately — no edge-case wrangling required.
- **Self-bootstrap (I-R-3) via `BASH_SOURCE`.** Cheap and robust. The
  registry can always derive its own install dir from `BASH_SOURCE[0]`
  even when running under a stripped PATH.
- **Resolver error-text contract.** FR-F3-3's exact-text mandate made the
  test (resolve-error-shapes/run.sh) trivially writable as `grep -qF`
  assertions. The NFR-F-2 silent-failure mutation test (case j) drops out
  for free: replace `return 1` with `return 0` in a copied resolver and
  assert the resolver suddenly returns 0 — that's literally the silence
  the contract is supposed to catch.

### Friction worth surfacing

1. **`bats` was not preinstalled — plan said `.bats`, dev/CI envs have no
   `bats-core`.** Plan §4 nominated `.bats` files at `plugin-wheel/tests/`,
   but `which bats` returns nothing on this dev box and `.github/workflows/
   wheel-tests.yml` has no bats install step. Existing convention is
   `<test-name>/run.sh` (e.g. `agent-resolver/run.sh`). Pivoted all four
   pure-shell unit tests to that convention, named the directories per
   the plan's intent (`registry-path-parse/`, `resolve-error-shapes/`).
   impl-preprocessor's notes call out the same bats-availability gap;
   either CI gets a bats install step (~3 lines) or both implementer
   tracks should normalize on `run.sh`. Worth resolving in retro.

2. **`engine.sh` source guard accidentally skipped registry+resolve.**
   The pre-existing guard pattern was:
   ```bash
   if [[ -z "${WHEEL_LIB_DIR:-}" ]] || ! declare -f workflow_load &>/dev/null; then
     # source state.sh, workflow.sh, dispatch.sh, lock.sh, context.sh, guard.sh
   fi
   ```
   When `validate-workflow.sh` sources `workflow.sh` first (sets
   `workflow_load`) and then `engine.sh`, the OR short-circuits false →
   the source block is skipped → `registry.sh` and `resolve.sh` never
   load → `build_session_registry: command not found` at runtime. Fix:
   moved registry/resolve sources OUTSIDE the gate (each file has its
   own re-source guard, so this is safe). One-line followup if the
   wheel team wants to clean up: replace the workflow_load-presence
   check with a per-lib `declare -F build_session_registry` check, or
   just always source everything (each lib already guards itself).

3. **Diagnostic-snapshot lifecycle simplification.** Contract said
   "delete on success, retain on failure" with a `cleanup_on_success`
   hook. Concrete implementation chose simpler equivalent semantics:
   write the snapshot ONLY on resolver failure
   (`.wheel/state/registry-failed-<timestamp>.json`). On success no
   snapshot is written, so no cleanup hook is needed. Net: one less
   integration point, identical observable behavior for post-mortem.
   Logged the deviation in tasks.md T032.

4. **Resolver token-discovery scan + escape grammar.** Initial attempt
   used `sed 's/\$\${[^}]*\}//g'` to strip escaped `$${...}` before
   matching `${WHEEL_PLUGIN_*}`. macOS BSD sed parses brace-quantifier
   syntax differently from GNU sed and emits "RE error: invalid
   repetition count(s)" on the same pattern that GNU sed accepts.
   Pivoted to a portable awk loop that hand-tokenizes the input —
   identical semantics, works on both BSD and GNU awk. (Note:
   impl-preprocessor hit the same portability issue and pivoted to a
   sentinel-byte python3 pass for the same reason. Either approach
   works; both are documented for the retro.)

5. **PATH cleanup in test fixtures.** Sandboxed registry tests need a
   PATH that has system tools (`jq`, `awk`, `basename`) but NOT the
   developer's actual plugin /bin entries (otherwise the test asserts
   against the dev's real cache, defeating isolation). Solution: build
   `clean_path` by greppping out `\.claude/plugins/(cache|installed)|/
   plugin-[a-zA-Z0-9_-]+/bin$` from `$PATH` once per fixture. Worth
   factoring into a shared helper if more fixtures are added.

### Test results (T039)

- `plugin-wheel/tests/registry-path-parse/run.sh` — 8/8 passing
- `plugin-wheel/tests/resolve-error-shapes/run.sh` — 10/10 passing (incl.
  NFR-F-2 silent-failure mutation case)
- `plugin-kiln/tests/registry-marketplace-cache/run.sh` — 6/6
- `plugin-kiln/tests/registry-plugin-dir/run.sh` — 3/3
- `plugin-kiln/tests/registry-settings-local-json/run.sh` — 3/3 (incl.
  FR-F1-3 disabled-in-settings.local case)
- `plugin-kiln/tests/resolve-missing-plugin/run.sh` — 4/4
- `plugin-kiln/tests/resolve-disabled-plugin/run.sh` — 4/4

Total: 38 assertions across 7 test files, all green.

### Coordination signals for impl-preprocessor + impl-migration-perf

- T031 (engine.sh wiring) is complete. The activation path now calls
  `engine_preflight_resolve` in BOTH `validate-workflow.sh` (front-line)
  AND `hooks/post-tool-use.sh` (defense-in-depth before `state_init`).
  Phase 4's T041 (preprocessor wiring) can now plug `template_workflow_json`
  into the existing path AFTER `engine_preflight_resolve` returns success.
- The registry JSON envelope shape in interfaces.md §1 is implemented
  exactly as specified: `{schema_version, built_at, source, fallback_used,
  plugins: {name: path}}`. impl-preprocessor's preprocess.sh consumes the
  `.plugins` map directly.
