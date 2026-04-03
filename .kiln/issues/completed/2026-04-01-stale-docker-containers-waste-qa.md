---
title: "Stale Docker containers waste QA cycles — pipeline needs container rebuild awareness"
type: bug
severity: critical
category: workflow
source: analyze-issues
github_issue: "#18, #23, #19, #17"
status: prd-created
date: 2026-04-01
---

## Description

The pipeline has zero awareness of containerized projects. When implementers commit code, running Docker containers still serve the old build. QA tests against stale code, gets false failures, wastes a full cycle, and someone has to manually rebuild. This happened in at least 4 separate pipeline runs (#18, #23, #19, #17).

In #18 alone, at least 3 full QA runs were wasted (~45 minutes of agent compute) plus 8 targeted reruns. The QA agent had to diagnose the stale container each time instead of testing code.

## Impact

Critical — every containerized pipeline run wastes 1-3 full QA cycles. This is the single most reported friction point across all retrospectives.

## Suggested Fix

- Add a Docker rebuild step to the build-prd orchestration between implementation and QA phases
- The team lead prompt should include: "After implementer completes and before QA starts, rebuild the Docker image and verify BUILD_ID > latest implementation commit hash"
- QA agent prompt should include: "Before running tests, verify the running container reflects the latest commits. If stale, rebuild before proceeding."
- Consider adding container-awareness to `qa-engineer.md` and `qa-checkpoint/SKILL.md`

## Source Retrospectives

- #18: CRITICAL — 3+ wasted QA runs, 8 targeted reruns needed
- #23: Stale Docker image caused full QA round to fail with 404s
- #19: QA flagged stale code, implementer had to rebuild mid-QA
- #17: QA blocked at checkpoint 2 by stale container

prd: docs/features/2026-04-01-pipeline-reliability/PRD.md
