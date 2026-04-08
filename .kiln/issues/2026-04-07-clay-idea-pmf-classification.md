---
title: "Clay idea skill should classify ideas by market intent"
type: feature-request
severity: medium
category: skills
source: manual
github_issue: null
status: open
date: 2026-04-07
---

## Description

The `/clay:idea` skill should ask whether the idea is for internal use only, marketable as a product, or needs product-market fit validation. This classification affects the entire downstream pipeline:

- **Internal tool**: Skip market research, simpler PRD, no naming/branding concerns
- **Marketable product**: Full pipeline — research competitors, name carefully, detailed PRD with pricing/users
- **PMF exploration**: Focus research on validating demand, include customer discovery questions in PRD

Currently `/clay:idea` routes based on overlap detection but doesn't consider the idea's market intent, which changes what research and PRD depth is appropriate.

## Impact

Without this classification, clay treats every idea the same — running full market research for internal tools wastes time, while skipping it for marketable products misses critical validation.

## Suggested Fix

Add a classification step early in `/clay:idea` that asks the user about market intent, then adjust the pipeline depth accordingly. Could be as simple as a multiple-choice question before routing.
