# Interface Contracts: Plugin Skill Test Harness

**Status**: LOCKED. Any signature change requires a plan.md update first (Article VII).
**Scope**: Every exported contract of the harness — YAML schema, TAP grammar, watcher verdict JSON, scratch-dir invariants, substrate-dispatch signature, answer-file format, and helper-script interfaces.

---

## 1. `test.yaml` schema

Every test directory MUST contain a `test.yaml` at its root. The file MUST parse as valid YAML and satisfy this schema.

```yaml
# Required fields
harness-type: string            # Substrate tag. V1 accepts ONLY "plugin-skill".
                                #   Future: "web-app", "cli-app", "api", "mobile"
skill-under-test: string        # Fully-qualified skill name being exercised, e.g., "kiln:kiln-distill"
                                #   Informational — the actual skill invocation is driven
                                #   by inputs/initial-message.txt
expected-exit: integer          # Expected process exit code of the `claude` subprocess.
                                #   Default implicit if omitted: 0 (successful exit)
description: string             # One-line human-readable description of the test's purpose
# Optional fields
timeout-override: integer       # Seconds. Overrides watcher stall_window for THIS test only.
                                #   Does NOT override poll_interval.
                                #   Valid range: 60 .. 3600. Harness rejects values outside this range
                                #   with exit 2 (inconclusive).
```

### Validation rules

- Unknown top-level keys MUST cause test-yaml-validate.sh to emit a warning but NOT fail — forward-compat for future substrate fields.
- `harness-type` MUST be one of the accepted substrate tags. V1 accepts exactly `plugin-skill`. Unknown substrate → exit 2 (inconclusive).
- `expected-exit` MUST be a non-negative integer. Default 0 if field absent.
- `description` MUST be non-empty.
- `timeout-override` if present MUST be an integer in `[60, 3600]`.

### Example

```yaml
harness-type: plugin-skill
skill-under-test: kiln:kiln-distill
expected-exit: 0
description: "Basic smoke test — distill a 3-item fixture backlog into a PRD with expected frontmatter"
```

---

## 2. TAP v14 output grammar

The harness writes TAP v14 to **stdout**. All other output (logs, verdict reports, scratch snapshots) goes to files or stderr. TAP stdout MUST be deterministic (no UUIDs, no timestamps) so that two runs against unchanged source produce byte-identical output (NFR-003).

### Stream shape (in order)

1. Version line: `TAP version 14\n`
2. Plan line: `1..N\n` where `N` = number of tests discovered.
3. N test-result lines (one per test, in discovery order).
4. No trailing summary line (TAP v14 does not require one).

### Test-result line grammar

**Pass**:
```
ok <N> - <test-name>
```

**Fail**:
```
not ok <N> - <test-name>
  ---
  <yaml-diagnostic-block>
  ...
```

**Inconclusive** (skipped due to malformed metadata or unavailable substrate):
```
ok <N> - <test-name> # SKIP <reason>
```

Exit-code mapping:
- 0 ← every test emitted `ok` and there were no `# SKIP` lines
- 1 ← at least one `not ok` line
- 2 ← at least one `# SKIP` line AND no `not ok` lines

### YAML diagnostic block

Emitted below every `not ok`. Two-space indent, delimited by `---` and `...`.

```yaml
  ---
  classification: "failed" | "stalled" | "paused-exhausted" | "assertion-failed"
  scratch-uuid: "<uuidv4>"
  scratch-retained: "/tmp/kiln-test-<uuid>/"
  verdict-report: ".kiln/logs/kiln-test-<uuid>.md"
  last-transcript-lines: |
    <up to 50 lines, verbatim>
  assertion-stdout: |
    <stdout of assertions.sh if relevant>
  assertion-stderr: |
    <stderr of assertions.sh if relevant>
  ...
```

Fields not relevant to a given failure mode MAY be omitted. `classification` and `scratch-uuid` are REQUIRED on every `not ok`.

### Example

