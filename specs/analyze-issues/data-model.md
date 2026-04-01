# Data Model: Analyze Issues Skill

**Date**: 2026-04-01

## Entities

### GitHub Issue (input, read-only except labels)

| Field | Type | Description |
|-------|------|-------------|
| number | integer | GitHub issue number |
| title | string | Issue title |
| body | string | Issue body (markdown) |
| labels | string[] | Current labels on the issue |
| createdAt | datetime | When the issue was created |
| updatedAt | datetime | When the issue was last updated |

### Analysis Result (transient, per-issue)

| Field | Type | Description |
|-------|------|-------------|
| issueNumber | integer | Reference to the GitHub issue |
| category | enum | One of: skills, agents, hooks, templates, scaffold, workflow, other |
| isActionable | boolean | Whether the issue contains actionable feedback |
| actionableReason | string | Why the issue is worth acting on (empty if not actionable) |
| suggestClose | boolean | Whether the issue should be suggested for closure |
| closeReason | string | Why the issue should be closed (empty if not suggested) |

### Summary Report (transient, end-of-run)

| Field | Type | Description |
|-------|------|-------------|
| totalAnalyzed | integer | Number of issues processed |
| categoryCounts | map<string, integer> | Count per category |
| actionableFlagged | integer | Number flagged as actionable |
| closureSuggested | integer | Number suggested for closure |
| closedCount | integer | Number actually closed (after confirmation) |
| backlogCreated | integer | Number of backlog items created |

## Relationships

- Each GitHub Issue produces exactly one Analysis Result
- All Analysis Results are aggregated into one Summary Report
- Flagged actionable issues may become `.kiln/issues/` backlog items (via `/report-issue`)

## State Transitions

GitHub Issue labels progress through:
1. **Unlabeled** (no `analyzed` tag) -> eligible for analysis
2. **Analyzed** (`analyzed` + `category:*` labels applied) -> skipped on next run
3. **Closed** (if user confirms closure suggestion) -> no longer appears in open issues

## Notes

- No persistent data model is introduced. All analysis results are transient within the skill run.
- The only persistent side effects are: GitHub labels applied, issues closed, and `.kiln/issues/` files created.
