---
title: Monitor tasks aren't auto-stopped when an interactive CLI test completes
date: 2026-04-25
status: open
kind: friction
priority: low
repo: https://github.com/yoshisada/ai-repo-template
tags:
  - tooling
  - monitor
  - tasks
  - lifecycle
source: kiln-report-issue
---

# Monitor tasks aren't auto-stopped when an interactive CLI test completes

## Description

When running an interactive verification test from the Claude Code CLI
(e.g. `/kiln:kiln-test kiln pi-apply-empty-backlog`), the typical pattern
is:

1. Spawn the test as a background Bash task.
2. Arm a `Monitor` against the task's output file with a grep filter for
   terminal markers (`ok `, `not ok `, `Bail out!`, `exit=`, etc.).
3. The background Bash task completes; the monitor fires its event;
   the model relays the verdict to the user.

After step 3, the monitor is no longer useful — its purpose was to
notify on the one-and-done completion of the underlying task. But
the monitor stays armed until either:

- Its `timeout_ms` expires (default 5 min, often set to 15 min for
  long tests), OR
- Someone calls `TaskStop` against the monitor's task ID.

In this 2026-04-25 session, two monitors (`bmm7tx7ol`, `bsrv73jyo`)
remained armed for 15 minutes each after their underlying tests
finished, until the user noticed and asked "looks like there is still
a monitor running?"

## Why it's friction, not a bug

The Monitor primitive is correctly designed for indefinite watches
(unbounded `tail -F`, `inotifywait -m`). The pattern this issue
describes — "monitor a one-shot completion" — could just use
`run_in_background: true` on the underlying Bash with no monitor at
all (the Bash task itself emits a completion notification). The
monitor was redundant for the one-shot case.

## Proposed fix (one of)

1. **Documentation / agent-side** — update the model's playbook to
   prefer `run_in_background: true` for one-shot completions; reserve
   `Monitor` for unbounded streams. (Cheapest; no code change.)
2. **Auto-stop monitor when watched-file producer exits** — if the
   monitor is `tail -F`'ing a file written by a known background
   task, exit the monitor when that task completes. Requires the
   monitor harness to know the producer→consumer link. (Higher cost.)
3. **Self-stop on first event** — add a `stop_after_first_event: true`
   flag to `Monitor` so the watcher exits cleanly after emitting one
   notification. Useful for the one-shot case without abandoning the
   `tail -F` ergonomics. (Medium cost; opt-in, no breaking change.)

Option 1 is the lowest-blast — pure agent-behavior tweak documented
in CLAUDE.md or an agent-prompt include.

## Workaround

Call `TaskStop <monitor_task_id>` immediately after relaying the
verdict, OR don't arm a monitor in the first place — `Bash` with
`run_in_background: true` already emits a `<task-notification>` when
the task completes.