```
TAP version 14
1..2
ok 1 - kiln-distill-basic
not ok 2 - kiln-hygiene-backfill-idempotent
  ---
  classification: "assertion-failed"
  scratch-uuid: "550e8400-e29b-41d4-a716-446655440000"
  scratch-retained: "/tmp/kiln-test-550e8400-e29b-41d4-a716-446655440000/"
  verdict-report: ".kiln/logs/kiln-test-550e8400-e29b-41d4-a716-446655440000.md"
  assertion-stderr: |
    FAIL: second backfill run emitted 3 diff --git lines
  ...
```

---

## 3. Watcher verdict JSON

Emitted by the watcher agent and consumed by `watcher-runner.sh`. The watcher-runner writes the human-readable `.md` verdict report (FR-007) from this JSON.

### Schema

```json
{
  "classification": "healthy" | "paused" | "stalled" | "failed",
  "timestamps": {
    "session_started_iso": "2026-04-24T14:32:11Z",
    "last_scratch_write_iso": "2026-04-24T14:35:02Z",
    "last_transcript_advance_iso": "2026-04-24T14:35:05Z",
    "verdict_emitted_iso": "2026-04-24T14:40:12Z"
  },
  "last_50_lines": [
    "string line 1",
    "string line 2",
    "..."
  ],
  "scratch_uuid": "550e8400-e29b-41d4-a716-446655440000",
  "scratch_files": [
    "relative/path/to/file-1",
    "relative/path/to/file-2"
  ],
  "pause_prompt": "string or null"
}
```

### Field rules

- `classification` is the terminal classification. Intermediate polls that read `healthy` do not emit JSON — only terminal transitions do.
- `timestamps.*` are ISO-8601 UTC strings with `Z` suffix. All four keys are REQUIRED.
- `last_50_lines` is an array of up to 50 most recent transcript lines (stdout+stderr interleaved in source order). If fewer than 50 lines exist, emit what's available.
- `scratch_uuid` is the UUIDv4 without path prefix.
- `scratch_files` is the list of relative paths under the scratch dir at the time of verdict emission.
- `pause_prompt` is REQUIRED when classification is `paused`. The watcher extracts the prompt text from the last 5 transcript lines and includes it verbatim. Otherwise null.

### Classification rules

- `healthy` — subprocess is alive AND (`last_scratch_write_iso` advanced in the last poll tick OR `last_transcript_advance_iso` advanced in the last poll tick).
- `paused` — subprocess is alive AND transcript contains a prompt pattern (regex: `(\?\s*\n\s*\n)|(Waiting for input)|(Press \[Enter\])`) in the last 5 lines AND no advance in scratch writes OR transcript for ≥ 1 poll tick.
- `stalled` — subprocess is alive AND no scratch write AND no transcript advance for ≥ `stall_window` seconds.
- `failed` — subprocess exited non-zero AND this does not match `expected-exit` from `test.yaml`. If subprocess exit matches `expected-exit`, classification is NOT `failed` — the test is evaluated by `assertions.sh`.

---

## 4. Scratch-dir invariants

### Path pattern

```
/tmp/kiln-test-<uuid>/
```

### UUID format

- MUST be UUIDv4 (RFC 4122).
- MUST be lowercase.
- MUST be generated via `uuidgen` and validated against the regex `^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$` before use.

### Collision handling

If `/tmp/kiln-test-<uuid>/` exists at creation time, `scratch-create.sh` MUST regenerate the UUID up to 3 times. On the 4th failure, exit 2 (inconclusive) with diagnostic.

### Cleanup rules

- **On success** (test passed): scratch dir is deleted recursively via `rm -rf`.
- **On failure** (test failed, inconclusive, or watcher terminated): scratch dir is retained; its UUID path MUST appear in the TAP YAML diagnostic block AND the verdict report.
- **On interrupt** (SIGINT/SIGTERM to the harness): scratch dirs are retained for post-mortem; the harness traps the signal, emits a `Bail out!` TAP line with the retained UUID paths, and exits 130.

