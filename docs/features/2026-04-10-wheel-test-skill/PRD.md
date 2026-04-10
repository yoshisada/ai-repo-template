# Feature PRD: Wheel Test Skill

## Parent Product

Parent: the **kiln** Claude Code plugin monorepo (`@yoshisada/kiln`), specifically the `plugin-wheel/` sub-plugin that provides a hook-based workflow engine for Claude Code agent pipelines. See `CLAUDE.md` for product context. Tech stack inherited: Markdown (skill definitions), Bash 5.x (hooks, CLI helpers), Node.js 18+ (scaffolding only — not needed for this feature), JSON (workflow definitions), `jq` (JSON parsing).

## Feature Overview

A new user-invocable skill `/wheel-test` that executes every test workflow under `workflows/tests/` end-to-end and produces a pass/fail report. The skill is the developer's one-command answer to "did my change to the wheel engine break anything?" It orchestrates a mix of parallel and serial workflow activations based on workflow type, collects results, flags orphaned state files and hook errors, and writes a markdown audit trail.

## Problem / Motivation

Today, validating the wheel engine means running each test workflow manually, one at a time, and remembering which ones can run together and which ones conflict. Over the course of one recent debugging session we:

- Re-ran `team-static` five times during a single investigation, each run requiring manual TeamCreate + Agent spawning + shutdown + TeamDelete. Every run took ~5 minutes of turn-by-turn ceremony.
- Accumulated orphan state files because stale `.wheel/.locks/` entries silently broke teammate sub-workflows, and the manual run-and-eyeball flow had no way to detect it.
- Missed a silent archive collision where two concurrent workers overwrote each other's archive files in the same wall-clock second. It was invisible until we grep'd `handle_terminal_step` in the logs.
- Had to remember the order constraint: team workflows all reuse the same `test-*-team` name and cannot run concurrently; non-team workflows can, but only the ones without agent steps in the lead's context.

A `/wheel-test` skill eliminates the ceremony, catches the silent failures, and turns "smoke-test the wheel engine" into a single command.

## Goals

- Run all 12 workflows in `workflows/tests/*.json` in a single invocation
- Respect parallelism constraints: safely parallelize workflows that don't share lead context or team resources, serialize the rest
- Flag pass/fail for each workflow (including "expected-failure" workflows like `team-sub-fail`)
- Detect and report orphan state files in `.wheel/state_*.json` after the run
- Detect and report hook errors logged in `.wheel/logs/wheel.log` during the run
- Produce a human-readable markdown report written to both stdout and `.wheel/logs/test-run-<timestamp>.md`
- Complete a full run in under 5 minutes on a developer machine
- Exit with a clear non-zero signal when any workflow fails so the skill is usable in CI-adjacent workflows

## Non-Goals

- **Running shell-script tests** (`tests/*.sh`). The skill only covers workflow-level tests in `workflows/tests/`.
- **Running in isolated worktrees.** This is a smoke-test suite, not a hermetic CI harness. It runs in the current working directory and leaves the repo state alone between tests.
- **Parallelism beyond the safe subset.** We do not attempt to parallelize team workflows or agent-step workflows. Their sequential cost is acceptable (~15 seconds each).
- **Self-healing on failures.** The skill reports failures; it does not retry, rollback, or attempt fixes.
- **CI integration.** A GitHub Actions runner wrapper is out of scope. Developers can call the skill from CI if they want, but the skill itself is designed for local invocation.
- **Running workflows other than the `tests/` subdirectory.** Future feature if needed.
- **Running tests with filters or tag selectors.** First version is "all or nothing". Filtering can come later.

## Target Users

- **Wheel engine developers** — the primary persona. Anyone modifying `plugin-wheel/lib/`, `plugin-wheel/hooks/`, or the test workflows themselves. Today that is one contributor.
- **Agents running on behalf of the developer** — the `/build-prd` pipeline could invoke `/wheel-test` as a smoke test before marking a wheel-engine change as done.

## Core User Stories

