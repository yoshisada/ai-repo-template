---
name: wheel-test
description: Run every workflow under workflows/tests/ end-to-end and emit a markdown pass/fail report at .wheel/logs/test-run-<timestamp>.md. Classifies workflows into 4 phases by JSON step types, runs Phase 1 in parallel (back-to-back activations) and Phases 2-4 serially via the wheel activate.sh + hook path. Usage: /wheel-test
---

<!--
  Plugin manifest note: plugin-wheel/.claude-plugin/plugin.json uses skill
  auto-discovery — no explicit registration required. This file's presence
  under plugin-wheel/skills/wheel-test/ is sufficient for Claude Code to
  expose /wheel-test.
-->

# Wheel Test — End-to-End Workflow Suite

Run every JSON workflow under `workflows/tests/` through the real `plugin-wheel/bin/activate.sh` + hook path, classify each workflow by JSON step type into one of four phases, and emit a timestamped markdown pass/fail report at `.wheel/logs/test-run-<UTC-timestamp>.md`.

## Overview — Phase Execution Model

| Phase | Step-type rule                                      | Execution                                 | Timeout |
|-------|-----------------------------------------------------|-------------------------------------------|---------|
| 1     | Only `command` / `branch` / `loop` steps            | Back-to-back activations, wait on all     | 60s ea  |
| 2     | Has `agent` step; no `workflow`/`team-*`/`teammate` | Serial                                    | 60s     |
| 3     | Has `workflow` step; no `team-*`/`teammate`         | Serial                                    | 60s     |
| 4     | Has any `team-*` or `teammate` step                 | Serial, stop-hook ceremony (see Step 6)   | 120s    |

### Absolute Musts (violating any is a bug)

