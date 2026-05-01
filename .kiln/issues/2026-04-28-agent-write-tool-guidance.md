---
title: "Agent steps need Write tool guidance to avoid schema violations"
type: improvement
severity: medium
category: workflow
source: manual
github_issue: null
status: open
date: 2026-04-28
---
## Description

Agent steps in wheel workflows need explicit instructions to use the Write tool (instead of Bash heredocs) when writing output files. When an agent writes output via Bash, the post-tool-use hook cannot detect the write occurred — it only detects Write/Edit tool calls. This causes schema validation to fail and marks the step as failed, even though the output was actually written. Lower quality models are more likely to default to Bash file writing, compounding the problem.

## Impact

Agents can get stuck in a loop or fail schema validation unnecessarily. The stop hook sees the output file exists but the post-tool-use hook didn't fire for the Bash write, leading to inconsistent step completion behavior.

## Suggested Fix

1. Update agent step instructions in wheel workflows to explicitly require Write tool for output files
2. Ensure post-tool-use hook detects Bash file write patterns (e.g., cat > file << EOF)
3. Consider re-validation on stop hook when output file exists but step is still pending

.kiln/issues/2026-04-28-agent-write-tool-guidance.md