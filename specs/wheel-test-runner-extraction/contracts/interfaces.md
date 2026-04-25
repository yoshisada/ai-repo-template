# Interface Contracts: Wheel Test Runner Extraction

**Spec**: `specs/wheel-test-runner-extraction/spec.md`
**Plan**: `specs/wheel-test-runner-extraction/plan.md`
**Article VII compliance**: All exported entrypoints below are pinned with exact CLI / function signatures, exit codes, output paths, and (for the snapshot-diff comparator) the per-fixture exclusion contract.

This document is the single source of truth. Implementer MUST match these signatures exactly. If any signature needs to change, update this contract FIRST.

---

## §1 — `wheel-test-runner.sh` (top-level entrypoint)

**Path**: `plugin-wheel/scripts/harness/wheel-test-runner.sh`
**Renamed from**: `plugin-kiln/scripts/harness/kiln-test.sh`
**Type**: Bash 5.x executable script (not a sourced library function)
**Sync/async**: Synchronous (blocks until all tests complete)

### CLI signature (FR-R1-3)

```
wheel-test-runner.sh                              # Form A: auto-detect plugin
wheel-test-runner.sh <plugin-name>                # Form B: run all tests for plugin
wheel-test-runner.sh <plugin-name> <test-name>    # Form C: run a single test
```

| Argument | Type | Required | Description |
|---|---|---|---|
| `<plugin-name>` | string | optional | Plugin directory name (without `plugin-` prefix). Auto-detected when omitted. |
| `<test-name>` | string | optional | Single test directory basename under `plugin-<plugin-name>/tests/`. |

**Argument count validation**:
- 0 args → Form A (auto-detect)
- 1 arg → Form B
- 2 args → Form C
- ≥3 args → `Bail out! too many arguments: expected 0, 1, or 2 (got N)`, exit 2

### Environment variable inputs

| Var | Required | Default | Description |
|---|---|---|---|
| `KILN_TEST_REPO_ROOT` | optional | `$(pwd)` | Repo root for plugin discovery (FR-R1-6 — name preserved as back-compat fossil per NFR-R-7). |

**No new environment variables introduced.** Renaming `KILN_TEST_REPO_ROOT` → `WHEEL_TEST_REPO_ROOT` is FORBIDDEN by NFR-R-7 (would break consumer overrides).

### Stdout (FR-R1-5)

TAP v14 stream. Byte-identical to pre-PRD `kiln-test.sh` output (modulo timestamps in YAML diagnostic blocks):

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

Bail-out form (fatal error):

```
Bail out! <human-readable diagnostic>
```

### Stderr

Diagnostics, warnings, and substrate-internal traces. NOT part of the TAP stream contract — no consumer parses stderr structurally.

### Exit codes (FR-R1-3)

| Code | Meaning |
|---|---|
| `0` | All tests passed |
| `1` | At least one test failed (TAP `not ok ...`) |
| `2` | At least one test was inconclusive (`# SKIP <reason>`) AND no tests failed |

When both fails and skips are present, exit code is `1` (fail wins per `kiln-test.sh:357-362`).

### Output paths (FR-R1-4 / NFR-R-7)

| Path | Description |
|---|---|
| `.kiln/logs/kiln-test-<uuid>.md` | Verdict report (markdown). Path prefix `kiln-test-` is a back-compat fossil. |
| `.kiln/logs/kiln-test-<uuid>-transcript.ndjson` | Per-test transcript stream-json envelopes. |
| `.kiln/logs/kiln-test-<uuid>-scratch.txt` | Scratch-dir snapshot summary. |
| `.kiln/logs/kiln-test-<uuid>-verdict.json` | Watcher verdict JSON. |
| `/tmp/kiln-test-<uuid>/` | Scratch directory. Retained on failure; removed on pass. |

`<uuid>` is generated via `uuidgen` (one per test run, NOT per test in a multi-test run).

### Internal helper resolution

`wheel-test-runner.sh` resolves sibling helpers via:

```bash
harness_dir=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
```

(Pattern preserved verbatim from `kiln-test.sh:30`.) All sibling helpers (`watcher-runner.sh`, `dispatch-substrate.sh`, etc.) are invoked via `"$harness_dir/<helper>.sh"`. Post-move, all 12 scripts live at `plugin-wheel/scripts/harness/` so `harness_dir` resolution works without edits.

### Backward-compat invariants (NFR-R-3)

