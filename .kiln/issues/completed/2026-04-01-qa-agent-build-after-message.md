---
title: "Add hooks to enforce QA agent builds after every message"
type: feature-request
severity: high
category: hooks
source: manual
github_issue: null
status: prd-created
prd: docs/features/2026-04-01-qa-tooling-templates/PRD.md
date: 2026-04-01
---

## Description

The QA agent (`qa-engineer`) does not reliably run the project build before testing after receiving messages from implementers. This can cause it to test stale artifacts. Two new hooks should be added to `hooks.json` to enforce this:

1. **`SubagentStart`** (matcher: `qa-engineer`) — Injects a persistent `additionalContext` reminder on spawn telling the QA agent it MUST run the project build command (from `plan.md`) after every `SendMessage` it receives, before any testing or evaluation.

2. **`TeammateIdle`** — A `type: "prompt"` hook that checks whether the teammate going idle is the QA agent, and if so, whether it ran a build since its last received message. Blocks going idle with a reason if the build was skipped.

## Impact

Without this, the QA agent may test against outdated build artifacts after implementers push changes, leading to false failures or missed regressions. This is especially problematic during the iterative checkpoint feedback loop in `/build-prd` where implementers and the QA agent exchange messages frequently.

## Suggested Fix

Add the following to `plugin/hooks/hooks.json`:

```json
"SubagentStart": [
  {
    "matcher": "qa-engineer",
    "hooks": [
      {
        "type": "command",
        "command": "echo '{\"additionalContext\": \"BUILD REQUIREMENT: After receiving EVERY SendMessage, you MUST run the project build command (from plan.md) BEFORE performing any testing or evaluation. Never skip this step.\"}'"
      }
    ]
  }
],
"TeammateIdle": [
  {
    "hooks": [
      {
        "type": "prompt",
        "prompt": "Check if this teammate is a QA agent (qa-engineer). If it is, check whether the most recent actions include running a build command. If the QA agent has NOT run a build since its last received message, respond with {\"ok\": false, \"reason\": \"You must run the project build before going idle. Check plan.md for the build command.\"}. If it has built or is not a QA agent, respond with {\"ok\": true}."
      }
    ]
  }
]
```
