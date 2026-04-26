---
name: kiln-test
description: "Executable skill-test harness. Invokes real claude --print ... --plugin-dir subprocesses against /tmp/kiln-test-<uuid>/ fixtures, watched by a classifier that replaces hard timeouts. Usage: /kiln:kiln-test (auto-detect plugin), /kiln:kiln-test <plugin>, /kiln:kiln-test <plugin> <test>. Tests live under plugin-<name>/tests/; verdict reports at .kiln/logs/kiln-test-<uuid>.md."
---

# /kiln:kiln-test

**Purpose**: Run executable tests against plugin skills — the real skill, in a real Claude subprocess, against a scratch-dir fixture, with assertions that verify final scratch-dir state. Replaces documentary `SMOKE.md` files with tests that actually run.

**Non-negotiable**: this skill MUST delegate to wheel's `scripts/harness/wheel-test-runner.sh`, resolved via the dual-layout sibling traversal shown in "What to do" below (NFR-001 portability + sibling-plugin resolution per spec OQ-R-1). No repo-relative `plugin-kiln/scripts/...` or `plugin-wheel/scripts/...` path may appear in this file. The harness script lives at a stable relative path inside whichever plugin-wheel directory the consumer has cached.

## When to invoke

- You edited a skill under `plugin-<name>/skills/<skill>/SKILL.md` and want to confirm it still works.
- You're about to merge a change to `/kiln:kiln-hygiene --backfill` and want the idempotence regression test to pass.
- You're adding a new test under `plugin-<name>/tests/` and want to run it to make sure fixtures + assertions are set up correctly.

## Three invocation forms (FR-001)

| Form | What it does |
|---|---|
| `/kiln:kiln-test` | Auto-detect the plugin in the current working directory (looks for exactly one `plugin-<name>/` sibling dir that contains `.claude-plugin/` or `skills/`). Run all tests for that plugin. Fails inconclusive if zero or more than one plugin dir is present. |
| `/kiln:kiln-test <plugin-name>` | Run all tests for `plugin-<plugin-name>/`. |
| `/kiln:kiln-test <plugin-name> <test-name>` | Run a single test: `plugin-<plugin-name>/tests/<test-name>/`. Fast dev iteration (NFR-006). |

## What to do

Resolve the wheel install dir, then invoke the runner. The if/else handles both layouts:

- **Source repo**: `plugin-kiln/` and `plugin-wheel/` are siblings under the repo root.
- **Consumer cache**: `kiln/<version>/` and `wheel/<version>/` are siblings under `~/.claude/plugins/cache/<org>-<marketplace>/`.

```bash
if [ -d "${WORKFLOW_PLUGIN_DIR}/../plugin-wheel" ]; then
  WHEEL_DIR="${WORKFLOW_PLUGIN_DIR}/../plugin-wheel"
else
  WHEEL_DIR=$(ls -d "${WORKFLOW_PLUGIN_DIR}/../../wheel"/*/ 2>/dev/null | sort -V | tail -1)
fi
bash "${WHEEL_DIR}/scripts/harness/wheel-test-runner.sh" $ARGUMENTS
```

That's the entire skill. The orchestrator emits TAP v14 on stdout, writes verdict reports to `.kiln/logs/kiln-test-<uuid>.md`, and retains scratch dirs under `/tmp/kiln-test-<uuid>/` on failure for post-mortem.

If the orchestrator exits non-zero:
- Exit **1** — at least one test failed. Look at the `not ok N - <test-name>` lines + the verdict report path in the YAML diagnostic block.
- Exit **2** — at least one test was inconclusive (missing fixtures, malformed `test.yaml`, `claude` not on PATH, or multi-plugin ambiguity in auto-detect). Read the stderr diagnostic or the `# SKIP <reason>` line in the TAP stream.
- Exit **0** — all tests passed.

## Writing a new test

Under `plugin-<your-plugin>/tests/<test-name>/`:

