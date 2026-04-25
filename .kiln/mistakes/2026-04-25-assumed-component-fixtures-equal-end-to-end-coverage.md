---
type: mistake
date: 2026-04-25
status: completed
completed_date: 2026-04-25
pr: "#166"
made_by: claude-opus-4-7
assumption: "I assumed that 8 passing kiln-test fixtures plus a documented SC-F-6 grep meant the cross-plugin-resolver feature actually worked end-to-end in live wheel dispatch."
correction: "Component fixtures verify components. They do not verify the wiring between components. A feature is 'working' only when the canonical user-facing flow runs against the merged code on the user's actual install — not when each isolated piece passes its own test."
severity: moderate
tags:
  - mistake/scope
  - topic/test-coverage
  - topic/audit-discipline
  - framework/wheel
  - testing/kiln-test
---

# Assumed component-level fixture coverage equaled end-to-end runtime coverage

## What happened

I led the cross-plugin-resolver-and-preflight-registry pipeline as team-lead for `/kiln:kiln-build-prd`. The auditor reported PASS with 8/8 kiln-test fixtures green and SC-F-1..SC-F-7 verified. I cited the audit verbatim, recommended squash-merge, and the user merged PR #163. On the very next live invocation of `/kiln:kiln-report-issue` (the canonical workflow the PRD migrated atomically), the agent prompt contained literal `${WHEEL_PLUGIN_shelf}` — completely unsubstituted. Bash silently expanded it to empty and tried to run `bash: /scripts/shelf-counter.sh: No such file or directory`. The exact silent-failure shape SC-F-6 was meant to eliminate had shipped to main.

Root cause was a wiring gap: `state_init` persisted only step metadata, not the templated `instruction` field. Every Stop-hook re-loaded the raw workflow file from disk, throwing away the in-memory templating done at activation. `engine_init` had no idea state could carry a templated workflow. Five minutes of investigation surfaced it; the fix is ~30 lines plus a regression fixture (PR #165).

## The assumption

I treated "8 fixtures green + audit PASS" as proof the feature worked. I did not run the canonical user flow once before signing off the merge. The fixtures all tested either `template_workflow_json` in isolation (correct) or the activate path in isolation (correct) — but no fixture tested `activate → state_init → stop_hook → agent_prompt` as one round-trip. The auditor's SC-F-6 grep on `.wheel/history/success/*.json` looked at `command_log` (what bash *ran*), not at the prompt the agent *received*. Bash silently expanded the empty token and the symptom showed up one level deeper as a missing-file error — invisible to the grep, invisible to the fixture suite, visible only when a real consumer flow hits it.

## The correction

A test that exercises `f(x)` correctly does not prove that `g(f(x))` works in production. End-to-end correctness requires end-to-end fixtures, OR a live-consumer smoke step that exercises the canonical user-facing flow against the merged code. SC-F-6 specifically was a grep on `command_log` — but what users care about is the prompt the agent received, not what bash later ran. The two diverge whenever shell can silently swallow an unbound expansion. Future audits of "no `${VAR}` reaches the agent" must inspect agent prompts directly, not downstream artifacts.

## Recovery

Investigated `engine_init`/`state_init` paths, identified that the templated JSON was a local variable thrown away after `state_init`. Modified `state.sh::state_init` to embed the full templated workflow JSON at `state.workflow_definition`. Modified `engine.sh::engine_init` to prefer that field over re-reading `workflow_file`. Added regression fixture `plugin-wheel/tests/state-persists-templated-workflow/run.sh` that sabotages the on-disk file post-`state_init` to prove `engine_init` reads from state. Verified all existing fixtures still pass. Opened PR #165.

## Prevention for future agents

- Treat `/kiln:kiln-build-prd` as not-done until the canonical user flow has been run live against the merged code. Library fixtures and audit grep are necessary but not sufficient. The pipeline should add a post-merge "live consumer smoke" step that runs the workflow the PRD modified, not just the fixtures the implementer wrote.
- When auditing "no `${VAR}` leaks to agent," inspect the **prompt the agent receives** (e.g. tool-call input, dispatched instruction text), not downstream artifacts like `command_log`. Bash silently expands unbound vars to empty strings — the symptom you see is one indirection away from the leak.
- Library-correctness fixtures (`template_workflow_json` substitutes correctly) are not a substitute for round-trip fixtures (`activate → state → stop-hook → agent_prompt`). For every new wheel hook that produces an artifact downstream code consumes, write a fixture that crosses the boundary in both directions.
- "Audit PASS" is a result of tests run, not a guarantee of correctness. When the audit cites a specific SC criterion, read the SC, find the canonical consumer flow it claims to verify, and run that flow once before signing off.
