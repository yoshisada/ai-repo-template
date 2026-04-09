# Implementation Plan: Trim Design Lifecycle

**Branch**: `build/trim-design-lifecycle-20260409` | **Date**: 2026-04-09 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `specs/trim-design-lifecycle/spec.md`

## Summary

Extend plugin-trim/ with 4 new skills (`/trim-edit`, `/trim-verify`, `/trim-redesign`, `/trim-flows`) and 4 corresponding wheel workflows. Each skill is a markdown file with embedded instructions. Each workflow is a JSON file following the command-first/agent-second pattern. Two new file schemas are introduced: `.trim-changes.md` (design changelog) and `.trim-flows.json` (user flow registry). All deliverables are markdown and JSON — no application code.

## Technical Context

**Language/Version**: Markdown (skill definitions), Bash 5.x (inline shell in skills/workflows), JSON (workflow definitions)
**Primary Dependencies**: Wheel workflow engine (`plugin-wheel/`), Penpot MCP tools, Playwright (headless browser), /chrome MCP (optional fallback)
**Storage**: File-based — `.trim-changes.md`, `.trim-flows.json`, `.trim-verify/` (gitignored screenshots), `.wheel/outputs/`
**Testing**: No test suite for plugin source — testing is done by running skills on consumer projects
**Target Platform**: Claude Code plugin system (macOS/Linux)
**Project Type**: Claude Code plugin (markdown skills + JSON workflows)
**Performance Goals**: Edit-verify cycle under 3 minutes for a single component
**Constraints**: No runtime dependencies beyond Claude Code, Penpot MCP, and Playwright. All Penpot interactions via MCP tools only.
**Scale/Scope**: 4 skills, 4 workflows, 2 file schemas

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Gate | Status | Notes |
|------|--------|-------|
| Spec-First (I) | PASS | spec.md exists with FRs and acceptance scenarios |
| 80% Coverage (II) | N/A | Plugin source repo — no test suite; testing via consumer projects |
| PRD as Source of Truth (III) | PASS | PRD at docs/features/2026-04-09-trim-design-lifecycle/PRD.md |
| Hooks Enforce Rules (IV) | PASS | Existing hooks remain active |
| E2E Testing (V) | N/A | Plugin deliverables are markdown/JSON — no compiled artifact |
| Small Changes (VI) | PASS | Each skill/workflow is self-contained; files under 500 lines |
| Interface Contracts (VII) | PASS | contracts/interfaces.md will define all exported interfaces |
| Incremental Tasks (VIII) | PASS | Tasks will be marked [X] as completed |

## Project Structure

### Documentation (this feature)

```text
specs/trim-design-lifecycle/
├── spec.md
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── contracts/
│   └── interfaces.md    # Phase 1 output
├── checklists/
│   └── requirements.md  # Quality checklist
└── tasks.md             # Phase 2 output (/tasks command)
```

### Source Code (repository root)

```text
plugin-trim/
├── .claude-plugin/
│   └── plugin.json          # Plugin manifest (extended with new skills)
├── skills/
│   ├── trim-edit/
│   │   └── SKILL.md         # Natural language Penpot editing skill
│   ├── trim-verify/
│   │   └── SKILL.md         # Visual verification skill
│   ├── trim-redesign/
│   │   └── SKILL.md         # Full UI redesign skill
│   └── trim-flows/
│       └── SKILL.md         # User flow management skill
├── workflows/
│   ├── trim-edit.json       # Edit workflow (command-first/agent-second)
│   ├── trim-verify.json     # Verification workflow
│   └── trim-redesign.json   # Redesign workflow
└── package.json             # npm package (version bump)
```

**Structure Decision**: This is a plugin source repo. All deliverables go into `plugin-trim/`. Skills are markdown files in `skills/<name>/SKILL.md`. Workflows are JSON files in `workflows/`. The `/trim-flows` skill does not need a workflow because it performs simple file operations (read/write `.trim-flows.json`) that don't require multi-step orchestration — subcommands (add, list, sync, export-tests) are handled inline in the skill.

## Complexity Tracking

No constitution violations. All deliverables are markdown and JSON following established patterns.

## Phase 1: Skills (P1 — Core Deliverables)

Create the 4 skill markdown files. Each skill follows the pattern established by existing plugins (shelf-sync, shelf-create, etc.): frontmatter with name/description, then step-by-step instructions.