- Exit codes by input MUST match pre-PRD `kiln-test.sh` exactly.
- TAP v14 stdout shape MUST be byte-identical (modulo timestamps).
- Verdict-report contents MUST be byte-identical per the `§3` per-fixture exclusion comparator.
- `KILN_TEST_REPO_ROOT` env var name MUST be preserved.
- Scratch-dir prefix `/tmp/kiln-test-` MUST be preserved.
- Verdict-report path prefix `.kiln/logs/kiln-test-` MUST be preserved.

---

## §2 — `/kiln:kiln-test` SKILL.md façade (FR-R2)

**Path**: `plugin-kiln/skills/kiln-test/SKILL.md`
**Type**: Skill markdown (not an executable; runtime executes the documented bash command)

### Pre-PRD shape (frozen)

Line 31 (the bash invocation):

```bash
bash "${WORKFLOW_PLUGIN_DIR}/scripts/harness/kiln-test.sh" $ARGUMENTS
```

Line 10 (the preamble):

```
**Non-negotiable**: this skill MUST delegate to `${WORKFLOW_PLUGIN_DIR}/scripts/harness/kiln-test.sh` (NFR-001 portability). No repo-relative `plugin-kiln/scripts/...` path may appear in this file. The harness scripts resolve to the plugin's install path automatically via `${WORKFLOW_PLUGIN_DIR}`.
```

### Post-PRD shape (FR-R2-1)

Line 31:

```bash
bash "${WORKFLOW_PLUGIN_DIR}/../plugin-wheel/scripts/harness/wheel-test-runner.sh" $ARGUMENTS
```

Line 10:

```
**Non-negotiable**: this skill MUST delegate to `${WORKFLOW_PLUGIN_DIR}/../plugin-wheel/scripts/harness/wheel-test-runner.sh` (NFR-001 portability + sibling-plugin resolution per spec OQ-R-1). No repo-relative `plugin-kiln/scripts/...` or `plugin-wheel/scripts/...` path may appear in this file. The harness scripts resolve to the plugin's install path automatically via `${WORKFLOW_PLUGIN_DIR}` + sibling-traversal.
```

### Resolution discipline rationale (OQ-R-1)

`${WORKFLOW_PLUGIN_DIR}` resolves at runtime to the kiln plugin's install dir:

- **Source repo**: `/<repo>/plugin-kiln/` → sibling `../plugin-wheel/scripts/harness/wheel-test-runner.sh` → `/<repo>/plugin-wheel/scripts/harness/wheel-test-runner.sh` ✓
- **Consumer install**: `~/.claude/plugins/cache/<org>-<mp>/plugin-kiln/<version>/` → sibling `../plugin-wheel/scripts/harness/wheel-test-runner.sh` → `~/.claude/plugins/cache/<org>-<mp>/plugin-wheel/scripts/harness/wheel-test-runner.sh` ✓ (versioned-sibling layout — Claude Code installs sibling plugins as siblings under the same `<org>-<mp>/` cache root)

