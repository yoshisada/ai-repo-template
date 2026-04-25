# impl-preprocessor — friction notes (FR-009)

Track friction encountered while implementing Theme F2 (schema) + F4 (preprocessor + tripwire).
Filled in incrementally during work; finalized before marking task #3 completed.

## Phase 2.B — preprocessor pure logic + bats coverage

- **awk → sentinel-byte python3 pivot.** Plan §3 nominated `awk` for the
  escape pre-scan. In practice the escape-grammar contract (research §2.B
  / I-P-3) requires *positional* skip-tracking: the literal `$${...}`
  sequence must be invisible to the substitution stage and then decoded
  back. BSD awk's `gsub()` doesn't have negative lookbehind; the cleanest
  awk implementation is a manual char-by-char tokenizer, which is more
  fragile (and platform-divergent: macOS BSD awk vs Linux gawk) than a
  20-line `python3` pass that already-permitted-as-fallback per plan §3.
  Pivoted to a sentinel-byte placeholder pattern (`\x01ESC_DOLLAR_BRACE\x01`)
  inside python3. The sentinel is invisible to the FR-F4-5 narrowed
  tripwire grep, so escapes survive without false positives. Net: less
  code, more portable, behaviour matches the contract verbatim. Worth
  surfacing in retro: the plan's "awk preferred" guidance traded a small
  dependency win for a meaningful complexity hit.

- **Tripwire-before-decode ordering.** Initial draft decoded the sentinel
  inside the python3 stage, then ran the bash-side tripwire grep. That
  caught literal `${WHEEL_PLUGIN_shelf}` from user docstrings as a
  residual and false-positived. Fixed by leaving the sentinel in place
  through the tripwire scan and decoding in bash AFTER the scan returns
  zero. Cheap fix, but a non-obvious ordering — worth a comment in the
  source (added).

- **Bats was not preinstalled.** `brew install bats-core` worked locally;
  CI configs (e.g. `.github/workflows/wheel-tests.yml`) currently have
  no bats step. Phase 4 Wire-up should ensure CI installs bats before
  running the new `.bats` files. Flagging for impl-migration-perf and
  the auditor.

## Phase 4 — engine wiring + workflow_load schema + context.sh refactor