### 1.1 `/trim-edit` Skill (FR-001 through FR-006)

**File**: `plugin-trim/skills/trim-edit/SKILL.md`

Accepts `$ARGUMENTS` as the natural language edit description. Delegates to the `trim-edit` wheel workflow via `/wheel-run trim:trim-edit`. The skill markdown contains:
- Input validation (require non-empty description)
- Instructions to start the wheel workflow
- Post-workflow instructions (do NOT sync to code)

### 1.2 `/trim-flows` Skill (FR-018 through FR-024)

**File**: `plugin-trim/skills/trim-flows/SKILL.md`

Parses `$ARGUMENTS` for subcommands: `add <name>`, `list`, `sync`, `export-tests`. Each subcommand is handled inline:
- **add**: Interactive flow definition — ask developer for steps, write to `.trim-flows.json`
- **list**: Read `.trim-flows.json`, display formatted table
- **sync**: Map flow steps to Penpot frames via MCP and to code routes
- **export-tests**: Generate Playwright test stubs from flow data

### 1.3 `/trim-verify` Skill (FR-007 through FR-012)

**File**: `plugin-trim/skills/trim-verify/SKILL.md`

Delegates to `trim-verify` wheel workflow. The skill:
- Checks `.trim-flows.json` exists and has flows
- Starts the wheel workflow
- Reports verification results

### 1.4 `/trim-redesign` Skill (FR-013 through FR-017)

**File**: `plugin-trim/skills/trim-redesign/SKILL.md`

Accepts optional `$ARGUMENTS` as redesign context. Delegates to `trim-redesign` wheel workflow. The skill:
- Reads optional context from arguments
- Starts the wheel workflow
- Reports redesign results (do NOT sync to code)

## Phase 2: Workflows (P2 — Orchestration)

Create 3 wheel workflow JSON files following the command-first/agent-second pattern from shelf-create.json. Each workflow resolves the trim plugin path at runtime.

### 2.1 `trim-edit` Workflow (FR-001 through FR-006, FR-025 through FR-027)

**File**: `plugin-trim/workflows/trim-edit.json`

Steps:
1. **resolve-trim-plugin** (command): Scan `installed_plugins.json` for trim path, fall back to `plugin-trim/`
2. **read-design-state** (command): Read `.trim-components.json` and Penpot project config
3. **apply-edit** (agent): Interpret the natural language description, read current Penpot design via MCP, apply targeted changes
4. **log-change** (agent): Append entry to `.trim-changes.md` with timestamp, request, actual changes, affected frames

### 2.2 `trim-verify` Workflow (FR-007 through FR-012, FR-025 through FR-027)

**File**: `plugin-trim/workflows/trim-verify.json`

Steps:
1. **resolve-trim-plugin** (command): Scan `installed_plugins.json` for trim path
2. **read-flows** (command): Read `.trim-flows.json`
3. **capture-screenshots** (agent): For each flow, walk steps in headless Playwright (or /chrome), screenshot each step, fetch corresponding Penpot frames
4. **compare-visuals** (agent): Use Claude vision to compare each screenshot pair, identify mismatches
5. **write-report** (agent): Generate `.trim-verify-report.md` with per-step results

### 2.3 `trim-redesign` Workflow (FR-013 through FR-017, FR-025 through FR-027)

**File**: `plugin-trim/workflows/trim-redesign.json`

Steps:
1. **resolve-trim-plugin** (command): Scan `installed_plugins.json` for trim path
2. **gather-context** (command): Read PRD, `.trim-components.json`, `.trim-flows.json`
3. **read-current-design** (agent): Fetch current Penpot design state via MCP
4. **generate-redesign** (agent): Reimagine visual design preserving IA, apply to Penpot via MCP
5. **log-changes** (agent): Append comprehensive redesign entry to `.trim-changes.md`

## Phase 3: Plugin Manifest Update

Update `plugin-trim/.claude-plugin/plugin.json` to register the 4 new skills and `plugin-trim/package.json` to bump the version.

## Risks & Mitigations

| Risk | Mitigation |
|------|-----------|
| Penpot MCP tool coverage may be limited | Skills document required MCP tools; graceful error if unavailable |
| Playwright may not be installed | Verify availability in workflow; fall back to /chrome MCP |
| Claude vision comparison is heuristic | Report confidence levels; developer makes final judgment |
| `.trim-flows.json` could become stale | `/trim-flows sync` re-maps to current Penpot frames |
