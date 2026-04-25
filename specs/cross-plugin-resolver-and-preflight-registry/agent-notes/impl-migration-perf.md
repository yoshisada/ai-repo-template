# impl-migration-perf — friction notes (FR-009)

Track friction encountered while implementing Theme F5 (atomic migration) + perf + back-compat.

## 2026-04-24 — Phase 5 scaffolding (T052 + T053 fixtures, pre-T050 atomic commit)

### Atomicity coordination

The team-lead's NFR-F-7 protocol — "T050 (workflow JSON migration) + impl-registry-resolver
Phase 3 commit + impl-preprocessor Phase 4 commit MUST land together as a single merge to
main" — pushed me to scaffold the two test fixtures (T052, T053) ahead of waiting for
upstream tracks. That worked cleanly: both fixtures have a "RUNTIME NOT READY" guard that
exits 2 with a clear message until the lib code lands. The impl-registry-resolver and
impl-preprocessor tracks had already committed working `plugin-wheel/lib/{registry,resolve,
preprocess}.sh` as untracked files in the same worktree, so I could smoke-test the scaffolds
against the in-progress runtime — useful early validation that caught two contract drifts
before they hit Phase 6 audit:

  1. Initial test draft asserted that the preprocessor would substitute `${WORKFLOW_PLUGIN_DIR}`
     in **command-step `.command` fields** as well as agent instructions. Re-reading
     contracts/interfaces.md §3 I-P-1 ("Schema fields, command-step `command` fields, and any
     other text are NOT preprocessed (only agent `instruction` per FR-F4-2)") corrected the
     scope: command substitution stays in the legacy env-var path at command-execution time.
     Test was rewritten around byte-identity of the templated JSON (which is the cleanest
     NFR-F-5 statement anyway).
  2. `set -euo pipefail` in run.sh + in-process invocation of `template_workflow_json` (which
     internally runs `python3` and may exit non-zero on transient internal paths even when the
     overall function returns 0) produced a non-debuggable silent exit. Switched the resolver-
     overhead trials to fresh `bash -c` subprocesses — which is also closer to how
     engine.sh activations actually call the libs.

### Perf-gate experience

Resolver+preprocess overhead on a no-deps workflow is **~119-129ms median (N=5)** on this
hardware (Darwin 24.5.0, M-series, default Homebrew bash 5.2.15) — comfortably under the
200ms NFR-F-6 gate (~37% headroom). Cost is dominated by:

  - One-time `build_session_registry` PATH parsing (jq invocations per plugin).
  - One `python3` import + run inside `template_workflow_json` for the substitution pass.

If headroom matters in the future, batching the per-plugin `jq -r .name plugin.json` reads
into a single `jq` invocation would likely halve the registry-build time. Filed as a future
optimization rather than a v1 blocker.

### kiln-test substrate friction

The kiln-test harness (`plugin-kiln/scripts/harness/kiln-test.sh`) only implements the
`harness-type: plugin-skill` substrate in v1 — the static-tripwire shape used by recently
landed fixtures (`distill-multi-theme-basic`, `kiln-fix-resolver-spawn`,
`require-feature-branch-build-prefix`) is an emergent convention rather than a first-class
substrate. The fixtures here follow that emergent convention (test.yaml + run.sh). Phase 6
auditor will need to invoke them directly with `bash plugin-kiln/tests/<name>/run.sh` rather
than via `/kiln:kiln-test plugin-kiln`, since the harness reports them as "skip" when no
`assertions.sh` + `inputs/initial-message.txt` is present.

This is the friction the team-lead flagged: build-prd's substrate guidance assumes
"plugin-skill or nothing," but architectural-feature fixtures (NFR-F-4 perf, NFR-F-6
resolver-overhead, NFR-F-5 byte-identity) are naturally library-level and don't benefit
from the LLM-driven plugin-skill substrate. The right resolution is a `harness-type: static`
implementation in dispatch-substrate.sh that runs `bash run.sh` directly under the watcher.
Logged for the retrospective; this PRD doesn't take it on. Forwards into
`.kiln/issues/2026-04-24-build-prd-substrate-list-omits-kiln-test.md`.

## 2026-04-25 — Phase 5 atomic landing (T050, T051, T054, T055, T056)

### T050 migration — escape grammar gotcha

Migrated `plugin-kiln/workflows/kiln-report-issue.json` per FR-F5-1: added
`requires_plugins: ["shelf"]` after version, bumped version 3.0.0 → 3.1.0, replaced the 3
shelf-script references in the `dispatch-background-sync` step's instruction. After the
migration, my first run of the resolver+preprocessor against the migrated workflow tripped
the FR-F4-5 tripwire with:

```
Wheel preprocessor failed: instruction text for step 'dispatch-background-sync' still
contains '${...}'.
```

Cause: I had ALSO updated the closure note at the end of the instruction to describe the
new system, with documentary references like `${WHEEL_PLUGIN_<name>}` and
`${WORKFLOW_PLUGIN_DIR}` as literal text (e.g. "the previous gap when ${WORKFLOW_PLUGIN_DIR}
resolved to plugin-kiln but the scripts lived in plugin-shelf"). The preprocessor correctly
fired the tripwire because the unsubstituted token grammar `${WHEEL_PLUGIN_<name>}` doesn't
match the substitution regex (`<` isn't in `[a-zA-Z0-9_-]+`) but DOES match the post-
substitution tripwire prefix-pattern `\$\{(WHEEL_PLUGIN_|WORKFLOW_PLUGIN_DIR)`.

First fix attempt: escape with `$$` per FR-F4-4 (`$${...}` decodes to `${...}` post-tripwire).
That cleared the tripwire — escape positions were correctly recorded and decoded. But the
post-decode text still contained literal `${WHEEL_PLUGIN_<name>}` and `${WORKFLOW_PLUGIN_DIR}`
strings, which would trip the SC-F-6 grep against the archived state file
(`git grep -E '\$\{(WORKFLOW_PLUGIN_DIR|WHEEL_PLUGIN_)[^}]*\}' .wheel/history/success/*.json`).

Final fix: rewrote the closure note in plain prose without literal token references. The
agent doesn't need to read the token grammar — it just needs the literal absolute paths.
SC-F-6 satisfied.

**Lesson**: documentary references to the new token grammar inside agent instructions are
hostile to both the FR-F4-5 runtime tripwire AND the SC-F-6 post-PRD audit grep. Even with
`$$` escaping, the post-decode form survives and trips SC-F-6. Plain prose is the only
durable form. Worth documenting in the wheel/preprocess.sh module comment for future
authors.

### T054 consumer-install simulation

Implemented as `plugin-kiln/tests/perf-kiln-report-issue/consumer-install-sim.sh`. Following
impl-registry-resolver's three guidance items:

1. `--plugin-dir` alone is enough (no settings.json seeding).
2. Must include `--plugin-dir plugin-wheel/` so the post-tool-use hook chain fires.
3. Tripwire: assert `find . -path '*/registry-failed-*.json'` returns empty.

End-to-end run against the migrated workflow:
- claude exited 0
- bg log contains `counter_after=1` (counter actually incremented)
- No `registry-failed-*.json` snapshot (resolver did not hit a failure path mid-run)
- SC-F-6 — newly-archived state file has zero `${WHEEL_PLUGIN_*}` / `${WORKFLOW_PLUGIN_DIR}`
  tokens

Wall-clock: 4 minutes. The full /kiln:kiln-report-issue path is ~4× longer than the bg-only
perf measurement because it also runs the foreground LLM agent that creates the issue file.

### T055 SC-F-6 verification — caveat for the auditor

The literal `git grep -E '\$\{(WORKFLOW_PLUGIN_DIR|WHEEL_PLUGIN_)[^}]*\}' .wheel/history/success/*.json`
returns 8 lines across 5 historical archives. All 5 archives predate commit cfe0f11 (the
impl-registry-resolver Phase 3 commit) — confirmed via:

```
$ git grep -lE '\$\{(WORKFLOW_PLUGIN_DIR|WHEEL_PLUGIN_)[^}]*\}' \
    -- '.wheel/history/success/kiln-report-issue-*.json' \
  | xargs -I{} git log -1 --format='%ai %h {}' -- {}
```

(Output: 5 archives, all from commits 2026-04-23 to 2026-04-24 06:24 — pre-PRD.)

The substantive SC-F-6 assertion (NEW post-PRD archives have zero matches) is enforced by
`consumer-install-sim.sh` assertion (e) and is currently passing. Pre-existing archives are
not regenerated — the auditor's T064 ("after a fresh kiln-report-issue run") is the
canonical post-PRD verification path; that's what consumer-install-sim does.

If the auditor wants a stricter assertion that EXCLUDES historical archives, the
formulation is:

```
# Newer than the Phase 3 commit cfe0f11 (i.e. post-PRD archives only):
git log --name-only --pretty='' --since='2026-04-25' \
    -- '.wheel/history/success/kiln-report-issue-*.json' \
  | sort -u \
  | xargs -I{} git grep -lE '\$\{(WORKFLOW_PLUGIN_DIR|WHEEL_PLUGIN_)[^}]*\}' -- {}
# Expected: empty.
```

### Perf gate (a) NFR-F-4 — final numbers

Ran `plugin-kiln/tests/perf-kiln-report-issue/run.sh` with both gates:

| Metric              | Baseline (b81aa25) | Post-PRD (this PR) | Threshold (120%) | Result |
|---------------------|-------------------:|-------------------:|-----------------:|:------:|
| Wall-clock (median) |             8.405s |             7.461s |          10.086s |  PASS  |
| duration_api_ms     |             4382ms |             4030ms |           5258ms |  PASS  |
| Resolver+preprocess |                n/a |          ~129ms    |            200ms |  PASS  |

Post-PRD bg sub-agent perf is *faster* than baseline at the median — within sample noise (the
5-sample N is small). The PRD does NOT regress bg perf because the bg sub-agent's prompt
shape and tool-call structure are unchanged: the migration moves substitution from
command-execution-time env-var (`${WORKFLOW_PLUGIN_DIR}` → exported value) to prompt-build-
time literal (preprocessor injects the absolute path). The bg sub-agent sees the same
absolute path either way.

### Status — task #4 ready to mark completed

- [X] T001-T003 (Phase 1)
- [X] T052, T053 (Phase 5 fixtures, scaffolded ahead of upstream)
- [X] T050 (workflow migration, version 3.1.0)
- [X] T051 (FR-F5-2 verified — 6 other workflows are in-plugin only)
- [X] T054 (consumer-install simulation — 5/5 assertions green)
- [X] T055 (SC-F-6 — caveat documented; canonical assertion passes via consumer-install-sim)
- [X] T056 (this commit IS the atomic Phase 5 commit per NFR-F-7)
