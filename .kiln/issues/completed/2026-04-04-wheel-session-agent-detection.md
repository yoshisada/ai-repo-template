---
title: "Wheel needs session/agent detection so only one agent runs a workflow"
type: improvement
severity: high
category: hooks
source: manual
github_issue: null
status: completed
prd: docs/features/2026-04-05-wheel-session-guard/PRD.md
date: 2026-04-04
---

## Description

When a wheel workflow is active, its hooks fire on every Claude Code event — including events from subagents that aren't the workflow orchestrator. This means multiple agents can simultaneously try to advance the workflow state, causing race conditions and duplicate step execution. The wheel engine needs a way to detect which session/agent started the workflow and only allow that agent to drive it forward.

## Impact

Any workflow run alongside other agents (e.g., during a `/build-prd` pipeline) risks state corruption. Command steps may execute twice, agent steps may get conflicting instructions, and branch decisions may race. This is a blocker for using wheel workflows inside pipelines with parallel agents.

## Suggested Fix

Add a `session_id` or `agent_id` field to `.wheel/state.json` at creation time (captured from the hook input's session/agent context). In each hook handler, compare the incoming event's session/agent ID against the stored one — if they don't match, return `{"decision": "approve"}` immediately (pass-through). This ensures only the originating agent drives the workflow.
completed_date: 2026-04-05
pr: #54
