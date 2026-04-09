# Implementation Plan: Plugin Polish & Skill UX

**Branch**: `build/plugin-polish-and-skill-ux-20260409` | **Date**: 2026-04-09 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `specs/plugin-polish-and-skill-ux/spec.md`

## Summary

Polish the kiln plugin for consumer project reliability: ship bundled workflows with `plugin.json` declaration, clean up init scaffold, add wheel pre-flight checks, filter `/next` to high-level commands only, add repo/file backlinks to issue templates, and upgrade trim-push to create full page compositions alongside component frames.

## Technical Context

**Language/Version**: Node.js 18+ (init.mjs), Bash 5.x (hooks, workflows), Markdown (skills/agents)
**Primary Dependencies**: jq, gh CLI (optional), Penpot MCP tools (for trim), wheel engine
**Storage**: File-based (JSON workflows, markdown skills/templates, `.wheel/` state)
**Testing**: Manual pipeline testing via `/build-prd` on consumer projects
**Target Platform**: macOS / Linux (Claude Code runtime)
**Project Type**: Claude Code plugin (npm package)
**Performance Goals**: N/A (developer tooling, not latency-sensitive)
**Constraints**: No new runtime dependencies (NFR-002); workflow files < 50KB total (NFR-003)
**Scale/Scope**: 12 FRs across 6 plugin files + 3 skill/workflow definitions

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Gate | Status | Notes |
|------|--------|-------|
| Spec-first (I) | PASS | spec.md exists with all 12 FRs |
| 80% coverage (II) | N/A | No test suite for plugin itself; testing via pipeline runs |
| PRD as source of truth (III) | PASS | All FRs trace to PRD at docs/features/2026-04-09-plugin-polish-and-skill-ux/PRD.md |
| Hooks enforce rules (IV) | PASS | Not disabling any hooks |
| E2E testing (V) | N/A | Plugin testing is done via pipeline runs on consumer projects |
| Small focused changes (VI) | PASS | Each FR touches 1-2 files |
| Interface contracts (VII) | PASS | Contracts defined below |
| Incremental task completion (VIII) | PASS | Tasks will be marked [X] after each completion |

## Project Structure

### Documentation (this feature)

```text
specs/plugin-polish-and-skill-ux/
├── spec.md
├── plan.md              # This file
├── research.md          # Phase 0 output
├── contracts/
│   └── interfaces.md    # Phase 1 output
├── checklists/
│   └── requirements.md
└── tasks.md             # Phase 2 output
```

### Source Code (files to modify)

```text
plugin-kiln/
├── .claude-plugin/
│   └── plugin.json          # FR-001: Add workflows declaration
├── bin/
│   └── init.mjs             # FR-002: Add workflow sync; FR-006: Remove src/tests creation
├── workflows/
│   └── report-issue-and-sync.json  # FR-001: Already exists, needs declaration
├── templates/
│   └── issue.md             # FR-011: Add repo/files frontmatter fields
├── skills/
│   ├── next/
│   │   └── SKILL.md         # FR-009/010: Add command whitelist filter
│   └── report-issue/
│       └── SKILL.md         # FR-012: Add repo/file auto-detection context

plugin-wheel/
├── skills/
│   └── wheel-run/
│       └── SKILL.md         # FR-007/008: Add pre-flight check

plugin-trim/
├── workflows/
│   └── trim-push.json       # FR-003/004: Add page classification + page-level push steps
├── skills/
│   └── trim-push/
│       └── SKILL.md         # FR-005: Update agent instructions for component vs page
```

**Structure Decision**: No new directories. All changes are modifications to existing plugin files.

## Implementation Phases

### Phase 1: Packaging & Scaffold (FR-001, FR-002, FR-006, FR-007, FR-008)

These are the foundational fixes that affect plugin distribution and consumer onboarding.

