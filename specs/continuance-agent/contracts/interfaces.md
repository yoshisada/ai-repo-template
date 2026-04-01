# Interface Contracts: Continuance Agent (/next)

**Date**: 2026-03-31
**Feature**: [spec.md](../spec.md)

## Overview

This feature delivers markdown-based skill and agent definitions for the kiln plugin. There are no compiled functions or programmatic interfaces. The "interfaces" here are the file contracts that define the structure and behavior of each deliverable.

## Skill Contract: /next (plugin/skills/next/SKILL.md)

### Frontmatter

```yaml
---
name: "next"
description: "Analyze full project state and produce prioritized next steps mapped to kiln commands. Replaces /resume. Run at session start or after /build-prd."
---
```

### Input

- `$ARGUMENTS` — optional flags:
  - `--brief` — output top 5 recommendations only, do not save report file

### Behavior

1. **Read project context**: VERSION, current branch, constitution
2. **Gather state from all sources** (via bash commands):
   - `specs/*/tasks.md` — grep for `[ ]` (incomplete) and `[X]` (complete) items
   - `specs/*/blockers.md` — read if exists
   - `specs/*/retrospective.md` — read if exists, extract action items
   - `.kiln/qa/` — read QA reports (QA-REPORT.md, QA-PASS-REPORT.md, UX-REPORT.md)
   - `.kiln/issues/` — read all open issue files
   - `specs/*/spec.md` — cross-reference FRs against tasks to find unimplemented requirements
   - GitHub issues — `gh issue list --state open --json number,title,labels` (skip if `gh` unavailable)
   - GitHub PR comments — `gh pr list --state open --json number,title,comments` (skip if `gh` unavailable)
3. **Classify each finding** into a category:
   - `blocker` — items from blockers.md, failing tests that prevent progress
   - `incomplete-work` — unchecked tasks from tasks.md
   - `qa-audit-gap` — QA failures, audit compliance gaps
   - `backlog` — open issues in `.kiln/issues/` and GitHub issues
   - `improvement` — retrospective action items, optimization suggestions
4. **Assign priority** based on category:
   - `critical` — blockers
   - `high` — incomplete work from most recent build
   - `medium` — QA/audit gaps
   - `low` — backlog items and improvements
5. **Map each finding to a kiln command**:
   - Incomplete task → `/implement`
   - Failing test → `/fix <description>`
   - QA finding → `/fix <description>` or `/qa-pass`
   - Audit gap → `/implement` or `/fix`
   - Unimplemented FR → `/specify` (if no spec) or `/implement` (if spec exists)
   - Backlog item → `/fix <description>` or `/specify` (if new feature needed)
   - Retrospective action → `/specify`, `/fix`, or specific file edit
6. **Create backlog issues** for untracked gaps (unless `--brief`):
   - Read existing `.kiln/issues/` filenames and titles
   - For each discovered gap not matching an existing issue, create `<YYYY-MM-DD>-<slug>.md` with `[auto:continuance]` tag
   - Ensure `.kiln/issues/` directory exists before writing
7. **Output terminal summary**: Max 15 items grouped by priority, each with description + command + source
8. **Save report** to `.kiln/logs/next-<YYYY-MM-DD-HHmmss>.md` (unless `--brief`)

### Output Format — Terminal Summary

```markdown
## What's Next

**Project**: [name] | **Branch**: [branch] | **Version**: [version]

[One-sentence project state summary]

### Critical
- [ ] [description] — `/command` _(source: path/to/artifact)_

### High
- [ ] [description] — `/command` _(source: path/to/artifact)_

### Medium
- [ ] [description] — `/command` _(source: path/to/artifact)_

### Low
- [ ] [description] — `/command` _(source: path/to/artifact)_

---
Full report: `.kiln/logs/next-<timestamp>.md`
[N] new backlog items created in `.kiln/issues/`
```

### Output Format — Persistent Report

```markdown
# Continuance Report

**Generated**: <YYYY-MM-DD HH:mm:ss>
**Branch**: [branch]
**Version**: [version]

## Project State Summary

[Paragraph summarizing overall project health]

## Sources Analyzed

- [x] specs/*/tasks.md — [N] incomplete tasks found
- [x] specs/*/blockers.md — [N] blockers found
- [x] .kiln/issues/ — [N] open items
- [ ] GitHub issues — skipped (gh not available)
...

## Recommendations

| # | Priority | Description | Command | Source |
|---|----------|-------------|---------|--------|
| 1 | critical | [desc] | `/fix ...` | specs/auth/blockers.md |
| 2 | high | [desc] | `/implement` | specs/auth/tasks.md:L42 |
...

## Backlog Updates

- Created: `.kiln/issues/2026-03-31-missing-validation.md` [auto:continuance]
- Skipped (already tracked): "Login timeout" matches `.kiln/issues/2026-03-30-login-timeout.md`
```

---

## Skill Contract: /resume (plugin/skills/resume/SKILL.md) — MODIFIED

### Frontmatter

```yaml
---
name: "resume"
description: "Deprecated — use /next instead. Runs /next with a deprecation notice."
---
```

### Behavior

1. Print deprecation notice: "Note: `/resume` has been replaced by `/next`. Please use `/next` going forward."
2. Execute the full `/next` workflow (same logic, no flags)

---

## Agent Contract: continuance (plugin/agents/continuance.md)

### Frontmatter

```yaml
---
name: "continuance"
description: "Analyzes full project state and produces prioritized next steps mapped to kiln commands. Used by /next skill and as the final step in /build-prd."
model: sonnet
---
```

### Role

The continuance agent is a reference definition that documents the agent's analysis methodology. The `/next` skill contains the executable logic. The agent definition exists for:
- Documentation of the agent's role in the kiln ecosystem
- Potential future use as a spawned teammate in build-prd if the analysis grows complex enough to warrant it

### Analysis Methodology

1. Scan all project state sources (same list as /next skill contract)
2. Classify findings by category (blocker → incomplete → qa/audit → backlog → improvement)
3. Assign priorities (critical → high → medium → low)
4. Map each finding to the most specific applicable kiln command
5. Deduplicate against existing `.kiln/issues/` entries
6. Produce structured output (terminal + persistent report)

---

## Build-prd Integration Contract (plugin/skills/build-prd/skill.md) — MODIFIED

### Integration Point

After the retrospective step completes and before PR creation, the team lead invokes `/next` to produce continuance analysis.

### Behavior

1. Team lead detects retrospective task completion
2. Team lead runs `/next` (not `--brief`) to get full analysis
3. Continuance output is included in the terminal summary
4. Continuance report is saved to `.kiln/logs/`
5. If `/next` fails, log a warning and proceed with PR creation (advisory, non-blocking)

### Wiring

Add to the build-prd skill's pipeline flow after the retrospective section:
- No new task/teammate needed — team lead invokes the skill directly
- Output included in the final pipeline summary
