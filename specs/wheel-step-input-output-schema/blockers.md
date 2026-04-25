# Blockers — wheel-step-input-output-schema

**Branch**: `build/wheel-step-input-output-schema-20260425`
**Owner reconciliation**: audit-compliance (TaskList #5)
**Last updated**: 2026-04-25

This file tracks gaps discovered during implementation/audit that are
out-of-scope to fix in this PRD but documented for a follow-on.

---

## OPEN — substrate gaps and pre-existing fixes flagged out-of-scope

### B-1 — `/kiln:kiln-test` substrate gap (pure-shell fixtures unsupported)

**Surface**: `plugin-kiln/scripts/harness/substrate-*.sh` — only `substrate-plugin-skill.sh` exists.
**Symptom**: tasks.md T022 / T047..T053 / T065 / T066 instructed implementers to
"Invoke `/kiln:kiln-test plugin-wheel <fixture>`", but the harness only supports
`harness-type: plugin-skill` (real `claude --print` subprocess against a skill).
Pure-shell unit tests under `plugin-wheel/tests/<name>/run.sh` and runtime-internal
fixtures under `plugin-kiln/tests/<name>/` have no substrate driver.
**Carveout exercised**: NFR-G-1 explicitly permits pure-shell unit tests for
"resolver/hydration logic without an LLM in the loop". Per-fixture
`.kiln/logs/wheel-test-<name>-<ts>.log` (or
`.kiln/logs/kiln-test-<fixture>-<ts>.log`) captures act as the verdict-report
analog. Both implementers cite these in their friction notes.
**Audit verdict**: ACCEPTED per team-lead instruction (`SC-G-1 recalibrated`
message + `Unblocked — start audit + live-smoke gate` message). Not a PRD
blocker. Filed for follow-on as a roadmap item: add a `pure-shell-runner`
substrate to `/kiln:kiln-test` that wraps `bash run.sh` and ingests `PASS:` /
`FAIL:` lines.
**Status**: OPEN — out-of-scope follow-on.

### B-2 — `set -u` + `WHEEL_LIB_DIR` self-discovery bug at `plugin-wheel/lib/workflow.sh:366`

**Surface**: `workflow.sh` line 366 in `workflow_validate_workflow_refs`.
**Symptom**: line 366's `bash -c "source '${WHEEL_LIB_DIR}/...'"` triggers an
unbound-variable error under `set -u` if `WHEEL_LIB_DIR` is not exported by the
caller. Surfaces when validator descends into sub-workflow refs (e.g.
`kiln-mistake.json`'s `shelf:shelf-propose-manifest-improvement` ref) from a
strict-mode context.
**Discovery**: caught by impl-schema-migration's T065 corpus check (back-compat
fixture initially failed under `set -u`); fixed by exporting `WHEEL_LIB_DIR`
before sourcing `workflow.sh` in the fixture, NOT by fixing `workflow.sh`
itself.
**Audit verdict**: out-of-scope for this PRD. Filed for follow-on as a roadmap
item: replace line 366 with `${WHEEL_LIB_DIR:-$(self-discover)}` defensively
(mirroring `engine.sh` lines 31-35).
**Status**: OPEN — out-of-scope follow-on.

---

### B-3 — `/kiln:kiln-report-issue` live-smoke not driveable from sub-agent context

**Surface**: `plugin-wheel/lib/dispatch.sh` — Stop / PostToolUse hooks bind
to the user's primary session.
**Symptom**: audit-compliance attempted to drive `/kiln:kiln-report-issue`
from teammate context to extract `dispatch-background-sync.command_log`
directly. Workflow stalled at `create-issue` (step 2/4) because the Stop hook
does not fire from sub-agent context. Workflow archived to
`.wheel/history/stopped/` (incomplete; `dispatch-background-sync` never
executed).
**Workaround used**: live perf substrate
(`/kiln:kiln-test plugin-kiln perf-kiln-report-issue`) spawns N=5 alternating
`claude --print --plugin-dir <local>` subprocesses — exercises post-PRD code
on this branch end-to-end without requiring wheel-hook activation. Combined
with structural fixture `kiln-report-issue-inputs-resolved` (SC-G-1(b)
anchor) closes the SC-G-1/G-2 gates.
**Audit verdict**: NOT a PRD blocker — substrate substitution worked.
Filed for follow-on as a roadmap item: either (a) document the live-smoke
substrate options in the audit-compliance teammate prompt, or (b) make wheel
hooks sub-agent-driveable for testing.
**Status**: OPEN — out-of-scope follow-on.

---

## RESOLVED

### R-1 — SC-G-1 numerical recalibration (PRD literal "≥3 fewer Bash/Read tool calls")

**Discovery**: researcher-baseline (research.md §baseline §Interpretation).
**Resolution**: spec.md SC-G-1 recalibrated to compound gate — (a)
`dispatch-background-sync.command_log` length 1→0 AND (b) inline disk-fetch
sub-command count 3→0. tasks.md T082 carries the recalibrated form.
**Resolved by**: commit `a7a9a4c` (specs: wheel step input/output schema
artifacts) — spec.md §266-269 ships the recalibrated form. No code commit
needed.
**Process gap noted** (for retrospective): PRD froze success-criteria numbers
(§SC-G-1 "≥3 fewer") BEFORE researcher-baseline captured the post-FR-E batched
baseline (median command_log = 1, not 5). Recalibration consumed mid-pipeline
attention. **Recommendation for retrospective**: PRDs that gate on
quantitative metrics should DEFER the literal numbers to the
researcher-baseline step's output, OR the baseline capture should occur in the
PRD-authoring phase (not the implementation phase).

### R-2 — Sub-workflow filename aliasing implicit in spec/contract

**Discovery**: researcher-baseline §Job 2 inventory walk; flagged in
researcher's early SendMessage to impl-resolver-hydration.
**Resolution**: handled transparently by
`resolve_inputs.sh::_read_upstream_output` fallback path (commit `87d780a`).
Both implementers' friction notes recommend lifting the convention into
contracts/interfaces.md §3 for the next PRD that touches the resolver.
**Resolved by**: commit `87d780a` (resolver impl handles alias).