**FR-001**: Add `"workflows": ["workflows/report-issue-and-sync.json"]` to `plugin-kiln/.claude-plugin/plugin.json`. The file already exists in `plugin-kiln/workflows/` and `workflows/` is already in `package.json` `files` array.

**FR-002**: In `init.mjs`, add a `syncWorkflows()` function in the `syncShared()` path that:
- Reads `plugin.json` to get the list of declared workflows
- For each workflow, copies it to the consumer's `workflows/` directory only if the file doesn't already exist (respects customizations)

**FR-006**: In `init.mjs` `scaffoldProject()`, remove the loop at lines 89-96 that creates `src/` and `tests/` directories with `.gitkeep` files.

**FR-007/008**: In `plugin-wheel/skills/wheel-run/SKILL.md`, add a Step 0 pre-flight check before Step 1 that:
- Verifies `.wheel/` directory exists
- Checks for wheel hooks in `.claude/settings.json` (or equivalent)
- If either check fails, prints: "Wheel is not set up for this repo. Run `/wheel-init` to configure it."
- Offers to run `/wheel-init` automatically

### Phase 2: Skills & Templates (FR-003, FR-004, FR-005, FR-009, FR-010, FR-011, FR-012)

These are skill behavior changes and template updates.

**FR-009/010**: In `plugin-kiln/skills/next/SKILL.md`, add a command filtering step in Step 4 (Classification and Prioritization) that:
- Defines a whitelist: `/build-prd`, `/fix`, `/qa-pass`, `/create-prd`, `/create-repo`, `/init`, `/analyze-issues`, `/report-issue`, `/ux-evaluate`, `/issue-to-prd`, `/next`, `/todo`, `/roadmap`
- Defines a blocklist: `/specify`, `/plan`, `/tasks`, `/implement`, `/audit`, `/debug-diagnose`, `/debug-fix`
- Filters all command recommendations to only include whitelisted commands
- Replaces internal commands with their high-level equivalents (e.g., `/implement` -> `/build-prd`, `/specify` -> `/build-prd`)

**FR-011**: In `plugin-kiln/templates/issue.md`, add optional `repo` and `files` fields to the frontmatter.

**FR-012**: In `plugin-kiln/skills/report-issue/SKILL.md`, add instructions to:
- Run `gh repo view --json url -q '.url'` to auto-detect repo URL
- Extract file paths mentioned in the issue description
- Populate the `repo:` and `files:` frontmatter fields

**FR-003/004/005**: In `plugin-trim/workflows/trim-push.json` and `plugin-trim/skills/trim-push/SKILL.md`:
- Add a `classify-files` step after `scan-components` that classifies each scanned file as "component" or "page" based on:
  - Directory convention: `components/` -> component, `pages/` or `app/` routes -> page
  - Router references and layout imports as secondary signals
- Modify the `push-to-penpot` agent instruction to handle both types:
  - Components -> "Components" page, bento grid layout
  - Pages -> individual Penpot pages, full-screen composed frames referencing the component library
- Update the SKILL.md description to document both behaviors

## Research Notes

No formal research.md needed — all decisions are based on existing codebase patterns:

- **Workflow declaration format**: Follows `plugin-clay/.claude-plugin/plugin.json` pattern: `"workflows": ["workflows/<name>.json"]`
- **Workflow sync pattern**: Uses same `copyIfMissing()` approach already in `init.mjs`
- **Pre-flight pattern**: Follows existing error checking in `wheel-run/SKILL.md` Step 2
- **Command filtering**: Simple whitelist/blocklist approach, no complex logic needed
- **File classification**: Directory-based heuristic with framework-specific overrides

## Risks & Mitigations

| Risk | Mitigation |
|------|-----------|
| Workflow sync overwrites user customizations | Use `copyIfMissing()` which skips existing files |
| Page classification heuristic is framework-specific | Start with directory conventions (most universal), add framework hints as secondary |
| Pre-flight check is too aggressive | Only check when actually running a workflow, not on every wheel operation |