### Write-boundary invariant

The watcher records every file written under the scratch dir in `scratch_files`. The watcher does NOT directly monitor writes outside the scratch dir (v1 has no sandbox) but the scratch-snapshot at session exit captures the final scratch state for the assertion step. If a skill writes outside the scratch dir, that write is undetected by the harness; NFR-004 only guarantees detection of scratch-dir writes and CWD isolation.

---

## 5. Substrate dispatch interface

### Dispatch signature

```bash
dispatch-substrate.sh <harness-type> <scratch-dir> <test-dir> <plugin-root>
```

| Arg | Type | Meaning |
|-----|------|---------|
| `<harness-type>` | string | Value of `harness-type` from `test.yaml` |
| `<scratch-dir>` | absolute path | `/tmp/kiln-test-<uuid>/` — already created and seeded |
| `<test-dir>` | absolute path | Path to the test directory (contains `test.yaml`, `fixtures/`, `inputs/`, `assertions.sh`) |
| `<plugin-root>` | absolute path | Path to the plugin source tree under test (e.g., `/path/to/repo/plugin-kiln`) |

### Behavior contract

- Dispatches to `plugin-kiln/scripts/harness/substrate-<harness-type>.sh` with the same args.
- V1 switch accepts exactly: `plugin-skill`.
- Unknown `harness-type` → exits 2 with diagnostic `"Substrate '<type>' not implemented in v1"` on stderr.

### Substrate-script contract

Every substrate script MUST:

