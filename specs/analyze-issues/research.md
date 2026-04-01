# Research: Analyze Issues Skill

**Date**: 2026-04-01

## R1: gh CLI Issue Operations

**Decision**: Use `gh issue list --json number,title,body,labels,createdAt,updatedAt --limit 50` to fetch issues, `gh issue edit` to apply labels, `gh issue close` to close issues, and `gh label create` to create labels.

**Rationale**: The `gh` CLI is the standard tool for GitHub operations in kiln skills. It supports JSON output for structured parsing and all required operations (list, label, close).

**Alternatives considered**:
- GitHub REST API via `curl`: More verbose, requires manual auth header management. `gh` handles auth automatically.
- GraphQL API: More powerful but unnecessarily complex for this use case.

## R2: Label Creation Strategy

**Decision**: Use `gh label create <name> --force` which creates the label if it doesn't exist and is a no-op if it already exists. This makes label creation idempotent.

**Rationale**: The `--force` flag on `gh label create` prevents errors on subsequent runs. Labels need specific colors for visual consistency in GitHub UI.

**Alternatives considered**:
- Check if label exists first via `gh label list`: Extra API call per label, race condition possible. `--force` is simpler.

## R3: Categorization Method

**Decision**: Claude reads each issue's title and body and assigns a category based on keyword matching and semantic understanding. The skill provides categorization guidelines in the SKILL.md instructions.

**Rationale**: As a kiln skill, Claude is the executor. Claude can understand context better than regex-based keyword matching. The categories are well-defined and map to specific subsystems.

**Alternatives considered**:
- Keyword-based regex matching: Fragile, misses context. An issue titled "hook should use agent pattern" could be either hooks or agents — Claude can determine intent.

## R4: Reanalyze Flag Handling

**Decision**: Parse `$ARGUMENTS` for `--reanalyze` flag. When present, skip the label filter and process all open issues. When absent, filter out issues with the `analyzed` label.

**Rationale**: Simple flag parsing in the skill instructions. The `gh issue list` command supports `--label` for filtering, but for exclusion we filter in the processing loop.

## R5: Integration with /report-issue

**Decision**: After flagging actionable issues, present them to the user and invoke `/report-issue #<number>` for each selected issue. The existing `/report-issue` skill already handles GitHub issue import via issue number.

**Rationale**: Reuses existing skill infrastructure. `/report-issue` already handles classification, file creation, and duplicate detection.