Both layouts validated by the consumer-install smoke pattern at `plugin-wheel/tests/workflow-plugin-dir-bg/run.sh` (PR #168 / FR-D1..D4 of wheel-as-runtime).

### Skill prose (FR-R2-2 — UNCHANGED)

Everything else in `SKILL.md` stays verbatim:

- "When to invoke" section
- "Three invocation forms" table
- "Writing a new test" section (test.yaml schema, fixtures/inputs/assertions.sh layout)
- Env-var documentation (`KILN_HARNESS=1`, `KILN_TEST_SCRATCH_DIR`, `KILN_TEST_NAME`, `KILN_TEST_VERDICT_JSON`)
- `.kiln/test.config` overrides documentation
- Dependencies section
- "What this harness does NOT do" section
- Related links

---

## §3 — Snapshot-diff comparator (NFR-R-8 / R-R-3 mitigation)

**Path**: `plugin-wheel/scripts/harness/snapshot-diff.sh`
**Type**: Bash 5.x executable script
**Purpose**: Byte-identity comparator with per-fixture exclusion contract. Implements the SC-R-1 verification.

### CLI signature

```
snapshot-diff.sh <mode> <baseline-path> <candidate-path>
```

| Argument | Type | Required | Description |
|---|---|---|---|
| `<mode>` | enum: `bats` \| `verdict-report` \| `verdict-report-deterministic` | yes | Per-fixture exclusion mode |
| `<baseline-path>` | path | yes | Pre-PRD baseline file |
| `<candidate-path>` | path | yes | Post-PRD candidate file (same shape) |

### Modes

#### Mode `bats`

For pure-deterministic bats TAP output (e.g., `preprocess-substitution.bats-pre-prd.md`).

**Exclusion regex** (applied to BOTH baseline and candidate before diff):

```
# (Empty exclusion list — bats output is fully deterministic.)
```

**Diff command** (after exclusion normalization):

```bash
diff -u "$baseline_normalized" "$candidate_normalized"
```

**Exit codes**:
- `0` — byte-identical
- `1` — differences found (delta lines emitted to stdout)
- `2` — usage / file-not-found error (stderr diagnostic)

#### Mode `verdict-report`

For LLM-stochastic kiln-test verdict reports (e.g., `kiln-distill-basic-pre-prd.md`).

**Section-level exclusion** (per researcher reconciliation directive #2):

The comparator splits each file at the literal section header:

```
## Last 50 transcript envelopes
```

Everything before this header is the **framing** (deterministic post-modulo). Everything from the header onward (inclusive) is the **stochastic body** and is replaced with a single placeholder line `<TRANSCRIPT-BODY-EXCLUDED>` before diff.

**Line-level exclusion regex** (applied to the framing portion of both baseline and candidate):

```
# Timestamps (ISO-8601 forms used by the harness):
^.*\b\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}([.,]\d+)?(Z|[+-]\d{2}:?\d{2})?\b.*$  → <TIMESTAMP>
# UUIDs:
\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\b  → <UUID>
# Absolute scratch-dir paths:
/tmp/kiln-test-<UUID>(/[^[:space:]]*)?  → /tmp/kiln-test-<UUID>
# Absolute repo-root paths (caller-dependent):
/Users/[^/]+/[^[:space:]]*  → <ABS-PATH>
```

After exclusion normalization, `diff -u` between framing portions. Stochastic body is excluded entirely from the diff (replaced with placeholder before diff runs).

**Exit codes**: same as mode `bats`.

#### Mode `verdict-report-deterministic`

For fast-deterministic plugin-skill fixtures whose output is fully reproducible (no LLM call inside the assertions.sh — e.g., the implementer's chosen synthetic fixture).

**Line-level exclusion regex** (applied to BOTH baseline and candidate):

Same regex as `verdict-report` mode (timestamps, UUIDs, abs paths) — but NO section-level body exclusion (the entire file is treated as framing).

After exclusion normalization, `diff -u` end-to-end.

**Exit codes**: same as mode `bats`.

### Reference implementation outline

```bash
#!/usr/bin/env bash
# snapshot-diff.sh — per-fixture byte-identity comparator. Pin per spec NFR-R-8.
set -euo pipefail

mode=$1; baseline=$2; candidate=$3
[[ -f $baseline ]] || { echo "baseline not found: $baseline" >&2; exit 2; }
[[ -f $candidate ]] || { echo "candidate not found: $candidate" >&2; exit 2; }

normalize() {
  local file=$1 mode=$2
  case $mode in
    bats)
      cat "$file"
      ;;
    verdict-report)
      # Split at section header; emit framing + placeholder.
      awk '/^## Last 50 transcript envelopes\s*$/ { print; print "<TRANSCRIPT-BODY-EXCLUDED>"; exit } { print }' "$file" \
        | sed -E \
            -e 's/[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}([.,][0-9]+)?(Z|[+-][0-9]{2}:?[0-9]{2})?/<TIMESTAMP>/g' \
            -e 's/[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/<UUID>/g' \
            -e 's|/tmp/kiln-test-<UUID>(/[^[:space:]]*)?|/tmp/kiln-test-<UUID>|g' \
            -e 's|/Users/[^/]+/[^[:space:]]*|<ABS-PATH>|g'
      ;;
    verdict-report-deterministic)
      sed -E \
        -e 's/[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}([.,][0-9]+)?(Z|[+-][0-9]{2}:?[0-9]{2})?/<TIMESTAMP>/g' \
        -e 's/[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/<UUID>/g' \
        -e 's|/tmp/kiln-test-<UUID>(/[^[:space:]]*)?|/tmp/kiln-test-<UUID>|g' \
        -e 's|/Users/[^/]+/[^[:space:]]*|<ABS-PATH>|g' \
        "$file"
      ;;
    *)
      echo "unknown mode: $mode (expected bats | verdict-report | verdict-report-deterministic)" >&2
      exit 2
      ;;
  esac
}

diff -u <(normalize "$baseline" "$mode") <(normalize "$candidate" "$mode")
```

### Per-fixture mode mapping

| Fixture | Baseline file | Mode |
|---|---|---|
| `plugin-wheel/tests/preprocess-substitution.bats` | `specs/wheel-test-runner-extraction/research/baseline-snapshot/preprocess-substitution.bats-pre-prd.md` | `bats` |
| `plugin-kiln/tests/kiln-distill-basic/` | `specs/wheel-test-runner-extraction/research/baseline-snapshot/kiln-distill-basic-pre-prd.md` | `verdict-report` |
| Implementer-chosen fast-deterministic plugin-skill fixture | TBD by implementer | `verdict-report-deterministic` |

The third fixture is implementer's choice; it MUST be a fast (≤30s) deterministic plugin-skill fixture whose verdict report is reproducible across runs. If no such fixture exists in the current `plugin-kiln/tests/` set, the implementer MAY author one as part of this PRD's deliverables (small, pure-bash assertions, no LLM-stochastic content) — but this is OPTIONAL and not a blocker (skip the third snapshot-diff verification with a documented note in `agent-notes/implementer.md`).

---

## §4 — Snapshot-diff exclusion regex (canonical reference)

This is the SINGLE pinned regex for line-level exclusions (R-R-3 mitigation). DO NOT introduce variants in fixture-level run.sh files; ALL snapshot-diffs invoke `snapshot-diff.sh` per `§3`.

```regex
# Timestamp:
[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}([.,][0-9]+)?(Z|[+-][0-9]{2}:?[0-9]{2})?

# UUID v4:
[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}

# Absolute scratch-dir paths:
/tmp/kiln-test-<UUID>(/[^[:space:]]*)?

# Absolute user-home paths (caller-dependent):
/Users/[^/]+/[^[:space:]]*
```

Replacement tokens: `<TIMESTAMP>`, `<UUID>`, `/tmp/kiln-test-<UUID>` (kept as a stable token), `<ABS-PATH>`.

If the auditor finds the regex misses a stochastic field that fires false-positive, the regex MUST be updated HERE FIRST (this contract), then in `snapshot-diff.sh`. Do not hand-edit fixture-level diffs.

---

## §5 — Internal helper invariants (for implementer reference)

The following are NOT exported entrypoints (not consumed by external callers) but ARE internal contracts that the runner depends on. Pinning them so the implementer doesn't accidentally break inter-helper coupling during the move.

| Helper | Caller | Invariant |
|---|---|---|
| `config-load.sh` | `wheel-test-runner.sh` line 119 | Outputs `eval`-able variable assignments; substitutes `<name>` placeholder in `discovery_path` |
| `tap-emit.sh` | `wheel-test-runner.sh` lines 211, 224, 230, 236, 245, 291, 309, 341, 351 | Args: `<index> <name> <pass|fail|skip> [diag-file]`; emits one TAP line + optional YAML block |
| `test-yaml-validate.sh` | `wheel-test-runner.sh` line 206 | Args: `<test.yaml>`; exit 0 = valid, exit non-zero = invalid + stderr diagnostic |
| `scratch-create.sh` | `wheel-test-runner.sh` line 234 | Stdout: absolute scratch-dir path; uses `mktemp -d /tmp/kiln-test-<uuid>.XXXXXX` (or equivalent) |
| `fixture-seeder.sh` | `wheel-test-runner.sh` line 243 | Args: `<test_dir> <scratch_dir>`; copies `fixtures/` contents into scratch dir |
| `dispatch-substrate.sh` | `wheel-test-runner.sh` line 270 | Args: `<harness_type> <scratch_dir> <test_dir> <plugin_root>`; spawns substrate subprocess |
| `watcher-runner.sh` | `wheel-test-runner.sh` line 273 | Args: `<scratch_dir> <substrate_pid> <transcript_path> <test_yaml> <verdict_json> <verdict_md>`; foregrounds the watcher classifier |
| `claude-invoke.sh` | called by `dispatch-substrate.sh` / `substrate-plugin-skill.sh` | Spawns `claude --print --verbose --input-format=stream-json --output-format=stream-json --dangerously-skip-permissions --plugin-dir <plugin_root>` |

**Move-time invariant**: All inter-helper invocations use `"$harness_dir/<helper>.sh"`. Post-move, `$harness_dir` resolves to `plugin-wheel/scripts/harness/`; sibling resolution requires no edits.

---

## §6 — Non-kiln consumability fixture contract (FR-R3)

**Path**: `plugin-wheel/tests/wheel-test-runner-direct/run.sh`
**Type**: Bash 5.x executable script (run.sh-only fixture pattern)

### CLI signature

```
bash plugin-wheel/tests/wheel-test-runner-direct/run.sh
```

No arguments. CWD-independent (resolves repo root via `${BASH_SOURCE[0]}` if needed).

### Stdout

PASS/FAIL summary lines. Final line MUST be one of:

```
PASS: wheel-test-runner-direct (N/N assertions passed)
FAIL: wheel-test-runner-direct (M/N assertions failed)
```

### Exit codes

- `0` — all assertions passed
- non-zero — at least one assertion failed (exact code is implementer's choice)

### Required assertions (FR-R3-1)

1. **Form A (auto-detect plugin)** — invoke `bash plugin-wheel/scripts/harness/wheel-test-runner.sh` with no args (in a temp scratch CWD with one `plugin-foo/` sibling); assert exit code matches expected; assert TAP `1..0` or `1..N` shape on stdout.
2. **Form B (`<plugin>`)** — invoke `bash plugin-wheel/scripts/harness/wheel-test-runner.sh <plugin>` for a known small plugin (e.g., `plugin-kiln`); assert TAP stdout structure.
3. **Form C (`<plugin> <test>`)** — invoke `bash plugin-wheel/scripts/harness/wheel-test-runner.sh <plugin> <test>` for a single deterministic test; assert exit code + verdict-report path written.
4. **`KILN_TEST_REPO_ROOT` honored** — invoke with `KILN_TEST_REPO_ROOT=<temp-dir> bash <runner>`; assert plugin-discovery uses the temp dir (FR-R1-6).
5. **`Bail out!` on bad input** — invoke `bash <runner> nonexistent-plugin`; assert TAP `Bail out!` line + exit 2.

### Non-kiln-coupling invariant (FR-R3-2)

`git grep -nF 'plugin-kiln/' plugin-wheel/tests/wheel-test-runner-direct/run.sh` MUST return zero matches. Implementer MAY reference `plugin-kiln/tests/<fixture>/` from the fixture's TEST INPUT (it's fine to USE a kiln fixture as input data) — but the run.sh itself, the shebang/imports/sourced libs, MUST NOT depend on kiln being installed. Caveat: if the run.sh invokes `wheel-test-runner.sh <plugin> <test>` where `<plugin>` is `kiln`, that's acceptable as an INPUT to the runner — the runner is still consumed without `plugin-kiln/scripts/` in its call chain.

If pure non-kiln invocation is impractical (no synthetic standalone fixture available without an LLM call), document the trade-off in `agent-notes/implementer.md` and use a deterministic plugin-skill fixture as input — the FR-R3-2 invariant becomes "no `plugin-kiln/scripts/` reference" rather than "no `plugin-kiln/` reference at all." Implementer judgment.

### Mutation tripwire (NFR-R-2)

The fixture's run.sh MUST include a comment block describing how an intentional mutation (e.g., adding a stray space character to `wheel-test-runner.sh`'s `printf 'TAP version 14\n'` line) would cause the assertions to fail. Documented for the auditor; not a runtime test.

---

## Article VII Compliance Summary

Every exported entrypoint in this PRD has a pinned signature in this contract:

| Surface | Section | Sign-off |
|---|---|---|
| `wheel-test-runner.sh` (CLI + exit codes + output paths) | §1 | ✓ |
| `/kiln:kiln-test` SKILL.md façade (script-resolution pattern) | §2 | ✓ |
| `snapshot-diff.sh` (CLI + 3 modes + exclusion regex) | §3 | ✓ |
| Snapshot-diff exclusion regex (canonical) | §4 | ✓ |
| Internal helper invariants (move-time discipline) | §5 | ✓ |
| `wheel-test-runner-direct/run.sh` fixture (CLI + assertions + tripwire) | §6 | ✓ |

If implementer needs to deviate from any signature, update this contract FIRST and notify the specifier via SendMessage.