1. Be invocable as `substrate-<name>.sh <scratch-dir> <test-dir> <plugin-root>` (the dispatcher drops the first arg).
2. Read `inputs/initial-message.txt` from `<test-dir>` (required).
3. Read `inputs/answers.txt` from `<test-dir>` if present (optional; single test that never prompts doesn't need it).
4. Spawn the session with CWD = `<scratch-dir>`, with env `KILN_HARNESS=1` set.
5. Cooperate with the watcher: the watcher polls scratch dir + transcript; the substrate script is responsible ONLY for session spawn, scripted-answer dispatch on `paused` verdicts, and waiting for exit.
6. Return exit code equal to the subprocess's own exit code.

### V1 substrate: `plugin-skill`

```bash
substrate-plugin-skill.sh <scratch-dir> <test-dir> <plugin-root>
```

**Implementation MUST**:

1. Resolve `initial-message` from `<test-dir>/inputs/initial-message.txt`.
2. Call `claude-invoke.sh <plugin-root> <scratch-dir> <test-dir>/inputs/initial-message.txt` to spawn the subprocess.
3. Wire a FIFO or stdin pipe to the subprocess so `watcher-runner.sh` can push scripted answers when it sees `paused`.
4. Wait for subprocess exit; propagate exit code.

---

## 6. Answer-file format

### File

`<test-dir>/inputs/answers.txt`

### Format

- Plain text, UTF-8.
- One answer per line.
- Lines consumed in FIFO order by the watcher-runner when the watcher emits a `paused` verdict.
- Empty lines are meaningful (they count as one "press Enter" answer).
- Comment lines (starting with `#` as the FIRST char) are skipped. A literal `#` answer can be escaped as `\#`.
- Trailing newline is optional.

### Exhaustion

If the watcher emits `paused` AND there are no unconsumed lines remaining, the test fails with classification `paused-exhausted` and diagnostic naming the unanswered prompt (from watcher verdict JSON `pause_prompt`).

### Missing file

If `answers.txt` does not exist AND the watcher emits `paused`, behavior is identical to exhaustion (`paused-exhausted`).

---

## 7. Helper-script interfaces

All helper scripts live under `plugin-kiln/scripts/harness/` and MUST be invoked with absolute paths. All scripts use `set -euo pipefail`. All scripts write TAP only through `tap-emit.sh` — no direct stdout from non-orchestrator scripts.

### 7.1 `fixture-seeder.sh`

```bash
fixture-seeder.sh <test-dir> <scratch-dir>
```

| Arg | Meaning |
|-----|---------|
| `<test-dir>` | Absolute path to the test directory containing `fixtures/` |
| `<scratch-dir>` | Absolute path to an already-created empty scratch dir |

**Behavior**: Recursively copies `<test-dir>/fixtures/*` into `<scratch-dir>/` via `cp -R`. Preserves file modes. If `fixtures/` does not exist, exits 0 (empty fixture is valid). Exit 2 on copy errors.

---

### 7.2 `claude-invoke.sh`

```bash
claude-invoke.sh <plugin-dir> <scratch-dir> <initial-message-file>
```

| Arg | Meaning |
|-----|---------|
| `<plugin-dir>` | Absolute path to the plugin source tree (passed via `--plugin-dir`) |
| `<scratch-dir>` | Absolute path; becomes the subprocess CWD |
| `<initial-message-file>` | Absolute path to a text file whose contents become the `--initial-message` value |

**Behavior**: Spawns `claude --plugin-dir <plugin-dir> --headless --dangerously-skip-permissions --initial-message "$(cat <initial-message-file>)"` with CWD=`<scratch-dir>`, env `KILN_HARNESS=1` set, and stdin wired from its own stdin (so the caller can pipe scripted answers).

**Why this exists**: Per PRD Risk 4, CLI flag names (`--plugin-dir`, `--headless`, `--dangerously-skip-permissions`, `--initial-message`) could drift. Wrapping them in this one helper makes a future flag rename a one-file change. This script MUST document the current flag contract in a header comment.

Exit code: propagates the subprocess exit code.

---

### 7.3 `tap-emit.sh`

```bash
tap-emit.sh <test-number> <test-name> <status> [diagnostic-yaml-file]
```

| Arg | Meaning |
|-----|---------|
| `<test-number>` | Positive integer, 1-indexed |
| `<test-name>` | Test name (directory basename). Must not contain newlines |
| `<status>` | One of `pass`, `fail`, `skip` |
| `<diagnostic-yaml-file>` | OPTIONAL; required when status is `fail`. Absolute path to a file containing the YAML diagnostic block BODY (without the `---`/`...` delimiters or the 2-space indent; tap-emit.sh adds those) |

**Behavior**:
- `pass` → emits `ok <N> - <test-name>\n`
- `fail` → emits `not ok <N> - <test-name>\n` followed by the indented/delimited YAML block
- `skip` → emits `ok <N> - <test-name> # SKIP <first-line-of-diagnostic-file>\n`

Writes to stdout only. Does NOT write to stderr.

---

### 7.4 `scratch-snapshot.sh`

```bash
scratch-snapshot.sh <scratch-dir> <output-path>
```

| Arg | Meaning |
|-----|---------|
| `<scratch-dir>` | Absolute path to scratch dir |
| `<output-path>` | Absolute path where the snapshot file is written |

**Behavior**: Runs `find <scratch-dir> -type f` (relative paths), then for each file appends one line to `<output-path>`:

```
<sha256-hex>  <relative-path>
```

Format matches `sha256sum` output so the file is diff-friendly. Lines sorted by path (stable ordering). Exit 0 on success; exit 1 if `<scratch-dir>` does not exist.

---

### 7.5 `scratch-create.sh`

```bash
scratch-create.sh
```

No arguments. Generates a UUIDv4, creates `/tmp/kiln-test-<uuid>/`, and prints the absolute path to stdout. Retries on collision up to 3 times; exit 2 on the 4th failure.

---

### 7.6 `test-yaml-validate.sh`

```bash
test-yaml-validate.sh <test-yaml-path>
```

**Behavior**: Validates `<test-yaml-path>` against section 1 schema. Exit 0 on pass. Exit 2 on schema violation, with stderr diagnostic naming the first failing field.

---

### 7.7 `config-load.sh`

```bash
config-load.sh <repo-root>
```

**Behavior**: Reads `<repo-root>/.kiln/test.config` if present; emits key=value lines to stdout for eval-consumption:

```
discovery_path=plugin-*/tests
watcher_stall_window_seconds=300
watcher_poll_interval_seconds=30
```

Missing file → emits defaults. Missing keys → fills with defaults. Unknown keys → passed through verbatim (forward-compat).

**Defaults**:
- `discovery_path=plugin-<name>/tests` (where `<name>` is resolved by the caller, not this script)
- `watcher_stall_window_seconds=300`
- `watcher_poll_interval_seconds=30`

---

### 7.8 `dispatch-substrate.sh`

See section 5 above.

---

### 7.9 `watcher-runner.sh`

```bash
watcher-runner.sh <scratch-dir> <subprocess-pid> <stdin-fifo> <test-yaml> <output-verdict-json> <output-verdict-md>
```

**Behavior**: Spawns the `test-watcher` agent (haiku) via the Task tool, polls every `watcher_poll_interval_seconds`, and on terminal classification (`paused` / `stalled` / `failed`) emits verdict JSON to `<output-verdict-json>` AND writes the human-readable verdict report to `<output-verdict-md>` (FR-007). On `paused`, reads next line from `<test-dir>/inputs/answers.txt` and writes to `<stdin-fifo>` so the substrate script forwards it to the subprocess.

---

### 7.10 `watcher-poll.sh`

```bash
watcher-poll.sh <scratch-dir> <subprocess-pid> <transcript-path>
```

Emits current snapshot JSON to stdout (scratch mtime, transcript tail, PID status). Called by `watcher-runner.sh` on each poll tick. Not directly user-invoked.

---

### 7.11 `kiln-test.sh` (top-level orchestrator)

```bash
kiln-test.sh [plugin-name] [test-name]
```

Invocation forms:
- No args → auto-detect plugin from CWD (FR-001 form a)
- `<plugin-name>` → run all tests for that plugin (form b)
- `<plugin-name> <test-name>` → run single test (form c)

**Behavior**: Resolves plugin root, loads config, discovers tests, emits TAP header, loops over tests (fixture-seed → scratch-create → dispatch-substrate + watcher-runner in parallel → assertions.sh → tap-emit → cleanup or retain). Aggregates exit code per section 2.

---

## 8. Environment variable contract

| Variable | Set By | Meaning |
|----------|--------|---------|
| `KILN_HARNESS` | substrate driver (FR-011) | `1` when the skill is running inside the harness. Skills MAY check this to skip interactive-only features. |
| `KILN_TEST_SCRATCH_DIR` | harness orchestrator | Absolute path to current test's scratch dir. Exposed to `assertions.sh`. |
| `KILN_TEST_VERDICT_JSON` | harness orchestrator | Absolute path to the watcher's verdict JSON. Exposed to `assertions.sh`. |
| `KILN_TEST_NAME` | harness orchestrator | Current test directory basename. Exposed to `assertions.sh`. |

`assertions.sh` is invoked with CWD = scratch-dir and inherits these three `KILN_TEST_*` env vars (plus `KILN_HARNESS=1`). Exit code 0 = pass; non-zero = fail (and assertion stdout/stderr captured into YAML diagnostic block).

---

## 9. `.kiln/logs/` outputs

Per test invocation, the harness produces:

- `.kiln/logs/kiln-test-<uuid>.md` — human-readable verdict report (from watcher verdict JSON)
- `.kiln/logs/kiln-test-<uuid>-scratch.txt` — scratch-dir file-list + sha256sums

Both files are retained regardless of pass/fail. The retained scratch DIR is separate and is only kept on fail.

---

## 10. Versioning of this contract

This contract is v1. If any of the above signatures changes (breaking YAML schema field, new required field, changed exit-code semantics, changed TAP shape, changed script arg order), the plan.md MUST be updated first and the contract version bumped to v2. Additive changes (new optional fields, new substrate entries in the dispatch switch) are non-breaking and do not require a version bump.