1. **Classification MUST inspect JSON step types via `jq`, never the filename** (FR-002). A workflow named `team-sub-fail` with only `command` steps is Phase 1.
2. **All workflow progression MUST go through `plugin-wheel/bin/activate.sh` + hooks.** Never write `.wheel/state_*.json` or advance cursors from this skill (FR-016).
3. **Phase 1 "parallel" means back-to-back Bash tool invocations from the skill invoker — ONE activate.sh call per Bash tool call** (FR-003). The wheel PostToolUse hook processes only the LAST `activate.sh` line in any single Bash tool command (`tail -1` in `post-tool-use.sh`), so loops would silently drop activations. The skill invoker MUST issue N separate Bash tool calls for N Phase 1 workflows.
4. `.wheel/state_*.json` MUST be empty after a passing run (FR-017, SC-004). Leftover state files are orphans and count as failure.
5. No mock mode — validation is end-to-end against real workflows (Absolute Must #5 in PRD).
6. **activate.sh MUST be invoked with a literal absolute path** on its own Bash line (no shell variables), because the hook scans the raw command text with a regex that requires `path/activate.sh` and won't match quoted shell variables.

## User Input

```text
$ARGUMENTS
```

`$ARGUMENTS` is currently unused; reserved for a future `--phase N` filter.

---

## Step 1 — Preflight + discover + classify

Source the function library and run preflight in a single Bash call. This sets the `WT_*` globals (exported so subsequent calls re-source the same clock), verifies `workflows/tests/` is non-empty, refuses if any `.wheel/state_*.json` files already exist, records the wheel.log baseline, and prints the four phase lists.

```bash
set -euo pipefail
WT_REPO_ROOT="$(git rev-parse --show-toplevel)"
source "${WT_REPO_ROOT}/plugin-wheel/skills/wheel-test/lib/runtime.sh"
wt_init_run_clock
wt_require_nonempty_tests_dir
wt_require_clean_state
WT_LOG_BASELINE="$(wt_record_log_baseline)"
export WT_LOG_BASELINE
mkdir -p "${WT_REPORT_DIR}"
: > "${WT_WHEEL_DIR}/logs/.wheel-test-results-${WT_RUN_TIMESTAMP}.tsv"
# Emit the classification as KEY=PATH lines plus a reusable env snapshot so
# later Bash calls (new shells) can re-seed globals.
env_file="${WT_WHEEL_DIR}/logs/.wheel-test-phases-${WT_RUN_TIMESTAMP}.env"
: > "$env_file"
printf 'WT_RUN_TIMESTAMP=%s\n' "$WT_RUN_TIMESTAMP" >> "$env_file"
printf 'WT_LOG_BASELINE=%s\n' "$WT_LOG_BASELINE"  >> "$env_file"
printf 'WT_START_EPOCH=%s\n'  "$WT_START_EPOCH"   >> "$env_file"
echo "=== preflight OK (run=${WT_RUN_TIMESTAMP}) ==="
echo ""
echo "=== classification ==="
while IFS= read -r wf; do
  [[ -z "$wf" ]] && continue
  p="$(wt_classify_workflow "$wf")"
  printf 'PHASE%s %s\n' "$p" "$wf"
  printf 'PHASE%s %s\n' "$p" "$wf" >> "$env_file"
done < <(wt_discover_workflows)
echo ""
echo "env snapshot: $env_file"
echo "results TSV:  ${WT_WHEEL_DIR}/logs/.wheel-test-results-${WT_RUN_TIMESTAMP}.tsv"
```

The `PHASE1 /abs/path/foo.json` lines in the output tell you exactly which workflows to activate in each subsequent step. Keep the env file path handy — every later step re-sources `runtime.sh` and re-reads it.

If preflight exits non-zero, STOP and surface the error. Do not proceed.

---

## Step 2 — Phase 1 activations (one Bash tool call per workflow)

**For each `PHASE1 <absolute-path>` line printed in Step 1**, issue one Bash tool call with EXACTLY this form, substituting the absolute path of `activate.sh` and the absolute path of the workflow:

```bash
/<absolute-repo-root>/plugin-wheel/bin/activate.sh /<absolute-repo-root>/workflows/tests/<workflow>.json
```

**Rules for this step:**
- One Bash tool call per workflow. Do NOT batch. Do NOT loop inside a single Bash call — the hook only processes the last `activate.sh` line per call.
- Use **literal absolute paths**, not shell variables. The hook's regex (`^[[:space:]]*(bash[[:space:]]+)?("|')?(\./|/)?[^[:space:]()"']*activate\.sh([[:space:]]|$)`) requires a literal path starting with `/` or `./`.
- No waits between calls. Fire them back-to-back in the conversation.
- Before sending any Phase 1 activation, record the start epoch per workflow (Step 3 below will compute durations against it). The runtime library does this bookkeeping for you via `wt_record_phase1_start`.

In practice the flow is:

1. Inspect the `PHASE1` lines from Step 1's output.
2. For each one, issue two Bash tool calls:
   - Call A (single-line command): the literal `activate.sh /abs/workflow.json` invocation. The hook intercepts this.
   - Call B: `bash -c "source .../runtime.sh && wt_record_phase1_start /abs/workflow.json"` to record the start timestamp. (Can also be done once as a batch before activations — see the helper block at the end of this step.)

**Optimization**: do all starts in ONE bookkeeping call before activations, then issue N activations. Use this helper:

```bash
# Record start times for all Phase 1 workflows in one go.
set -euo pipefail
WT_REPO_ROOT="$(git rev-parse --show-toplevel)"
source "${WT_REPO_ROOT}/plugin-wheel/skills/wheel-test/lib/runtime.sh"
wt_load_run_env
while read -r tag path; do
  [[ "$tag" == "PHASE1" ]] || continue
  wt_record_phase1_start "$path"
done < "${WT_WHEEL_DIR}/logs/.wheel-test-phases-${WT_RUN_TIMESTAMP}.env"
cat "${WT_WHEEL_DIR}/logs/.wheel-test-phase1-starts-${WT_RUN_TIMESTAMP}.tsv"
```

Then issue one literal-path `activate.sh` Bash tool call per Phase 1 workflow.

---

## Step 3 — Phase 1 wait + result recording

After all Phase 1 activations have been issued, run the wait loop in ONE Bash call. It polls each workflow's archive directory, records pass/fail into the TSV, and sweeps for orphans.

```bash
set -euo pipefail
WT_REPO_ROOT="$(git rev-parse --show-toplevel)"
source "${WT_REPO_ROOT}/plugin-wheel/skills/wheel-test/lib/runtime.sh"
wt_load_run_env
wt_phase1_wait_all
```

---

## Step 4 — Phase 2 (serial, agent-step workflows)

For **each** `PHASE2 <absolute-path>` line from Step 1, do this sequence — one workflow at a time. The whole sequence for one workflow fits in two Bash calls: the literal activate.sh call, then the wait+record call.

### Call 4a (per workflow): literal activate.sh

```bash
/<absolute-repo-root>/plugin-wheel/bin/activate.sh /<absolute-repo-root>/workflows/tests/<workflow>.json
```

### Call 4b (per workflow): wait and record

```bash
set -euo pipefail
WT_REPO_ROOT="$(git rev-parse --show-toplevel)"
source "${WT_REPO_ROOT}/plugin-wheel/skills/wheel-test/lib/runtime.sh"
wt_load_run_env
wt_wait_and_record_serial 2 "/<absolute-repo-root>/workflows/tests/<workflow>.json" <start-epoch>
```

Where `<start-epoch>` is the output of `date +%s` captured just before Call 4a. If you forget to capture it, pass `0` and the duration column will just be inaccurate — the pass/fail is still correct.

Do NOT begin a new workflow until the previous workflow's wait+record call has returned.

---

## Step 5 — Phase 3 (serial, nested-workflow composition)

Identical to Phase 2, but pass `3` as the phase number to `wt_wait_and_record_serial`:

For **each** `PHASE3 <absolute-path>` line:

1. Literal activate.sh call.
2. `... wt_wait_and_record_serial 3 "<abs-path>" <start-epoch>`.

---

## Step 6 — Phase 4 (team workflows, stop-hook ceremony) — FR-006

Phase 4 workflows spawn real Claude Code teammates via `TeamCreate` + `Agent`. These primitives cannot be driven from a shell script — the skill invoker (you, the agent running this skill) MUST follow the stop-hook protocol turn-by-turn for each Phase 4 workflow. Blind-spawning before the stop-hook instruction arrives is **forbidden** — the fix trail on this branch (commits 3283c10, 3215cfd, 69d2dff) exists precisely because earlier versions raced the hook.

For **each** `PHASE4 <absolute-path>` line from Step 1, follow these 10 steps one workflow at a time:

1. **Activate**: issue a literal-path Bash tool call of the form `/<abs>/activate.sh /<abs>/workflows/tests/<workflow>.json`. Capture `date +%s` immediately before as the start epoch.
2. **Wait for TeamCreate instruction from the stop hook.** Do NOT proactively call `TeamCreate`. The hook will deliver a system-reminder / tool-result block with the exact `team_id` and teammate roster.
3. **Call `TeamCreate`** exactly as instructed — no inferred fields, no renaming.
4. **Wait for spawn instructions** — the hook then sends a follow-up listing each teammate to spawn.
5. **Spawn each teammate** via the `Agent` tool with `run_in_background: true`. Use the exact `agent_id` and prompt given by the hook. Never spawn a teammate the hook did not name.
6. **Wait for teammate results.** Teammates work in background; you will receive notifications when they send messages or complete. Do not poll, do not sleep.
7. **Send `shutdown_request`** to each teammate (one `SendMessage` per teammate) once their work is reported complete.
8. **Wait for `teammate_terminated` notifications** from each teammate. Do NOT call `TeamDelete` until every teammate has reported termination.
9. **Call `TeamDelete`** for the team id from step 3.
10. **Wait and record** — issue a Bash tool call:
    ```bash
    set -euo pipefail
    WT_REPO_ROOT="$(git rev-parse --show-toplevel)"
    source "${WT_REPO_ROOT}/plugin-wheel/skills/wheel-test/lib/runtime.sh"
    wt_load_run_env
    wt_wait_and_record_serial 4 "/<abs-path>/workflows/tests/<workflow>.json" <start-epoch>
    ```

Once every Phase 4 workflow has been run through steps 1–10, proceed to Step 7.

---

## Step 7 — Reconcile, build report, emit, verdict

One final Bash call builds and emits the report and returns the verdict.

```bash
set -euo pipefail
WT_REPO_ROOT="$(git rev-parse --show-toplevel)"
source "${WT_REPO_ROOT}/plugin-wheel/skills/wheel-test/lib/runtime.sh"
wt_load_run_env
wt_reconcile_expected_failures
BODY="$(wt_build_report)"
wt_emit_report "$BODY"
wt_final_verdict
```

The final `wt_final_verdict` call is the ONLY function whose exit code propagates as the skill's final status (per `specs/wheel-test-skill/contracts/interfaces.md`).

---

## Rules & Invariants

- **Never write `.wheel/state_*.json`** — only `activate.sh` + hooks manage state.
- **Never delete archives** — the report's reproduction section is the diagnostic, not archive surgery.
- **Never classify by filename** — always via `jq -r '.steps[].type'`.
- **Phase 1 parallel activation** means separate Bash tool calls with literal paths. Not `&`/`wait`, not loops.
- **No mock mode** — the only validation is the real 12-workflow suite (Absolute Must #5).
- **One report per run** — `WT_RUN_TIMESTAMP` includes seconds, so back-to-back runs produce distinct files (FR-012, US3).
- **Expected-failure reconciliation** — workflows whose basename matches `*-fail*` flip pass/fail against archive location (FR-005).

## Troubleshooting

- **"pre-existing state files detected"** — Run `/wheel-stop` for each, or archive them manually into `.wheel/history/stopped/`, then re-run `/wheel-test`.
- **"TIMEOUT" rows** — A workflow failed to archive within its phase budget. Check `.wheel/logs/wheel.log` between `WT_LOG_BASELINE` and EOF.
- **Orphans present but verdict PASS?** — Won't happen. Orphans force FAIL per FR-008 / FR-017.
- **Activation did nothing** — you used `"$VAR"` instead of a literal path. The hook regex requires `/` or `./` at the start of the activate.sh token. Re-issue with the expanded absolute path.
- **Phase 4 ceremony confusion** — re-read Step 6. The rule is simple: never call `TeamCreate`, `Agent`, or `TeamDelete` until the stop hook has explicitly asked you to. The hook is authoritative.

## Files

- `plugin-wheel/skills/wheel-test/SKILL.md` — this file
- `plugin-wheel/skills/wheel-test/lib/runtime.sh` — function library (all `wt_*` functions per `specs/wheel-test-skill/contracts/interfaces.md`)
- `.wheel/logs/test-run-<WT_RUN_TIMESTAMP>.md` — generated report (per run)
- `.wheel/logs/.wheel-test-results-<WT_RUN_TIMESTAMP>.tsv` — transient result accumulator (inspectable for debugging)
- `.wheel/logs/.wheel-test-phases-<WT_RUN_TIMESTAMP>.env` — transient classification snapshot (inspectable for debugging)
- `.wheel/logs/.wheel-test-phase1-starts-<WT_RUN_TIMESTAMP>.tsv` — Phase 1 start-epoch accumulator
