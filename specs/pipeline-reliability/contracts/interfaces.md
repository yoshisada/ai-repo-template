# Interface Contracts: Pipeline Reliability & Health

**Feature**: Pipeline Reliability
**Branch**: `build/pipeline-reliability-20260401`
**Date**: 2026-04-01

## Overview

This feature modifies existing shell scripts (hooks), markdown skill definitions, and markdown agent definitions. There are no exported functions in the traditional sense — the "interfaces" are the behavioral contracts of the hook scripts and the prompt instructions in skills/agents.

## Hook Script Contracts

### require-spec.sh

**Location**: `plugin/hooks/require-spec.sh`
**Type**: PreToolUse hook (stdin: JSON with tool_name and tool_input)
**Exit codes**: 0 = allow, 2 = block

#### get_current_feature()

```bash
# Derives current feature name from git branch or fallback file
# Input: none (reads git branch and .kiln/current-feature)
# Output: prints feature name to stdout (e.g., "pipeline-reliability")
# Behavior:
#   1. Try git branch: extract from "build/<name>-<date>" pattern
#   2. Try git branch: extract from "<number>-<name>" pattern
#   3. Fall back to .kiln/current-feature file contents
#   4. If all fail: print empty string (triggers glob fallback for backwards compat)
get_current_feature()
```

#### is_implementation_path()

```bash
# Checks if a file path is in an implementation directory that requires gate checks
# Input: $1 = absolute file path
# Output: exit 0 if implementation path (needs gates), exit 1 if not
# Implementation directories: src/, cli/, lib/, modules/, app/, components/
# Always-allowed: docs/, specs/, scripts/, tests/, plugin/, .claude/, .specify/,
#   config files (.json, .yml, .yaml, .toml, .md, .gitignore, .env*)
is_implementation_path()
```

#### check_implementing_lock()

```bash
# Checks if /implement is currently active via lock file
# Input: none (reads .kiln/implementing.lock)
# Output: exit 0 if active (lock exists and is <30min old), exit 1 if not
# Lock file format: JSON with timestamp, feature, pid fields
# Stale detection: locks older than 30 minutes are treated as stale (exit 1)
check_implementing_lock()
```

#### Gate Check Sequence (updated)

```
Gate 1: specs/<current-feature>/spec.md exists
Gate 2: specs/<current-feature>/plan.md exists
Gate 3: specs/<current-feature>/tasks.md exists
Gate 3.5: specs/<current-feature>/contracts/interfaces.md exists
Gate 4: tasks.md has [X] mark OR implementing.lock is active and fresh
```

## Skill Prompt Contracts

### build-prd/SKILL.md Additions

#### Stall Detection Section

```markdown
# Location: After "Task Dependencies" section
# Content: Instructions for team lead to monitor agent activity
# Configurable timeout: default 10 minutes
# Trigger: task stays in_progress with no commits/task-updates/messages
# Action: SendMessage check-in to stalled agent
```

#### Phase Dependency Enforcement Section

```markdown
# Location: In "Monitor and Steer" section
# Content: Instructions to dispatch agents in dependency order
# Rule: Do NOT dispatch Phase N+1 agents until all Phase N tasks are [X]
# Verification: Check tasks.md before sending each implementer's prompt
```

#### Docker Rebuild Step

```markdown
# Location: After implementation phase, before QA phase dispatch
# Content: Instructions to run docker rebuild for containerized projects
# Detection: Dockerfile or docker-compose.yml in project root
# Command: docker compose build (or docker build) before QA agent starts
```

### implement/SKILL.md Modifications

#### Lock File Management

```markdown
# On start: create .kiln/implementing.lock with JSON payload
# On completion (success): remove .kiln/implementing.lock
# On failure: remove .kiln/implementing.lock (via trap)
# Format: {"timestamp": "ISO8601", "feature": "<name>", "pid": "<pid>"}
```

#### Validation Checkpoint Clarification

```markdown
# Replace: "STOP and VALIDATE"
# With: "SELF-VALIDATE: Run tests locally and verify the phase works.
#        Do NOT wait for external QA feedback.
#        If tests pass, proceed to the next phase."
# Distinguish from: "QA-GATED CHECKPOINT: Wait for QA agent feedback
#        before proceeding. This applies only when explicitly marked."
```

### tasks-template.md Modification

```markdown
# Replace: "STOP and VALIDATE"
# With: "SELF-VALIDATE: Run tests locally and verify independently"
```

## Agent Prompt Contracts

### qa-engineer.md Additions

#### Container Freshness Pre-Flight

```markdown
# Location: In "Pre-Flight" section, before version check
# Content: For containerized projects (Dockerfile exists):
#   1. Read .kiln/qa/last-build-sha (if exists)
#   2. Compare against git rev-parse HEAD
#   3. If mismatch or file missing: run docker compose build
#   4. Update .kiln/qa/last-build-sha with current HEAD
#   5. If no Dockerfile: skip this check
```

### qa-checkpoint/SKILL.md Additions

#### Container Freshness Step

```markdown
# Location: New step between "Determine What to Test" and "Start Dev Server"
# Content: Same logic as qa-engineer.md pre-flight
# Only runs if Dockerfile or docker-compose.yml exists in project root
```

## File Inventory

| File | Action | FR |
|------|--------|----|
| `plugin/hooks/require-spec.sh` | Modify | FR-001, FR-002, FR-003, FR-004 |
| `plugin/skills/build-prd/SKILL.md` | Modify | FR-005, FR-006, FR-008 |
| `plugin/skills/implement/SKILL.md` | Modify | FR-002 (lock), FR-007 |
| `plugin/templates/tasks-template.md` | Modify | FR-007 |
| `plugin/agents/qa-engineer.md` | Modify | FR-009 |
| `plugin/skills/qa-checkpoint/SKILL.md` | Modify | FR-010 |
