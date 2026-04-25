# Wheel Test Runner

`plugin-wheel/scripts/harness/wheel-test-runner.sh` is the plugin-agnostic executable test harness. Any plugin can invoke it directly — no dependency on `plugin-kiln/` is required.

This document is the consumer-facing contract. The single source of truth for the CLI signature, exit codes, output paths, and snapshot-diff exclusion regex is `specs/wheel-test-runner-extraction/contracts/interfaces.md` (in the plugin source repo).

## What it does

For every test fixture under `plugin-<plugin>/tests/<test>/` that contains a `test.yaml`:

1. Validates the `test.yaml` schema.
2. Creates a scratch dir at `/tmp/kiln-test-<uuid>/` and seeds it with the fixture's `fixtures/` contents.
3. Spawns a real Claude subprocess (`claude --print --verbose --input-format=stream-json --output-format=stream-json --dangerously-skip-permissions --plugin-dir <plugin-root>`) with the test's `inputs/initial-message.txt` as the first user envelope.
4. Streams the session transcript while a watcher classifier polls the scratch dir for `stalled` / `exited` / `failed` states (no hard timeouts — classifier-driven).
5. Runs the test's `assertions.sh` against the final scratch state.
6. Emits TAP v14 on stdout and writes a verdict report at `.kiln/logs/kiln-test-<uuid>.md`.

## Three invocation forms

```bash
# Form A — auto-detect plugin (single plugin-<name>/ sibling in CWD)
bash plugin-wheel/scripts/harness/wheel-test-runner.sh

# Form B — run all tests for an explicit plugin
bash plugin-wheel/scripts/harness/wheel-test-runner.sh <plugin>

# Form C — run a single test
bash plugin-wheel/scripts/harness/wheel-test-runner.sh <plugin> <test>
```

`<plugin>` is the bare plugin name without the `plugin-` prefix (e.g., `kiln`, `wheel`, `foo`). Tests are discovered under `<repo-root>/plugin-<plugin>/tests/<test>/` (or per `discovery_path` in `.kiln/test.config`).

## Exit codes

| Code | Meaning |
|---|---|
| `0` | All tests passed |
| `1` | At least one test failed (TAP `not ok ...`) |
| `2` | At least one test was inconclusive (`# SKIP <reason>`) AND no tests failed; OR fatal `Bail out!` |

## Stdout — TAP v14 stream

```
TAP version 14
1..N
ok 1 - <test-name>
not ok 2 - <test-name>
  ---
  classification: "failed"
  scratch-uuid: "<uuid>"
  scratch-retained: "/tmp/kiln-test-<uuid>/"
  verdict-report: ".kiln/logs/kiln-test-<uuid>.md"
  transcript: ".kiln/logs/kiln-test-<uuid>-transcript.ndjson"
  expected-exit: 0
  actual-exit: 1
  ...
```

Bail-out form (fatal error — usage, missing CLI, bad input):

```
Bail out! <human-readable diagnostic>
```

## Output paths

| Path | Description |
|---|---|
| `.kiln/logs/kiln-test-<uuid>.md` | Verdict report (markdown). |
| `.kiln/logs/kiln-test-<uuid>-transcript.ndjson` | Per-test stream-json envelope transcript. |
| `.kiln/logs/kiln-test-<uuid>-scratch.txt` | Scratch-dir snapshot summary. |
| `.kiln/logs/kiln-test-<uuid>-verdict.json` | Watcher verdict JSON. |
| `/tmp/kiln-test-<uuid>/` | Scratch directory. Retained on fail; removed on pass. |

The `kiln-test-` prefix is a back-compat fossil — log/scratch paths are named after the historic skill `/kiln:kiln-test`, not the runner's location. Do not rename without coordinating with every existing fixture's path-based assertions.

## Environment variables

| Var | Required | Default | Description |
|---|---|---|---|
| `KILN_TEST_REPO_ROOT` | optional | `$(pwd)` | Repo root for plugin discovery. |

Inside `assertions.sh`, the harness sets:

| Var | What |
|---|---|
| `KILN_HARNESS=1` | Always set when a skill runs under the harness. Skills MAY check this to skip interactive features. |
| `KILN_TEST_SCRATCH_DIR` | Scratch dir path (same as CWD when assertions.sh runs). |
| `KILN_TEST_NAME` | Test directory basename. |
| `KILN_TEST_VERDICT_JSON` | Path to watcher verdict JSON for this test. |

## `.kiln/test.config` overrides

Optional file at repo root:

```
discovery_path=plugin-<name>/tests
watcher_stall_window_seconds=300
watcher_poll_interval_seconds=30
```

The literal string `<name>` in `discovery_path` is substituted with the plugin name at runtime.

## Worked example — non-kiln consumer

Suppose you author `plugin-foo` with one test `tests/foo-basic/`:

```
plugin-foo/
├── .claude-plugin/
│   └── plugin.json
├── skills/
│   └── foo-greet/
│       └── SKILL.md
└── tests/
    └── foo-basic/
        ├── test.yaml
        ├── inputs/
        │   └── initial-message.txt    # "/foo-greet"
        └── assertions.sh              # checks scratch-dir state
```

Minimal `test.yaml`:

```yaml
harness-type: plugin-skill
skill-under-test: foo:foo-greet
expected-exit: 0
description: "Smoke — invoke foo-greet"
```

Invoke directly via wheel:

```bash
cd <repo-root>
bash plugin-wheel/scripts/harness/wheel-test-runner.sh foo foo-basic
```

Expected output:

```
TAP version 14
1..1
ok 1 - foo-basic
```

Exit 0. No `plugin-kiln/` in the call chain.

## Limitations (v1)

- Only `harness-type: plugin-skill` is implemented. The `harness-type: shell-test` substrate (for pure-shell `run.sh`-only fixtures) is a future extension tracked under `2026-04-25-shell-test-substrate` in the kiln source repo.
- One Claude subprocess per test (no pooling). ~5–10s startup overhead per test.
- Mid-session prompts are answered via queued `inputs/answers.txt` lines, not interactive.

## Related

- `plugin-wheel/scripts/harness/snapshot-diff.sh` — per-fixture byte-identity comparator (3 modes: `bats` / `verdict-report` / `verdict-report-deterministic`).
- `plugin-kiln/skills/kiln-test/SKILL.md` — the kiln-side façade that delegates to this runner.
- `plugin-wheel/tests/wheel-test-runner-direct/run.sh` — the non-kiln consumability fixture (5 structural assertions exercise the runner without `plugin-kiln/scripts/` in the call chain).
