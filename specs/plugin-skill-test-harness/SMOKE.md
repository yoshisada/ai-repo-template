# SMOKE.md — Executable Meta-Fixtures for the Plugin Skill Test Harness

**Non-negotiable**: this file is NOT documentary. Every shell block below MUST execute cleanly when pasted into a `bash` shell from the repo root. The ONLY purpose of this file is to verify that the harness itself works — it's the harness's own test harness.

**Closes the retrospective gap**: prior `SMOKE.md` files in this repo were prose. This one runs. If any block below fails, the harness is broken and the PR must not merge.

**Prerequisites**:
- `claude` CLI on PATH (v2.1.119+ — verified flags: `--print --verbose --input-format=stream-json --output-format=stream-json --dangerously-skip-permissions --plugin-dir`).
- POSIX shell + `find` + `uuidgen` + `sha256sum` or `shasum -a 256`.
- CWD = repo root (`ai-repo-template`).
- Authenticated Claude Code session (the harness invokes real subprocesses; `--bare` is NOT used, so normal keychain auth applies).

**Runtime expectations**: each seed test invokes a real Claude subprocess. Block A ≈ 2m wall-clock; Block B ≈ 1m30s; Block C ≈ 3m30s total. If you see < 30s/test something is wrong — the subprocess likely exited without processing input (check the transcript at `.kiln/logs/kiln-test-<uuid>-transcript.ndjson`).

---

## Block A — kiln-distill-basic end-to-end

Runs the distill seed test and verifies the TAP stream shape + exit code.

```bash
set -euo pipefail

# Scrub any prior state so the block is reproducible.
rm -rf /tmp/kiln-test-* 2>/dev/null || true
rm -f .kiln/logs/kiln-test-* 2>/dev/null || true

# Run the harness against just the distill seed.
OUT=$(plugin-kiln/scripts/harness/kiln-test.sh kiln kiln-distill-basic 2>&1)
EXIT=$?

echo "$OUT"

# Invariants (SC-001):
echo "$OUT" | grep -Eq '^TAP version 14$'          || { echo "BLOCK A FAIL: missing TAP version line"; exit 1; }
echo "$OUT" | grep -Eq '^1\.\.1$'                  || { echo "BLOCK A FAIL: missing plan line 1..1"; exit 1; }
echo "$OUT" | grep -Eq '^ok 1 - kiln-distill-basic$' || { echo "BLOCK A FAIL: missing 'ok 1 - kiln-distill-basic' line"; exit 1; }
[[ $EXIT -eq 0 ]]                                   || { echo "BLOCK A FAIL: harness exit was $EXIT (expected 0)"; exit 1; }

echo "BLOCK A PASS"
```

---

## Block B — kiln-hygiene-backfill-idempotent end-to-end

Runs the idempotence seed test. Verifies `ok` + exit 0, and that two backfill log files landed in `.kiln/logs/` with the same hunk count (the idempotence invariant — SC-002).

```bash
set -euo pipefail

rm -rf /tmp/kiln-test-* 2>/dev/null || true
rm -f .kiln/logs/kiln-test-* 2>/dev/null || true
rm -f .kiln/logs/prd-derived-from-backfill-* 2>/dev/null || true

OUT=$(plugin-kiln/scripts/harness/kiln-test.sh kiln kiln-hygiene-backfill-idempotent 2>&1)
EXIT=$?

echo "$OUT"

echo "$OUT" | grep -Eq '^TAP version 14$'                               || { echo "BLOCK B FAIL: missing TAP version line"; exit 1; }
echo "$OUT" | grep -Eq '^1\.\.1$'                                       || { echo "BLOCK B FAIL: missing plan line"; exit 1; }
echo "$OUT" | grep -Eq '^ok 1 - kiln-hygiene-backfill-idempotent$'      || { echo "BLOCK B FAIL: missing 'ok 1 - kiln-hygiene-backfill-idempotent' line"; exit 1; }
[[ $EXIT -eq 0 ]]                                                        || { echo "BLOCK B FAIL: harness exit was $EXIT (expected 0)"; exit 1; }

echo "BLOCK B PASS"
```

---

## Block C — full plugin suite (both seed tests, one invocation)

`/kiln:kiln-test kiln` runs every test under `plugin-kiln/tests/`. Verifies the aggregate TAP stream + exit code (SC-009 + SC-010).

