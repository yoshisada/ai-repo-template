# Implementation Plan: Continuance Agent (/next)

**Branch**: `build/continuance-agent-20260331` | **Date**: 2026-03-31 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `specs/continuance-agent/spec.md`

## Summary

Create a continuance agent and `/next` skill that analyzes full project state (specs, tasks, blockers, QA results, audit findings, GitHub issues, backlog) and produces a prioritized list of actionable next steps mapped to kiln commands. The agent runs automatically as the final step of `/build-prd` and manually via `/next` at session start. It replaces `/resume` (kept as deprecated alias).

This is a plugin-internal feature: the deliverables are markdown-based skill and agent definitions plus modifications to the existing `/build-prd` and `/resume` skills. No compiled code, no new dependencies.

## Technical Context

**Language/Version**: Markdown (skill/agent definitions) + Bash (shell commands within skills)
**Primary Dependencies**: None new — uses existing kiln plugin infrastructure, GitHub CLI (`gh`)
**Storage**: Filesystem — `.kiln/logs/` for reports, `.kiln/issues/` for backlog items
**Testing**: Manual pipeline testing via `/build-prd` on consumer projects (no automated test suite for the plugin itself)
**Target Platform**: Any platform running Claude Code with the kiln plugin installed
**Project Type**: Claude Code plugin (markdown skills + agents)
**Performance Goals**: N/A — agent runs interactively, no latency-sensitive paths
**Constraints**: Must work when `gh` CLI is unavailable (graceful degradation); terminal summary capped at 15 items
**Scale/Scope**: Single skill + single agent + modifications to 2 existing skills

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Gate | Status | Notes |
|------|--------|-------|
| I. Spec-First Development | PASS | Spec exists at `specs/continuance-agent/spec.md` with FR-001 through FR-015 |
| II. 80% Test Coverage | N/A | Plugin is markdown-based — no compiled code to measure coverage on. Testing is via pipeline runs. |
| III. PRD as Source of Truth | PASS | PRD at `docs/features/2026-03-31-continuance-agent/PRD.md` is the authoritative source |
| IV. Hooks Enforce Rules | PASS | No changes to hook enforcement. No `src/` edits needed. |
| V. E2E Testing Required | N/A | No CLI, API, or compiled artifact. Testing is via running the skill in a consumer project. |
| VI. Small, Focused Changes | PASS | 4 files created/modified, each under 500 lines |
| VII. Interface Contracts | PASS | Contracts defined in `contracts/interfaces.md` |
| VIII. Incremental Task Completion | PASS | Tasks will be marked `[X]` per the workflow |

## Project Structure

### Documentation (this feature)

```text
specs/continuance-agent/
├── plan.md              # This file
├── spec.md              # Feature specification
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── contracts/
│   └── interfaces.md    # Interface contracts
├── checklists/
│   └── requirements.md  # Spec quality checklist
└── tasks.md             # Phase 2 output (created by /tasks)
```

### Source Code (repository root)

```text
plugin/
├── skills/
│   ├── next/
│   │   └── SKILL.md           # NEW — /next skill definition (replaces /resume)
│   └── resume/
│       └── SKILL.md           # MODIFIED — deprecated alias pointing to /next
├── agents/
│   └── continuance.md         # NEW — continuance agent definition
└── ...

# Also modified:
plugin/skills/build-prd/skill.md  # MODIFIED — add continuance as final pipeline step
```

**Structure Decision**: This feature adds 2 new files (`plugin/skills/next/SKILL.md` and `plugin/agents/continuance.md`) and modifies 2 existing files (`plugin/skills/resume/SKILL.md` and `plugin/skills/build-prd/skill.md`). All files are markdown. No new directories beyond `plugin/skills/next/`.

## Deployment Readiness

| Artifact | Path | Required? | Notes |
|----------|------|-----------|-------|
| Dockerfile | N/A | No | Plugin is distributed via npm, no container |
| docker-compose.yml | N/A | No | N/A |
| CI config | N/A | No | No CI changes needed |
| Env template | N/A | No | No environment variables |
| Kubernetes manifests | N/A | No | N/A |
| Terraform / IaC | N/A | No | N/A |

**Deployment notes**: Plugin is distributed via `npm publish` from the `plugin/` directory. The new skill and agent files are automatically discovered by Claude Code's plugin system when present in the correct directories.

## Implementation Phases

### Phase 1: Create Continuance Agent Definition

Create `plugin/agents/continuance.md` — the agent definition that contains the analysis logic, priority classification, and output formatting rules.

**Files**:
- `plugin/agents/continuance.md` (NEW)

**Key decisions**:
- Agent uses `sonnet` model (complex analysis across multiple sources)
- Agent is structured as a step-by-step workflow: gather sources → classify → prioritize → format output
- Priority ordering: blockers > incomplete work > QA/audit gaps > backlog > improvements
- Terminal summary capped at 15 items grouped by priority
- Report format includes metadata header, recommendations table, and source references

### Phase 2: Create /next Skill Definition

Create `plugin/skills/next/SKILL.md` — the skill that users invoke directly. It orchestrates the continuance agent's analysis and handles the `--brief` flag, report persistence, and backlog issue creation.

**Files**:
- `plugin/skills/next/SKILL.md` (NEW)

**Key decisions**:
- Skill reads `$ARGUMENTS` for flags (`--brief`)
- Skill gathers project state via bash commands (same approach as existing `/resume`)
- Skill delegates analysis and prioritization to the continuance agent's logic (inline, not spawned)
- Report saved to `.kiln/logs/next-<timestamp>.md` unless `--brief`
- Backlog issues created in `.kiln/issues/` for untracked gaps with `[auto:continuance]` tag
- Deduplication uses title similarity matching against existing `.kiln/issues/` files

### Phase 3: Update /resume as Deprecated Alias

Modify `plugin/skills/resume/SKILL.md` to become a thin wrapper that prints a deprecation notice and then executes the `/next` skill logic.

**Files**:
- `plugin/skills/resume/SKILL.md` (MODIFIED)

**Key decisions**:
- Keep the file so existing references continue to work
- Deprecation notice is printed before the main output
- The actual logic redirects to running `/next`

### Phase 4: Integrate into /build-prd Pipeline

Modify `plugin/skills/build-prd/skill.md` to add the continuance agent as the final pipeline step, running after the retrospective.

**Files**:
- `plugin/skills/build-prd/skill.md` (MODIFIED)

**Key decisions**:
- Continuance runs after retrospective completes (last step before PR creation)
- The continuance output is included in the terminal summary
- Continuance runs as a skill invocation within the pipeline, not as a separate spawned agent
- Failure of the continuance step does not block PR creation (advisory only)

## Complexity Tracking

No constitution violations to justify. All gates pass or are N/A for this markdown-only plugin feature.