```
tests/<test-name>/
├── test.yaml               # metadata (required)
├── fixtures/               # copied wholesale into /tmp/kiln-test-<uuid>/ before the session starts (optional — empty fixtures are valid)
├── inputs/
│   ├── initial-message.txt # first stream-json user envelope content (required — this is the skill invocation, e.g. "/kiln:kiln-distill")
│   └── answers.txt         # subsequent user envelopes, one per line (optional — omit if the skill never prompts)
└── assertions.sh           # executable; runs with CWD = scratch dir after the session exits. Non-zero exit = test fails.
```

Minimal `test.yaml`:

```yaml
harness-type: plugin-skill
skill-under-test: kiln:kiln-distill
expected-exit: 0
description: "Basic smoke — distill a 3-item fixture backlog into a PRD"
```

Inside `assertions.sh`, these env vars are available (all paths absolute):

| Env var | What |
|---|---|
| `KILN_HARNESS=1` | Always set when a skill runs under the harness. Skills MAY check this to skip interactive features. |
| `KILN_TEST_SCRATCH_DIR` | Scratch dir path (same as CWD). |
| `KILN_TEST_NAME` | Test directory basename. |
| `KILN_TEST_VERDICT_JSON` | Path to watcher verdict JSON for this test. |

## `.kiln/test.config` overrides (optional)

Create `.kiln/test.config` at repo root to tweak defaults:

```
# All keys optional. Harness falls back to defaults for absent keys.
discovery_path=plugin-<name>/tests
watcher_stall_window_seconds=300
watcher_poll_interval_seconds=30
```

- **`discovery_path`** — where the harness looks for tests. The literal string `<name>` is substituted with the plugin name. Default: `plugin-<name>/tests`. The harness recognizes two fixture shapes: (a) the canonical `test.yaml` + `inputs/` + `assertions.sh` shape (drives a live `claude --print --plugin-dir` subprocess against the fixture mktemp dir); (b) `run.sh`-only directories (a structural-invariant tripwire — harness invokes `bash run.sh` and parses the trailing `PASS:` / `FAIL:` line as the verdict). The `run.sh`-only shape is the right substrate for skill-shape regression checks where assertions pin exact contract text in source files; the `test.yaml` shape is the right substrate for live-skill behavior verification. Both ship side-by-side in the harness report.
- **`watcher_stall_window_seconds`** — seconds with zero scratch-write or transcript advance before the watcher classifies `stalled` and sends SIGTERM. Default: `300` (5 min).
- **`watcher_poll_interval_seconds`** — watcher poll cadence. Default: `30`.

Per-test override: a test's `test.yaml` may include `timeout-override: <seconds>` (range 60..3600) to override the stall window for that one test.

## Dependencies (NFR-002)

- `claude` CLI (Claude Code v2.1.119+ — verified to support `--print --verbose --input-format=stream-json --output-format=stream-json --dangerously-skip-permissions --plugin-dir`).
- Standard POSIX utilities (`find`, `sort`, `awk`, `sed`, `date`, `stat`, `mktemp`, `uuidgen`, `sha256sum` or `shasum`).
- No MCP servers, no `gh` calls, no jq/yq.

## What this harness does NOT do (out of scope for v1)

- Web-app / CLI-app / API / mobile substrates — future PRDs.
- Sandboxing — the safety boundary is the scratch-dir CWD, not a container.
- Mid-session prompt answering — scripted answers are all queued up-front via `inputs/answers.txt` as stream-json user envelopes before stdin close (per plan D6).
- Pooling `claude` subprocesses — one per test, accept the ~5-10s startup (NFR-006).

## Related

- `specs/plugin-skill-test-harness/contracts/interfaces.md` — authoritative contract for YAML schema, TAP grammar, verdict JSON, script signatures.
- `specs/plugin-skill-test-harness/spec.md` — user stories, FRs, acceptance scenarios.
- `plugin-kiln/tests/` — seed tests shipping with this PRD (see FR-015).
