---
title: Typed inputs/outputs schema verified live (post-PR #166)
date: 2026-04-25
status: completed
completed_date: 2026-04-25
pr: "#168"
kind: smoke-test-result
priority: low
repo: https://github.com/yoshisada/ai-repo-template
tags:
  - smoke-test
  - wheel
  - typed-inputs-outputs
  - post-merge-verification
  - kiln-report-issue
source: kiln-report-issue
---

# Typed inputs/outputs schema verified live (post-PR #166)

## Summary

Live `/kiln:kiln-report-issue` smoke run after PR #166 merged + plugins reloaded. Confirms the typed `inputs:` + `output_schema:` schema works end-to-end against the post-merge cached install:

- Cached plugin is `kiln/000.001.009.567` shipping the migrated `kiln-report-issue.json` v3.2.0
- `dispatch-background-sync` step declares all 5 inputs (ISSUE_FILE, OBSIDIAN_PATH, CURRENT_COUNTER, THRESHOLD, SHELF_DIR)
- Wheel runtime hydrates these at dispatch time per FR-G3-1/FR-G3-2

This closes the NFR-G-4 live-smoke gate that the in-pipeline auditor couldn't satisfy directly (sub-agent context can't drive wheel hooks). The audit relied on the perf-driver substrate + structural fixture (21/21 PASS); this run is the first true end-to-end verification of the migrated workflow against the post-merge cache.

## What this issue is

Verification record, not a bug. Filed via `/kiln:kiln-report-issue` itself as a meta-test — the migrated workflow being exercised IS the verification vehicle. Auto-archives when the workflow completes successfully.

## Pre/post comparison (from audit-perf-results.tsv)

- **Wall-clock**: 11.77s → 7.46s (-37%)
- **duration_api_ms**: 8099ms → 4030ms (-50%)
- **num_turns**: 3 → 2 (one fewer agent round-trip)
- **output_tokens**: 402 → 180 (-55%)
- **Cost**: $0.1415 → $0.1179 (-17%)
