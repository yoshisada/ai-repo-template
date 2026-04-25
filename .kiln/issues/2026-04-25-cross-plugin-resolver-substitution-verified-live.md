---
title: Cross-plugin-resolver substitution verified live (PR #165)
date: 2026-04-25
status: verified
kind: smoke-test-result
priority: low
repo: https://github.com/yoshisada/ai-repo-template
tags:
  - smoke-test
  - cross-plugin-resolver
  - verified
  - wheel
  - state-persistence
source: kiln-report-issue
---

# Cross-plugin-resolver substitution verified live (PR #165)

## Summary

Live `/kiln:kiln-report-issue` smoke run after PR #165 merged confirms the cross-plugin-resolver works end-to-end:

- New wheel state file (`state_f72781b5-…_1777097648_12406.json`) has `workflow_definition: true`
- The `dispatch-background-sync` step's `instruction` field already contains the literal absolute path:
  `bash "/Users/ryansuematsu/.claude/plugins/cache/yoshisada-speckit/shelf/000.001.009.498/scripts/shelf-counter.sh" read`
- No `${WHEEL_PLUGIN_shelf}` token survives into the embedded workflow definition

This closes the live-verification gap captured in `.kiln/mistakes/2026-04-25-assumed-component-fixtures-equal-end-to-end-coverage.md`.

## Pre/post

- **Before PR #165** (verified earlier this session): same workflow leaked `${WHEEL_PLUGIN_shelf}` to the agent prompt → bash silently expanded to empty → `bash: /scripts/shelf-counter.sh: No such file or directory`
- **After PR #165**: state-embedded templated workflow → engine_init reads from state → agent receives literal path → bash runs the real script

## What this issue is

This is a verification record, not a bug. Filed via `/kiln:kiln-report-issue` itself as a meta-test (the workflow being verified is also the workflow being run to verify it). Auto-archives when the linked PR closes its loop.
