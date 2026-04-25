---
id: 2026-04-25-pipeline-end-shutdown-nag-loop
title: Pipeline-end shutdown-nag loop — team-lead enters /loop after teammate pipeline finishes (verified 2026-04-25)
type: feedback
date: 2026-04-25
status: open
severity: high
area: architecture
repo: https://github.com/yoshisada/ai-repo-template
---

At the end of teammate pipelines (notably `/kiln:kiln-build-prd`) when shutdown_requests have been sent to all teammates, the team-lead should transition into a `/loop` dynamic-mode session that ticks every ~60s (60s minimum per ScheduleWakeup clamps, but cache-friendly) and re-checks each agent's shutdown progress, re-sending `shutdown_request` to any straggler that hasn't actually shut down. The loop self-bounds: when the team is empty, no ScheduleWakeup is called → loop exits cleanly.

This pattern was empirically verified 2026-04-25 in this session — `/loop` launched from the main session via the Skill tool, ScheduleWakeup re-fired the prompt verbatim through the wakeup channel, two ticks landed at 22:37:41Z and 22:39:11Z with no user input between them, and the loop self-terminated.

Adds bounded retries (e.g., 10-tick cap) + a force-shutdown fallback (TaskStop on the owning task) for stuck agents.

Generalizes beyond build-prd: any wheel pipeline with post-pipeline async work (waiting for CI, polling for completion of deferred work, nagging shutdown) can use the same "wheel pipeline ends → main session enters /loop" handoff pattern. The wheel workflow itself can't host `/loop` because hook-driven workflow lifecycle and `/loop`'s pacing lifecycle conflict — the transition has to happen at workflow end, in the main session's free turn.
