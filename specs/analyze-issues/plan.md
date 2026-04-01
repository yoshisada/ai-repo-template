# Implementation Plan: Analyze Issues Skill

**Branch**: `build/analyze-issues-20260401` | **Date**: 2026-04-01 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/analyze-issues/spec.md`

## Summary

Create a new kiln skill (`/analyze-issues`) that reads open GitHub issues via `gh`, categorizes them using the existing backlog category scheme, labels them, flags actionable ones with explanations, suggests closures with user confirmation, offers backlog item creation via `/report-issue`, and displays a summary report. The skill is a markdown file (`SKILL.md`) with embedded bash commands, following the same pattern as existing kiln skills like `/report-issue` and `/analyze`.

## Technical Context

**Language/Version**: Markdown (skill definition) + Bash (shell commands within skill via `gh` CLI)
**Primary Dependencies**: `gh` CLI (GitHub CLI), existing `/report-issue` skill
**Storage**: N/A (labels applied to GitHub issues, backlog items written to `.kiln/issues/`)
**Testing**: Manual testing by running the skill on a repo with open issues
**Target Platform**: Any platform with `gh` CLI installed and authenticated
**Project Type**: Claude Code plugin skill (markdown file auto-discovered by plugin system)
**Performance Goals**: Process up to 50 issues per run
**Constraints**: Requires `gh` CLI authenticated with write access to repo labels/issues
**Scale/Scope**: Single skill file, single SKILL.md

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Gate | Status | Notes |
|------|--------|-------|
| Spec-First Development | PASS | spec.md exists at specs/analyze-issues/spec.md |
| 80% Test Coverage | N/A | This is a skill definition (markdown), not compiled code. No test suite applies. |
| PRD as Source of Truth | PASS | PRD at docs/features/2026-04-01-analyze-issues/PRD.md, spec aligns with it |
| Hooks Enforce Rules | PASS | Existing hooks allow edits to plugin/ skills (not src/) |
| E2E Testing Required | N/A | Skill is markdown — tested by running `/analyze-issues` on a live repo |
| Small, Focused Changes | PASS | Single SKILL.md file, well-bounded scope |
| Interface Contracts | PASS | contracts/interfaces.md will define the skill's interface |
| Incremental Task Completion | PASS | Will be enforced during implementation |

## Project Structure

### Documentation (this feature)

```text
specs/analyze-issues/
├── spec.md
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── contracts/
│   └── interfaces.md    # Phase 1 output
└── tasks.md             # Phase 2 output (created by /tasks)
```

### Source Code (repository root)

```text
plugin/skills/analyze-issues/
└── SKILL.md             # The skill definition — single file deliverable
```

**Structure Decision**: Single skill file in `plugin/skills/analyze-issues/SKILL.md`, following the established pattern of all other kiln skills. No additional source files, no tests directory, no build artifacts.

## Deployment Readiness

| Artifact | Path | Required? | Notes |
|----------|------|-----------|-------|
| SKILL.md | plugin/skills/analyze-issues/SKILL.md | Yes | Auto-discovered by plugin system |
| Dockerfile | N/A | No | Not applicable |
| CI config | N/A | No | Existing CI covers plugin |
| Env template | N/A | No | Uses existing `gh` auth |

**Deployment notes**: The skill is auto-discovered by Claude Code's plugin system when placed in `plugin/skills/analyze-issues/SKILL.md`. No additional configuration, registration, or build steps needed. The `gh` CLI must be available in the user's environment.

## Technical Design

### Skill Structure

The SKILL.md follows the established kiln skill pattern:

1. **YAML frontmatter**: name, description metadata
2. **User Input section**: Captures `$ARGUMENTS` (supports `--reanalyze` flag)
3. **Step-by-step execution**: Sequential instructions for Claude to follow
4. **Bash commands**: Inline `gh` CLI commands for GitHub operations

### Execution Flow

```
Step 1: Validate prerequisites (gh CLI available, authenticated)
Step 2: Fetch open issues (gh issue list --json, limit 50)
Step 3: Filter issues (skip analyzed unless --reanalyze)
Step 4: For each issue — categorize, determine actionability, determine closure suggestion
Step 5: Present results grouped by category
Step 6: Flag actionable issues with explanations
Step 7: Suggest closures with reasons, prompt for confirmation
Step 8: Apply labels (category + analyzed) via gh issue edit
Step 9: Close confirmed issues via gh issue close
Step 10: Offer backlog creation for flagged issues via /report-issue
Step 11: Display summary report
```

### GitHub Label Strategy

- Category labels: `category:skills`, `category:agents`, `category:hooks`, `category:templates`, `category:scaffold`, `category:workflow`, `category:other`
- Analysis label: `analyzed`
- Labels are created via `gh label create` if they don't exist (idempotent — `gh label create` is safe to re-run)

### Categorization Approach

The skill instructs Claude to categorize based on issue content:
- **skills**: Issues about skill behavior, prompts, flow, or new skill requests
- **agents**: Issues about agent definitions, team structure, agent behavior
- **hooks**: Issues about enforcement rules, hook behavior, gate logic
- **templates**: Issues about spec/plan/task templates
- **scaffold**: Issues about init script, project structure, scaffolding
- **workflow**: Issues about kiln pipeline, build-prd orchestration, process flow
- **other**: Issues that don't fit the above categories

### Actionability Assessment

The skill instructs Claude to flag issues as actionable when they contain:
- Concrete improvement suggestions with clear implementation paths
- Bug reports with reproducible steps
- Process changes that would measurably improve workflow
- Performance or reliability concerns with specific evidence

Non-actionable (suggest for closure):
- Pure informational summaries with no recommendations
- Issues describing behavior that has already been fixed
- Stale issues (>90 days with no activity and no clear action)
- Duplicates of other open issues

### User Interaction Points

1. **Closure confirmation**: Present suggested closures, ask for individual or batch confirmation
2. **Backlog creation**: Present flagged issues, ask which to convert to backlog items
3. Both interactions use Claude's natural conversation — no custom UI needed

## Complexity Tracking

No constitution violations. Single-file deliverable with no abstractions needed.