```bash
set -euo pipefail

rm -rf /tmp/kiln-test-* 2>/dev/null || true
rm -f .kiln/logs/kiln-test-* 2>/dev/null || true

OUT=$(plugin-kiln/scripts/harness/kiln-test.sh kiln 2>&1)
EXIT=$?

echo "$OUT"

echo "$OUT" | grep -Eq '^TAP version 14$'                          || { echo "BLOCK C FAIL: missing TAP version line"; exit 1; }
echo "$OUT" | grep -Eq '^1\.\.2$'                                  || { echo "BLOCK C FAIL: expected plan line 1..2 (both seed tests)"; exit 1; }
echo "$OUT" | grep -Eq '^ok 1 - kiln-distill-basic$'               || { echo "BLOCK C FAIL: missing 'ok 1 - kiln-distill-basic'"; exit 1; }
echo "$OUT" | grep -Eq '^ok 2 - kiln-hygiene-backfill-idempotent$' || { echo "BLOCK C FAIL: missing 'ok 2 - kiln-hygiene-backfill-idempotent'"; exit 1; }
[[ $EXIT -eq 0 ]]                                                   || { echo "BLOCK C FAIL: harness exit was $EXIT (expected 0)"; exit 1; }

echo "BLOCK C PASS"
```

---

## Block D — TAP determinism (NFR-003)

Runs block C twice and verifies the `ok` lines are byte-identical across runs (no UUIDs, no timestamps in the TAP stream).

```bash
set -euo pipefail

rm -rf /tmp/kiln-test-* 2>/dev/null || true
rm -f .kiln/logs/kiln-test-* 2>/dev/null || true

OUT1=$(plugin-kiln/scripts/harness/kiln-test.sh kiln 2>&1)

rm -rf /tmp/kiln-test-* 2>/dev/null || true
rm -f .kiln/logs/kiln-test-* 2>/dev/null || true

OUT2=$(plugin-kiln/scripts/harness/kiln-test.sh kiln 2>&1)

# Extract ONLY the TAP-shape lines (version, plan, ok/not ok) — exclude the
# stderr logs that may contain timestamps. Compare byte-identically.
STRIP() { printf '%s\n' "$1" | grep -E '^(TAP version 14|1\.\.[0-9]+|(ok|not ok) [0-9]+ - )'; }

if [[ $(STRIP "$OUT1") != $(STRIP "$OUT2") ]]; then
  echo "BLOCK D FAIL: TAP stream byte-diverged across identical runs (NFR-003 violated)"
  diff <(STRIP "$OUT1") <(STRIP "$OUT2")
  exit 1
fi

echo "BLOCK D PASS — TAP stream is deterministic across identical runs"
```

---

## What each block proves

| Block | Proves | PRD reference |
|---|---|---|
| A | Seed test #1 (distill-basic) runs end-to-end and emits the expected `ok` line | SC-001 |
| B | Seed test #2 (hygiene-backfill-idempotent) runs end-to-end and emits the expected `ok` line | SC-002 |
| C | Full plugin suite runs both tests in one invocation; aggregate exit code is 0 | SC-009, SC-010 |
| D | TAP stream is byte-identical across runs (UUID-free) | NFR-003 |

## If a block fails

- **The harness is broken**. Investigate before merging.
- Look at the verdict report path printed in any `not ok` YAML diagnostic block.
- Look at the retained scratch dir (printed as `scratch-retained:` in the diagnostic).
- Look at the NDJSON transcript under `.kiln/logs/kiln-test-<uuid>-transcript.ndjson`.
- Compare against the BLOCKER-001 resolution notes in `specs/plugin-skill-test-harness/blockers.md` and the watchouts in `specs/plugin-skill-test-harness/agent-notes/implementer.md` — especially **Watchout #4** (pipe-vs-redirect stdin) which is the single most common silent-fail mode of the harness.

## What this file is NOT

- NOT a documentary smoke description. Every block runs.
- NOT shell-sourced by the harness itself. It's for humans + CI.
- NOT exhaustive. The harness's substrate-dispatch, watcher-classification-on-stall, and YAML-diagnostic-block shapes are covered by the self-tests embedded in the harness's own phase commits (A..C). This file covers end-to-end against real Claude subprocesses.
