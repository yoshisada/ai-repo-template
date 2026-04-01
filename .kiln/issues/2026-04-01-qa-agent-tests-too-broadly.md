---
title: "QA agent tests too broadly — runs sitewide regression instead of feature-scoped testing"
type: friction
severity: medium
category: agents
source: analyze-issues
github_issue: "#20"
status: prd-created
prd: docs/features/2026-04-01-qa-tooling-templates/PRD.md
date: 2026-04-01
---

## Description

The QA agent runs a full sitewide regression + UX audit even for small, scoped features. In #20 (signout-button-placement — a 2-file, ~20 line change), the QA agent filed 21 issues for pre-existing sitewide problems unrelated to the feature. The QA report mixed the feature verdict (26/26 pass) with a sitewide UX audit (4/10 score, 21 issues), making it hard to quickly determine the feature's pass/fail status.

## Impact

Medium — inflates QA duration, creates noise in issue trackers, and obscures the feature-specific signal that the team lead and auditor need.

## Suggested Fix

1. **Feature-scoped testing first**: QA agent should focus on the feature's test matrix first and report feature pass/fail as a standalone section
2. **Separate report sections**: Structure QA reports with: (1) Feature Verdict — scoped pass/fail, (2) Regression Findings (optional) — pre-existing issues discovered
3. **Conditional regression**: Only run sitewide regression if explicitly requested or if the feature touches shared components (layout, nav, auth)

## Source Retrospectives

- #20: QA spent most time on pre-existing sitewide issues; 21 issues filed unrelated to feature
