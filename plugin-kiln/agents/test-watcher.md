---
name: test-watcher
description: "Classifier agent for the /kiln:kiln-test harness. Polls a running test's scratch dir + NDJSON transcript and classifies session state (healthy / stalled / failed). Used by plugin-kiln/scripts/harness/watcher-runner.sh. Haiku-model — classification is cheap, generation is not the job."
model: haiku
---

# test-watcher

**Role**: Classify the state of a running kiln-test session based on scratch-dir activity, NDJSON transcript advancement, and subprocess liveness. The classification drives termination (no hard timeouts — FR-008).

**Scope**: One invocation per test. Not shared across tests (no cross-test state).

**Contract**: `specs/plugin-skill-test-harness/contracts/interfaces.md` §3 (verdict JSON schema + classification rules) + §7.9 (watcher-runner interface) + §7.10 (poll snapshot).

## V1 implementation note

The watcher classification rules in contracts §3 are purely mechanical: timestamps of last scratch write + last NDJSON envelope advance + subprocess PID status. Pure-bash implementation in `watcher-runner.sh` applies these rules directly without spawning an LLM. This agent spec exists as (a) the authoritative documentation of the classification rules and (b) the extension point for a future LLM-assisted classifier when rule-based triage proves insufficient (e.g., semantic distinction between "genuinely stalled" and "expensive long-running tool-use").

If the v1 bash implementation is working correctly, this agent file is read by humans and audit tools but not actually spawned via the Task tool.

## Classifications

Per contracts/interfaces.md §3:

- **`healthy`** — subprocess alive AND (scratch-dir wrote a file since the last poll tick OR the NDJSON transcript gained a new envelope since the last poll tick).
- **`stalled`** — subprocess alive AND no scratch write AND no NDJSON envelope advance for ≥ `stall_window` seconds. Default `stall_window = 300s` (plan.md D3); overridable via `.kiln/test.config` (`watcher_stall_window_seconds`) or per-test via `test.yaml` key `timeout-override`.
- **`failed`** — subprocess exited with a code that doesn't match `expected-exit` from `test.yaml`, OR emitted a `{"type":"result",...}` NDJSON envelope with `"is_error": true` whose exit doesn't match `expected-exit`. Exit matching `expected-exit` is NOT `failed` — assertions.sh decides those cases.

The `paused` classification has been removed (plan.md D6 rev 2026-04-23); scripted answers are queued up-front by `claude-invoke.sh` so mid-session answer injection is out of scope for v1.

## Poll cadence

Default `poll_interval = 30s` (plan.md D3). Overridable via `.kiln/test.config` (`watcher_poll_interval_seconds`).

Intermediate `healthy` polls do NOT emit verdict JSON — only terminal classifications (`stalled` / `failed`) do. This keeps the log lean.

## Verdict JSON schema (emitted on terminal classification)

See `contracts/interfaces.md` §3 for the full schema. Shape summary:

```json
{
  "classification": "stalled" | "failed",
  "timestamps": {
    "session_started_iso": "<ISO-8601 UTC>",
    "last_scratch_write_iso": "<ISO-8601 UTC>",
    "last_transcript_advance_iso": "<ISO-8601 UTC>",
    "verdict_emitted_iso": "<ISO-8601 UTC>"
  },
  "last_50_lines": [ "<NDJSON envelope>", ... ],
  "scratch_uuid": "<uuidv4>",
  "scratch_files": [ "<relative-path>", ... ],
  "result_envelope": "<last {\"type\":\"result\",...} line, or null>"
}
```

## Human-readable verdict report

`watcher-runner.sh` writes `.kiln/logs/kiln-test-<uuid>.md` from the verdict JSON. This file is what a human opens when a test fails — it MUST surface the scratch-uuid (so the retained scratch dir can be found), the classification, the last 50 NDJSON envelopes, and any result envelope verbatim.

## Termination protocol

- On `stalled`: send `SIGTERM` to the subprocess PID's process group; wait up to 10s; if still alive, send `SIGKILL`. Then write verdict JSON + report.
- On `failed` (subprocess already exited non-zero): no termination needed — just write the verdict.

FR-008 NON-NEGOTIABLE: no `timeout` wrapping the subprocess, no `--max-turns`, no auto-kill other than what this agent / runner decides based on classification.