### Story 1: Smoke test after a wheel-engine change
As a wheel engine developer who just changed `plugin-wheel/lib/dispatch.sh`, I want to run `/wheel-test` in my session and get a pass/fail report within 5 minutes so I know whether my change broke any of the 12 known-good workflows before I commit.

### Story 2: Diagnose a regression
As a developer who just saw `team-static` fail, I want the test report to show me which phase failed, whether orphan state files were left behind, and whether any hook errors fired — so I can jump straight to the root cause without re-running everything manually.

### Story 3: Audit trail
As a developer doing a multi-session debugging investigation, I want each test run to write a timestamped report to `.wheel/logs/test-run-*.md` so I can diff results across runs and see whether a fix made things better or worse.

## Functional Requirements

1. **FR-001 — Workflow enumeration**: The skill discovers all `.json` files under `workflows/tests/` at invocation time. It does not hard-code a list; adding a new test workflow to that directory MUST cause the next `/wheel-test` run to pick it up automatically.

2. **FR-002 — Phase classification**: Each workflow is classified into one of four phases based on its step types:
   - **Phase 1 — parallelizable, command-only**: workflows whose steps are all `command`, `branch`, or `loop` types AND do NOT contain any `agent`, `teammate`, `team-*`, or `workflow` step types.
   - **Phase 2 — serial, agent-step**: workflows containing `agent` steps (requires lead-driven dispatch) but NOT team or nested workflow steps.
   - **Phase 3 — serial, composition**: workflows containing `workflow` (nested child) step types.
   - **Phase 4 — serial, team**: workflows containing any `team-*` or `teammate` step types.

   Classification is derived from the workflow JSON, not from heuristics on the name.

3. **FR-003 — Phase 1 parallel execution**: Phase 1 workflows are activated back-to-back in quick succession (each activate.sh call is a separate Bash tool invocation) to let the hook system create all their state files. The skill then waits for all of them to archive before moving to the next phase. "Parallel" here means the activations are not gated on each other's completion — it does NOT mean spawning sub-agents.

4. **FR-004 — Phase 2/3/4 serial execution**: Workflows in phases 2, 3, and 4 run one at a time. The skill activates one workflow, waits for its archive to appear in `.wheel/history/success/` or `.wheel/history/failure/`, then moves to the next.

5. **FR-005 — Expected-failure handling**: Workflows whose name matches the pattern `*-fail*` or whose documented expected outcome is failure (e.g., `team-sub-fail`) are treated as "expected failure = pass". If they archive to `history/failure/`, that counts as a pass. If they archive to `history/success/` unexpectedly, that counts as a fail.

6. **FR-006 — Team workflow orchestration**: For Phase 4 workflows, the skill instructs the invoker (the agent or developer running the skill) to follow the wheel stop-hook flow exactly: wait for TeamCreate instruction, call TeamCreate, wait for spawn instructions, spawn teammates via the Agent tool with `run_in_background: true`, wait for teammates to complete their sub-workflows and send results, send shutdown_requests, wait for teammate_terminated notifications, then call TeamDelete. The skill MUST document that blind-spawning before the stop hook instructions is forbidden (reference the bug trail from session).

7. **FR-007 — Pre-run hygiene check**: Before running any workflow, the skill verifies `.wheel/state_*.json` is empty. If any state files exist, it lists them and refuses to proceed, telling the user to archive them first.

8. **FR-008 — Orphan detection**: After each workflow phase, the skill checks for lingering `.wheel/state_*.json` files. Any that don't correspond to the workflow just activated are reported as orphans. Orphans count as a pipeline failure even if the workflow itself passed.

9. **FR-009 — Hook error detection**: At the start of the run, the skill records the current line count of `.wheel/logs/wheel.log`. After the run, it scans new lines for `ERROR|FAIL|stalled` patterns and includes any matches in the report.

