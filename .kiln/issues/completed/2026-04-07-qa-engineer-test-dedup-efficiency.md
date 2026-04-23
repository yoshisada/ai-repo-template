---
title: "QA engineer should audit tests for overlap and efficiency"
type: improvement
severity: medium
category: agents
source: manual
github_issue: null
status: completedcompleted_date: 2026-04-23
pr: merged-pre-tracking
prd: docs/features/2026-04-07-developer-tooling-polish/PRD.md
date: 2026-04-07
---

## Description

The QA engineer agent should read over QA tests to make sure none overlap and look for lost efficiency. Currently the QA engineer runs tests but doesn't analyze the test suite itself for redundancy or waste.

This could be implemented as an additional agent step in the QA workflow — a dedicated "test audit" pass that reviews the generated test suite before or after execution to identify:
- Duplicate or overlapping test scenarios
- Tests that cover the same code paths redundantly
- Opportunities to consolidate similar tests
- Tests that could be more targeted/efficient

## Impact

Redundant tests waste CI time and make test suites harder to maintain. A test audit step would catch this during the pipeline rather than letting test bloat accumulate.

## Suggested Fix

Add a new agent step to the QA engineer workflow (or as a separate agent) that reads the test files, analyzes coverage overlap, and reports findings. Could be positioned after test generation but before execution, or as a post-execution review.
