# Interface Contracts: Analyze Issues Skill

**Date**: 2026-04-01
**Feature**: analyze-issues

## Skill Interface

The analyze-issues skill is a single SKILL.md file. It has no programmatic API — it is a set of instructions that Claude follows when the user invokes `/analyze-issues`. The "interface" is the skill's input/output contract.

### Skill Invocation

```
Command: /analyze-issues [--reanalyze]
Arguments: Optional --reanalyze flag
```

### Input Contract

| Input | Source | Format | Required |
|-------|--------|--------|----------|
| `$ARGUMENTS` | User command line | String, may contain `--reanalyze` | No |
| Open GitHub issues | `gh issue list` | JSON array of issue objects | Yes (runtime) |

### Output Contract

The skill produces the following outputs:

#### 1. GitHub Label Operations (side effects)

For each analyzed issue:
- Apply `category:<name>` label (one of: `category:skills`, `category:agents`, `category:hooks`, `category:templates`, `category:scaffold`, `category:workflow`, `category:other`)
- Apply `analyzed` label

Labels created if they don't exist:
- `category:skills` (color: `#0E8A16`)
- `category:agents` (color: `#1D76DB`)
- `category:hooks` (color: `#D93F0B`)
- `category:templates` (color: `#FBCA04`)
- `category:scaffold` (color: `#B60205`)
- `category:workflow` (color: `#5319E7`)
- `category:other` (color: `#C5DEF5`)
- `analyzed` (color: `#EDEDED`)

#### 2. Issue Closure (conditional, user-confirmed)

Issues closed via `gh issue close <number>` after user confirmation.

#### 3. Backlog Items (conditional, user-selected)

`.kiln/issues/` entries created via `/report-issue #<number>` for user-selected flagged issues.

#### 4. Summary Report (terminal output)

```
## Analysis Summary

| Metric                  | Count |
|-------------------------|-------|
| Total issues analyzed   | N     |
| Categories assigned     | N     |
| Flagged as actionable   | N     |
| Suggested for closure   | N     |
| Issues closed           | N     |
| Backlog items created   | N     |
```

### SKILL.md Structure Contract

The SKILL.md file MUST follow this structure:

```yaml
---
name: analyze-issues
description: <one-line description>
---
```

Followed by markdown sections in this order:

1. `# Analyze Issues` — title
2. `## User Input` — captures `$ARGUMENTS`
3. `## Step 1: Validate Prerequisites` — check `gh` CLI
4. `## Step 2: Fetch Open Issues` — `gh issue list` with JSON output
5. `## Step 3: Filter Issues` — skip analyzed unless `--reanalyze`
6. `## Step 4: Analyze Each Issue` — categorize + assess actionability
7. `## Step 5: Present Results` — grouped by category with flags
8. `## Step 6: Handle Closures` — suggest + confirm + close
9. `## Step 7: Create Labels` — apply category + analyzed labels
10. `## Step 8: Offer Backlog Creation` — invoke `/report-issue` for selected
11. `## Step 9: Summary Report` — display final counts
12. `## Rules` — constraints and guardrails

### Bash Command Contracts

These are the exact `gh` CLI commands the skill will use:

```bash
# Fetch issues (Step 2)
gh issue list --state open --json number,title,body,labels,createdAt,updatedAt --limit 50

# Create label if not exists (Step 7)
gh label create "<label-name>" --color "<hex>" --force

# Apply labels to issue (Step 7)
gh issue edit <number> --add-label "category:<name>,analyzed"

# Close issue (Step 6)
gh issue close <number> --comment "Closed by /analyze-issues: <reason>"
```