- **Schema check duplication is intentional.** T040 adds
  `workflow_validate_requires_plugins` to `workflow_load`. The same shape
  checks already live inline in `resolve.sh::resolve_workflow_dependencies`
  (per contract I-V-5 — "called inline by this function or by
  `workflow_load` before this function — implementer's choice"). Kept BOTH
  with byte-identical error text: workflow_load is the early gate (catches
  malformed workflow JSONs at load time), resolve.sh is the late gate
  (catches the same shape-bug if a caller bypasses workflow_load — e.g.
  unit tests that hand-build a workflow JSON). NFR-F-2 silent-failure
  tripwires (`resolve-error-shapes/run.sh`) still pass because the late
  gate is unchanged. Auditor signal: identical strings → either gate's
  failure looks the same to the user.

- **`template_workflow_json` wiring detour.** T041 wires the preprocessor
  into `post-tool-use.sh`'s activation block AFTER `engine_preflight_resolve`.
  Captured the registry stdout (previously discarded into `>/dev/null 2>&1`)
  and threaded it into the preprocessor. On tripwire firing, the existing
  `false` short-circuit pattern keeps state creation entirely off — same
  FR-F3-1 contract that the resolver already used. Did NOT wire the
  preprocessor into `validate-workflow.sh`: validate is documentation-only
  (no state mutation), and the resolver's token-discovery scan covers the
  practical case (an instruction referencing an undeclared plugin). The
  preprocessor's tripwire is the runtime defense-in-depth check, not a
  validation-time check.

- **Engine sources `preprocess.sh` unconditionally.** Added a re-source
  guard (`WHEEL_PREPROCESS_SH_LOADED`) and put the source line right
  beneath registry.sh / resolve.sh in `engine.sh` — the same outside-
  the-workflow_load-gate pattern impl-registry-resolver already
  established. Means any caller that sources engine.sh gets the
  preprocessor for free.

- **T042 Theme D test cascade — three tests, not just context.sh.**
  Removing `runtime_env_block` from context.sh broke all three FR-D1
  tests because they assert the marker text. Updated all three:
  - `context-runtime-env/run.sh` — flipped to assert the marker is now
    ABSENT and that Step Instruction still emits.
  - `workflow-plugin-dir-bg/run.sh` — repurposed as a Theme F4
    consumer-install smoke test: feeds a `${WORKFLOW_PLUGIN_DIR}`-using
    workflow through `template_workflow_json` (with a synthetic registry)
    and asserts the literal install-cache path lands in the instruction,
    no residual tokens, no Runtime Environment header. The original
    test's bg-sub-agent script was kept (slightly tweaked) so the
    end-to-end "the path resolves to a real script" assertion still
    runs against the new substitution output.
  - `workflow-plugin-dir-tripwire/run.sh` — repurposed as the Theme F4
    NFR-F-2 silent-failure tripwire: neuters the FR-F4-5 narrowed-pattern
    grep in `preprocess.sh` (string-search + slice replacement, not regex)
    and asserts that `preprocess-tripwire.bats` fails loudly. Skips
    cleanly when bats is unavailable.

- **CI bats install gap closed.** Added `bats` to the apt-get install
  step in `.github/workflows/wheel-tests.yml`, plus a new step that runs
  both new bats suites. Also added the SC-F-6 grep alongside the
  pre-existing SC-007 check, defensively scoped to runtime artefact dirs.

- **T043 fixture design — the malformed-dotted-name angle.** The naive
  test "instruction has `${WHEEL_PLUGIN_unknown}` and requires_plugins is
  empty" doesn't reach the preprocessor's tripwire — the resolver's
  token-discovery scan catches it first with the FR-F3-3 unknown-token
  error. To exercise the preprocessor's tripwire as the sole defense,
  the fixture uses `${WHEEL_PLUGIN_some.dotted.name}`: the dot violates
  the strict `[a-zA-Z0-9_-]+` grammar, so the resolver's regex doesn't
  match the token (resolver passes), the preprocessor's regex doesn't
  match either (so substitution skips it), and the narrowed-pattern
  tripwire `\${(WHEEL_PLUGIN_|WORKFLOW_PLUGIN_DIR)` matches the prefix
  and fires. This is the genuine "preprocessor is the runtime backstop"
  test case.

- **Bash heredoc + python3 -c '...' multi-line gotcha.** First pass at
  the kiln-test fixture used `python3 -c '<multi-line>'` for the hook
  input JSON. macOS bash 5.2 + python 3.11 raised `'(' was never closed`
  on line 3. Rewrote as single-line `python3 -c "..."` (double-quoted)
  with embedded single quotes for python string literals. Worth a CI
  note: future fixtures should prefer single-line python -c for
  portability.

- **Test posture summary.** All Phase 4 deliverables ship green:
  - `plugin-wheel/tests/preprocess-substitution.bats` — 15/15
  - `plugin-wheel/tests/preprocess-tripwire.bats` — 10/10
  - `plugin-wheel/tests/context-runtime-env/run.sh` — OK (repurposed)
  - `plugin-wheel/tests/workflow-plugin-dir-bg/run.sh` — OK (repurposed)
  - `plugin-wheel/tests/workflow-plugin-dir-tripwire/run.sh` — OK (repurposed)
  - `plugin-kiln/tests/preprocess-tripwire/run.sh` — 3/3 (T043)
  Existing impl-registry-resolver tests still green:
  - `registry-path-parse/run.sh` — 8/8
  - `resolve-error-shapes/run.sh` — 10/10
  - `plugin-kiln/tests/resolve-missing-plugin/run.sh` — 4/4

