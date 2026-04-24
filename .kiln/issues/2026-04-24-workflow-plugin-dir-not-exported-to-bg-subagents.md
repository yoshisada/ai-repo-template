---
id: 2026-04-24-workflow-plugin-dir-not-exported-to-bg-subagents
title: WORKFLOW_PLUGIN_DIR is unset in background sub-agents spawned by wheel agent-steps — silent portability failure in consumer installs
type: bug
date: 2026-04-24
status: open
severity: high
area: wheel
category: portability
repo: https://github.com/yoshisada/ai-repo-template
files:
  - plugin-wheel/bin/activate.sh
  - plugin-wheel/hooks/post-tool-use.sh
  - plugin-kiln/workflows/kiln-report-issue.json
  - plugin-shelf/scripts/shelf-counter.sh
  - plugin-shelf/scripts/append-bg-log.sh
  - specs/report-issue-speedup
---

## Summary

When a wheel agent-step spawns a **background** sub-agent via `Agent(run_in_background: true)`, the sub-agent's environment does NOT have `WORKFLOW_PLUGIN_DIR` exported. This is a silent-in-source-repo / fatal-in-consumer portability violation: in this repo the sub-agent falls back to the local source path (`plugin-shelf/scripts/...`) and things work by accident; in a consumer install where `plugin-shelf/` doesn't exist under the repo root, the same sub-agent fails to resolve its scripts and the `dispatch-background-sync` step produces no side effects (counter never increments, log never appends, full-sync cadence never fires).

CLAUDE.md explicitly names this pattern as NON-NEGOTIABLE: *"plugin-workflow portability — scripts invoked from wheel workflows must not be referenced via repo-relative paths like `plugin-shelf/scripts/foo.sh`."* The violation is currently hidden by the accident that source-repo paths happen to resolve.

## How to reproduce

1. Run `/kiln:kiln-report-issue <some description>` in the source repo (this one). The foreground path completes cleanly.
2. Observe the background sub-agent's completion log — it will note that `WORKFLOW_PLUGIN_DIR` was unset in its environment and that it resolved the script path from the local source repo (`plugin-shelf/scripts/`).
3. In a simulated consumer install (empty repo with the plugin installed via marketplace, no `plugin-shelf/` directory under CWD), running the same command silently no-ops the background step — counter stays at its current value, no log entry is appended.

Observed in this session: background sub-agent `a307a93f7b7697302` completed with the note "`WORKFLOW_PLUGIN_DIR` was unset in the sub-agent environment, so I resolved the script path from the local source repo (`plugin-shelf/scripts/`). This is the pre-req gap called out in CLAUDE.md's 'Plugin workflow portability' section — in a consumer install the script would live under `~/.claude/plugins/cache/yoshisada-speckit/shelf/<version>/scripts/` and would need the env var exported by wheel."

## Why severity: high

The bug is silent. A consumer running `/kiln:kiln-report-issue` sees a clean 3-line foreground summary; the background step appears to succeed (the foreground never waits on it). But the counter never increments, so the full-sync cadence (`shelf_full_sync_threshold = 10`) never triggers — the consumer's Obsidian vault silently drifts from their `.kiln/` state. Worse: the log file that should capture this in `.kiln/logs/report-issue-bg-<date>.md` never gets written, so the consumer has no signal that anything is wrong.

This is exactly the "silently works in the source repo and silently breaks everywhere else" pattern CLAUDE.md's portability rules exist to prevent.

## Root cause hypothesis

The wheel engine (most likely `plugin-wheel/bin/activate.sh`, `plugin-wheel/hooks/post-tool-use.sh`, or wherever per-step env composition happens) exports `WORKFLOW_PLUGIN_DIR` to the **foreground** agent step's subshell, but not to asynchronous background sub-agents spawned via the `Agent` tool with `run_in_background: true`. The Agent-tool call seems to use its own env-baseline rather than inheriting the workflow's current env.

Confirm by:
- Inspecting where `WORKFLOW_PLUGIN_DIR` is exported relative to the agent-step dispatch path.
- Checking whether the Agent tool's environment inheritance differs for background vs foreground spawns.
- Verifying by instrumenting a test workflow that `env | grep WORKFLOW` produces output in a foreground step but not in a background sub-agent's first bash call.

## Proposed fix shape

Two options — pick one based on which is the right abstraction:

**(A) Wheel exports `WORKFLOW_PLUGIN_DIR` globally for the workflow's lifetime** — so any sub-agent (foreground or background) inherits it. This is the cleanest model if wheel already owns per-workflow env scope.

**(B) The `dispatch-background-sync` step templates `${WORKFLOW_PLUGIN_DIR}` into the sub-agent prompt literal at dispatch time** — so the sub-agent doesn't need the env var, it gets an absolute path baked into its instructions. Simpler to ship, but every background sub-agent in every workflow has to remember to do this correctly.

Option (A) is preferred because it prevents every future background-sub-agent-from-a-workflow pattern from having to re-learn this lesson.

## Proposed acceptance

- A wheel smoke test (e.g., extend `/wheel:wheel-test`) simulates a consumer install — removes `plugin-shelf/` and `plugin-kiln/` from the repo root, runs a workflow that spawns a background sub-agent, asserts the sub-agent can resolve its plugin scripts.
- CI fails if the smoke test regresses.
- `/kiln:kiln-report-issue` background logs (`.kiln/logs/report-issue-bg-<date>.md`) show `WORKFLOW_PLUGIN_DIR` pointing at the plugin cache path (`~/.claude/plugins/cache/...`), not the repo-relative path, when run from a consumer install.
- Documentation updated (CLAUDE.md or wheel's README) to state that `WORKFLOW_PLUGIN_DIR` is available in both foreground and background sub-agent env.

## Relation to other issues

- This bug currently hides behind a happy accident in this repo. Once fixed, the same test-suite addition should verify that the `report-issue-speedup` FR-010 summary (counter display) is *correct* in a consumer install, not just present.
- Complements the `install-smoke-ci` roadmap item (`.kiln/roadmap/items/2026-04-24-install-smoke-ci.md`) — the install smoke test should specifically exercise a background-sub-agent-spawning workflow path to catch this class of portability regression.

## Pipeline guidance

High severity — silent failure in consumer installs is the worst kind of bug because the consumer has no feedback that anything is wrong. Fix should be bundled with (or closely precede) any marketing / adoption push, because the first thing a new user does is file an issue via `/kiln:kiln-report-issue` and right now the plugin's own "did anything happen in the background?" signal is broken for them. `/kiln:kiln-fix` appropriate — the fix is scoped and the existing wheel + report-issue specs are sufficient.
