---
title: "Wheel workflows should use Write tool for agent step outputs"
type: improvement
severity: medium
category: workflow
source: manual
github_issue: null
status: open
date: 2026-04-28
---
## Description

Wheel workflows need explicit instructions to use the Write tool (instead of Bash heredocs or other methods) when writing their progress/output files. When agents use Bash to write output files, the stop hook cannot detect the output was written (it only detects Write/Edit tools). This causes agents to get stuck in a loop where the stop hook keeps blocking them and removing "stale" output files, even though the agent just wrote them. Lower quality models may be more likely to use Bash instead of the Write tool, compounding the problem.

## Impact

Agents can get stuck in an infinite loop during workflow execution. The stop hook blocks the turn, removes the output file it considers "stale", and instructs the agent to write again — but since the agent used Bash, the hook never detects the write and the cycle repeats.

## Suggested Fix

1. Update wheel workflow agent step instructions to explicitly require the Write tool for output files
2. Add a note to the stop hook logic about stale output detection — consider tracking recently-written files in the current session to avoid removing them
3. Alternatively, enhance the post-tool-use hook to also detect Bash file write patterns (e.g., `cat > file << EOF`)

.kiln/issues/2026-04-28-wheel-workflow-write-tool.md