---
title: "Pipeline lacks agent health-checks and phase dependency enforcement"
type: bug
severity: critical
category: workflow
source: analyze-issues
github_issue: "#11, #26, #19"
status: prd-created
date: 2026-04-01
---

## Description

Two related failures in pipeline orchestration:

### 1. No stall detection or timeout (CRITICAL)
In #11, the specifier agent stalled after producing spec.md — it never ran /plan or /tasks. The entire pipeline hung indefinitely. No other agent or the team lead detected it. Downstream agents waited forever because their tasks were blocked by the specifier. There is no watchdog, timeout, or health-check mechanism.

### 2. Phase dependencies are documentation-only
In #26, implementers started Phase 2 and Phase 3 before Phase 1 completed, despite tasks.md explicitly stating "Phase 2 depends on Phase 1 completion." Phase 2 landed 2 minutes before Phase 1. The dependency annotations in tasks.md are text that agents ignore because there's no enforcement mechanism.

### 3. Implementer self-blocking
In #19, the implementer held a task waiting for QA validation before proceeding because the prompt says "STOP and VALIDATE" at checkpoints, which the agent interpreted as "wait for external QA" rather than "self-validate and move on."

## Impact

Critical — #11 caused 100% pipeline failure (no implementation, no tests, no PR). #26 caused merge-order issues requiring additional fix commits.

## Suggested Fix

1. **Add agent timeout**: If an agent's task stays `in_progress` for >N minutes without commits or messages, the team lead should check in or escalate
2. **Enforce phase gating**: Dispatch impl agents in dependency order. Use TaskUpdate blockedBy to enforce ordering. Only send Phase 2/3 agents their prompts after Phase 1 agent's task is completed
3. **Clarify "STOP and VALIDATE"**: Change the implement prompt to distinguish "self-validate (run tests locally)" from "wait for external QA feedback"

## Source Retrospectives

- #11: CRITICAL — pipeline stalled completely, no recovery
- #26: CRITICAL — Phase 2 committed before Phase 1
- #19: Implementer blocked itself misinterpreting "STOP and VALIDATE"

prd: docs/features/2026-04-01-pipeline-reliability/PRD.md
