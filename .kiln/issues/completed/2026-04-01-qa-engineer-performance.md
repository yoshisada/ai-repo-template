---
title: "QA engineer agent is too slow — optimize video recording and Playwright config"
type: friction
severity: high
category: agents
source: manual
github_issue: null
status: prd-created
prd: docs/features/2026-04-01-qa-tooling-templates/PRD.md
date: 2026-04-01
---

## Description

The QA engineer agent takes too long to run, primarily due to recording video for every test and suboptimal Playwright configuration. Instead of recording every test, produce one final walkthrough video highlighting the latest features added.

Key optimizations:

1. **Switch recordings to failure-only** — change `video: 'on'` / `trace: 'on'` to `'retain-on-failure'` in the Playwright config. Recording every test is the biggest time sink.
2. **Enable `fullyParallel: true`** — the 3 viewport projects (desktop, tablet-768, mobile) currently run serially. Parallelizing them would divide wall-clock time by ~3x.
3. **Replace `networkidle` waits** — use targeted `waitForSelector` or `waitForFunction` instead. `networkidle` waits 500ms of no network activity, which adds up fast.

## Impact

- QA pass runtime is a bottleneck in the `/build-prd` pipeline — slow QA delays the entire feedback loop
- Excessive video recording wastes disk space and agent compute time
- Serial viewport testing multiplies runtime unnecessarily

## Suggested Fix

1. Update the QA engineer agent and `/qa-setup` scaffold to default Playwright config to `video: 'retain-on-failure'` and `trace: 'retain-on-failure'`
2. Add a final walkthrough recording step that captures one clean run of new features after all tests pass
3. Set `fullyParallel: true` in the scaffolded Playwright config
4. Update QA agent instructions to prefer `waitForSelector` over `networkidle` and avoid hardcoded `waitForTimeout` calls
