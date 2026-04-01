---
title: "Create a better template for issue submission"
type: improvement
severity: medium
category: templates
source: manual
github_issue: null
status: open
date: 2026-04-01
---

## Description

The current `/report-issue` skill uses a hardcoded markdown template embedded in the skill prompt. We need a dedicated, customizable template file for issue submission that lives in `plugin/templates/` — similar to how spec, plan, and tasks already have templates. This would allow consumers to customize issue fields and structure for their project.

## Impact

- Plugin maintainers can't iterate on the issue format without editing the skill prompt directly
- Consumer projects can't customize issue templates to match their own triage workflows
- Consistency between issue entries depends entirely on the skill prompt reproducing the format correctly each time

## Suggested Fix

1. Extract the issue markdown structure from the `/report-issue` skill into `plugin/templates/issue.md`
2. Update the skill to read from the template file instead of using an inline format
3. Have `init.mjs` scaffold the template into consumer projects so they can customize it
