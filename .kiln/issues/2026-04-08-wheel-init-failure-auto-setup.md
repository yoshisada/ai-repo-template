---
title: "Wheel activation should detect missing setup and offer auto-install"
type: improvement
severity: medium
category: workflow
source: manual
github_issue: null
status: prd-created
prd: docs/features/2026-04-09-plugin-polish-and-skill-ux/PRD.md
date: 2026-04-08
---

## Description

When wheel workflow initiation fails (e.g., activate.sh errors, missing hooks, no .wheel/ directory), the error is opaque. The skill should detect whether wheel was correctly set up for this repo and, if not, suggest automatically setting it up (e.g., running the wheel init/scaffold process).

## Impact

Users who haven't installed the wheel plugin or whose setup is incomplete get confusing errors instead of a helpful recovery path.

## Suggested Fix

In the wheel-run skill (or activate.sh), add a pre-flight check:
1. Verify wheel hooks are registered in settings.json
2. Verify .wheel/ directory exists (or can be created)
3. If checks fail, print a clear message: "Wheel is not set up for this repo. Run `/wheel-init` to configure it."
4. Optionally offer to run the setup automatically.
