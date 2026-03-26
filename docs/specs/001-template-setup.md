# Feature Specification: AI Repo Template Setup

**Created**: 2026-03-26
**Status**: Approved

## Overview

A GitHub template repository that enforces spec-first development via Claude Code hooks, spec-kit, and ruflo (claude-flow). Any repo created from this template starts with: a constitution, enforcement hooks that block code without specs, custom agents, custom speckit commands, and a single install script that bootstraps everything.

## User Scenarios & Testing

### User Story 1 — Bootstrap a new project from the template (Priority: P0)

As a developer, I want to create a repo from this template and run one command to have everything working — speckit, ruflo, hooks, agents, and enforcement rules.

**Acceptance Scenarios**:

1. **Given** I created a repo from the template, **When** I run `./scripts/setup.sh`, **Then** speckit is initialized, ruflo MCP server is configured, hooks are active, and I can run `/speckit.specify`.
2. **Given** setup completed, **When** I try to edit a source file without a spec, **Then** the PreToolUse hook blocks me with "No spec found."
3. **Given** I create a spec in `specs/`, **When** I try to edit a source file, **Then** the hook allows it.

### User Story 2 — Enforce spec-first workflow via hooks (Priority: P0)

As a developer, I want hooks that physically prevent code changes without specs, so the workflow is mandatory, not optional.

**Acceptance Scenarios**:

1. **Given** no spec exists in `specs/`, **When** Claude attempts Edit or Write on `src/` files, **Then** the hook blocks with a message explaining what to do.
2. **Given** a spec exists, **When** Claude edits files, **Then** the hook allows it.
3. **Given** Claude tries to commit, **When** .env files are staged, **Then** the hook warns and blocks.
4. **Given** any session starts, **When** Claude loads, **Then** CLAUDE.md rules are loaded with the full workflow.

### User Story 3 — Custom speckit commands (Priority: P1)

As a developer, I want custom speckit commands beyond the standard set, tailored for AI-assisted development.

**Acceptance Scenarios**:

1. **Given** the template is set up, **When** I run `/speckit.audit`, **Then** it runs a PRD compliance audit against the current implementation.
2. **Given** a spec and implementation exist, **When** I run `/speckit.coverage`, **Then** it checks test coverage against the 80% gate.

### User Story 4 — Custom agents for specialized tasks (Priority: P1)

As a developer, I want pre-built agents that handle common workflows — auditing, testing, reviewing — without manual configuration.

**Acceptance Scenarios**:

1. **Given** the template is set up, **Then** `prd-compliance-auditor`, `spec-enforcer`, and `test-runner` agents are available.
2. **Given** I ask for a PRD audit, **Then** the prd-compliance-auditor agent runs automatically.

### User Story 5 — Ruflo/claude-flow integration (Priority: P1)

As a developer, I want ruflo pre-configured so I can use swarm orchestration and memory from day one.

**Acceptance Scenarios**:

1. **Given** setup completed, **When** I check MCP config, **Then** claude-flow is registered as an MCP server.
2. **Given** ruflo is configured, **When** I use swarm commands, **Then** they work without additional setup.

### User Story 6 — Works as a GitHub template (Priority: P2)

As a developer, I want to use GitHub's "Use this template" button to create new repos.

**Acceptance Scenarios**:

1. **Given** the repo has template enabled, **When** I click "Use this template", **Then** the new repo has all files but no git history from the template.

## Requirements

### Functional Requirements

- **FR-001**: `scripts/setup.sh` MUST install speckit (via uv/uvx), initialize speckit for claude, configure ruflo MCP, and set hooks active.
- **FR-002**: `scripts/setup.sh` MUST be idempotent — safe to run multiple times.
- **FR-003**: PreToolUse hook MUST block Edit/Write on `src/**` files when no spec exists in `specs/`.
- **FR-004**: PreToolUse hook MUST allow Edit/Write on non-src files (docs, specs, config) always.
- **FR-005**: PreToolUse hook MUST block git commit when .env files are staged.
- **FR-006**: CLAUDE.md MUST contain the full mandatory workflow (spec → plan → tasks → implement → test → verify).
- **FR-007**: `.specify/memory/constitution.md` MUST be pre-filled with spec-first + 80% coverage rules.
- **FR-008**: Custom speckit commands MUST be installable as `.claude/skills/` or `.claude/commands/`.
- **FR-009**: Custom agents MUST be defined in `.claude/agents/` or equivalent.
- **FR-010**: Ruflo MCP server MUST be configured in `.mcp.json` or project settings.
- **FR-011**: `docs/PRD.md` MUST exist as a placeholder with the required structure.
- **FR-012**: `specs/` directory MUST exist with a README explaining the workflow.
- **FR-013**: `.gitignore` MUST exclude node_modules, .env, .env.*, dist/, coverage/.

### Key Entities

- **Setup Script**: Single entry point that bootstraps everything
- **Enforcement Hooks**: PreToolUse hooks in `.claude/settings.json`
- **Constitution**: `.specify/memory/constitution.md` — governing rules
- **CLAUDE.md**: Auto-loaded instructions for every conversation
- **Custom Skills**: `.claude/skills/` — extended speckit commands
- **Custom Agents**: `.claude/agents/` — specialized AI agents

## Success Criteria

- **SC-001**: `./scripts/setup.sh` completes without errors on a fresh clone.
- **SC-002**: Edit/Write blocked when no spec exists; allowed when spec exists.
- **SC-003**: All custom commands and agents are functional after setup.
- **SC-004**: Template works with GitHub "Use this template" button.
