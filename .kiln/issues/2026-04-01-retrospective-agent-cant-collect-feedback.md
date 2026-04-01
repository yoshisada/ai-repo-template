---
title: "Retrospective agent can't collect teammate feedback — agents shut down before retro runs"
type: friction
severity: medium
category: agents
source: analyze-issues
github_issue: "#30, #28, #25, #16, #15"
status: open
date: 2026-04-01
---

## Description

The retrospective agent runs last in the pipeline, after all other agents have completed their tasks. By the time it spawns and sends feedback requests, teammates have shut down and cannot respond. This happened in every single pipeline run observed (at least 10 runs across #30, #28, #25, #16, #15, and others).

The retro relies solely on commit history and artifacts rather than first-person friction reports from agents who experienced the issues.

## Impact

Medium — retrospectives are lower quality because they miss subjective friction that only agents experience. The retro can still analyze commits and artifacts, but "what was confusing" and "where I got stuck" signals are lost.

## Suggested Fix

Two options (not mutually exclusive):

1. **Agent handoff notes**: Before each agent shuts down, it writes a brief friction note to `specs/<feature>/agent-notes/<agent-name>.md`. The retrospective agent reads these files instead of relying on live messages.

2. **Earlier retrospective spawn**: Spawn the retrospective agent earlier (alongside implementation) with a blocking dependency. It warms up and can request feedback from agents while they're still active, before they mark their final task complete.

## Source Retrospectives

- #30, #28, #25, #16, #15: All report the same issue — teammates unresponsive to retro feedback requests