10. **FR-010 — Archive verification**: For each passed workflow, the skill confirms an archive file exists at `.wheel/history/success/{workflow_name}-{timestamp}-{state_id}.json` (the new hybrid format from tonight's fix) or the failure equivalent. Missing archives indicate a handle_terminal_step failure and count as a run failure.

11. **FR-011 — Report format**: The report is a markdown document containing:
    - Header with run timestamp, total duration, and overall verdict
    - Summary table: `N passed / M failed / K orphaned / L hook errors`
    - Per-workflow table with columns: `Workflow | Phase | Expected | Status | Duration | Archive | Notes`
    - Orphan state file section (if any)
    - Hook error excerpts section (if any)
    - Reproduction commands section listing the exact `activate.sh` invocations used, so a developer can re-run a single failed workflow by hand

12. **FR-012 — Report persistence**: The report is written to `.wheel/logs/test-run-<UTC-timestamp>.md` AND echoed to stdout. The file path is printed at the end of the run for easy reference.

13. **FR-013 — Exit status**: The skill's last action reports overall pass/fail. If every workflow passed, no orphans, no hook errors → `PASS`. Otherwise → `FAIL` with a count of issues.

14. **FR-014 — Skill activation gate**: Before any activation, the skill refuses to run if there are no workflows in `workflows/tests/`, printing a clear error and exiting.

15. **FR-015 — Duration budget**: Total run time should fit inside 5 minutes for the current 12-workflow suite. No individual workflow should be allowed to hang the suite; if a workflow fails to archive within 60 seconds of its activation (for phases 1-3) or 120 seconds (for phase 4, which includes team orchestration), the skill marks it as a timeout and moves on.

## Absolute Musts

1. **Tech stack (highest priority)**: Markdown (skill definition), Bash 5.x (any shell logic inlined in the skill), `jq` (JSON parsing for workflow classification and archive verification), the existing wheel engine (`plugin-wheel/lib/*`, `plugin-wheel/hooks/*`, `plugin-wheel/bin/activate.sh`). No new language runtime. No new dependencies. No Node.js.
2. **Hook-driven execution only**: The skill MUST NOT manually advance cursors, mark step statuses, or write state files. All workflow progression goes through `activate.sh` + the hook system. This is non-negotiable — bypassing hooks is exactly the kind of bug we've been fixing.
3. **Classification from JSON, not names**: Phase classification MUST inspect workflow step types, not parse filenames. A workflow named `team-foo` that contains no team steps must be classified as Phase 1/2/3, not Phase 4.
4. **Zero new state file leaks**: The skill MUST leave `.wheel/state_*.json` empty after a successful run. If the skill itself creates orphans, it fails.
5. **No mock mode**: The skill runs real workflows against the real hook system. There is no dry-run or simulation mode. (A future feature could add that, but MVP is real runs only.)

## Tech Stack

No additions or overrides. Feature uses only tooling already present in the kiln/wheel repo:
- `plugin-wheel/bin/activate.sh` for workflow activation
- `plugin-wheel/bin/validate-workflow.sh` for workflow discovery and JSON inspection
- `jq` for parsing workflow JSON and state files
- Bash `[[`, parameter expansion, and process management for orchestration
- The existing stop-hook / post-tool-use hook contracts from `plugin-wheel/hooks/`

## Impact on Existing Features

- **New skill file** at `plugin-wheel/skills/wheel-test/SKILL.md`. Becomes auto-discovered as `/wheel-test`.
- **No changes to the wheel engine itself.** `lib/`, `hooks/`, `bin/`, and the workflow JSON files are untouched.
- **New log file location**: `.wheel/logs/test-run-*.md`. The `.wheel/logs/` directory already exists. The new files will be gitignored via the existing `.wheel/logs/` entry (verify this in implementation).
- **Plugin manifest may need updating**: `plugin-wheel/.claude-plugin/plugin.json` may need to list the new skill. Check the existing pattern from other wheel skills (`wheel-run`, `wheel-status`, `wheel-list`, etc.) during implementation.
- **No breaking changes.** Existing skills, workflows, and hooks all continue to work identically. Developers who don't invoke `/wheel-test` see no difference.

## Success Metrics

1. **Ergonomic**: After `/wheel-test` ships, a wheel-engine developer should be able to say "I ran the test suite" in one command and point at `.wheel/logs/test-run-*.md` as evidence. Measured by: the next debugging session (tonight's style) uses `/wheel-test` at least once instead of hand-running workflows.
2. **Coverage**: 12 of 12 current workflows run in a single invocation. Measured by: a successful run produces 12 archive entries and 0 skipped workflows (excluding deliberate timeouts).
3. **Speed**: Full suite completes in under 5 minutes on a developer machine. Measured by: the Duration field in the report.
4. **Signal quality**: When a known bug is introduced (e.g., re-introducing the stale `agent_map_*` lock bug), `/wheel-test` catches it via orphan detection or team-workflow failure. Measured by: at least one regression caught during the first week of use.

## Risks / Unknowns

- **Risk: Lead-driven dispatch for Phase 2/3/4 requires the skill invoker to follow instructions over multiple turns.** The skill is a passive instruction set, not an active orchestrator. If the invoker doesn't follow the stop-hook flow exactly, team workflows will fail. Mitigation: the skill explicitly documents each stop-hook step and refuses to skip ahead. The user accepted this tradeoff during clarification ("if you need me to approve something fine").
- **Risk: Timing flakiness on Phase 1 parallel activations.** Multiple `activate.sh` calls back-to-back within the same second could race on lock acquisition or state file naming. Tonight's archive-collision fix (hybrid filename with state id suffix) mitigates the archival path, but there may be other timing-sensitive paths we haven't exercised.
- **Risk: Team workflow shutdown latency** (issue #007 — bad-worker took ~30 seconds to shut down after a failed sub-workflow). The skill's 120-second Phase 4 timeout accommodates this, but if the latency grows, the skill will start timing out.
- **Unknown: How does the hook system behave when multiple state files are active simultaneously?** Phase 1 deliberately relies on parallel activation. If the hook has any assumptions about "one active workflow at a time" we haven't encountered yet, we'll find them here. That's arguably a feature — the test suite will surface the assumption.
- **Unknown: Is `.wheel/logs/` gitignored?** Need to verify during implementation. If it isn't, the report files would pollute the working tree.

## Assumptions

- The `workflows/tests/` directory exists and is the canonical home for test workflows. (Verified — it contains all 12 workflows referenced during tonight's session.)
- `activate.sh` is idempotent with respect to multiple back-to-back invocations in the same session. (Verified by observation: Phase 1 parallel activation worked during manual testing.)
- The wheel post-tool-use hook picks up multiple concurrent activations correctly. (Verified by session experience: multiple worker sub-workflow activations ran in parallel during team-static runs.)
- The `.wheel/.locks/` directory is either unused or self-cleaning after tonight's lock elimination. (Verified — `agent_map_*` locks are gone; only `workflow-dispatch-*` locks remain and those clean up with their state files.)
- The skill can rely on `jq` being present. (Verified — the whole wheel engine depends on it.)
- The skill can parse the new hybrid archive filename format (`{workflow}-{timestamp}-{state_id}.json`). (Verified — tonight's fix shipped in commit `69d2dff`.)

## Open Questions

1. Should the skill have a `--verbose` / `--quiet` mode? (Leaning: no for MVP. The report itself has all the detail; verbosity tweaks can come later.)
2. Should Phase 1 workflows that finish early (say, `count-to-100` in 2 seconds) proceed to Phase 2 immediately while Phase 1 stragglers catch up, or must all Phase 1 complete before Phase 2 starts? (Leaning: all Phase 1 must complete. Simpler to reason about. Performance cost is negligible.)
3. What happens if a workflow archives to `.wheel/history/stopped/` instead of `success/` or `failure/` (e.g., because something else called deactivate.sh mid-run)? Count as a failure, or as a skipped test? (Leaning: failure with a "stopped unexpectedly" note.)
4. Should the skill auto-archive existing orphan state files at the start of the run, or refuse to proceed until the user cleans them up manually? FR-007 currently says "refuse to proceed" — is that too strict? (Leaning: yes, refuse. Auto-archive could mask a real problem from a previous session.)

Decisions on these can happen during `/plan` and `/tasks`, but flagging them now so they're not lost.
