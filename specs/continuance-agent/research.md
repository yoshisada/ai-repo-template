# Research: Continuance Agent (/next)

**Date**: 2026-03-31
**Feature**: [spec.md](./spec.md)

## Decision 1: Agent Model Assignment

**Decision**: Use `sonnet` model for the continuance agent.
**Rationale**: The agent performs complex analysis across multiple project sources (specs, tasks, QA, GitHub issues) and needs to synthesize findings into prioritized recommendations. This requires reasoning capability beyond simple text matching. Consistent with existing agents like `smoke-tester.md` and `qa-engineer.md` that use sonnet for complex work.
**Alternatives considered**: `haiku` — rejected because the prioritization and deduplication logic requires stronger reasoning to avoid noisy or duplicated recommendations.

## Decision 2: Skill vs Spawned Agent Architecture

**Decision**: The `/next` skill contains the full logic inline (like `/resume`) rather than spawning a separate agent.
**Rationale**: The continuance agent is invoked in two contexts: (1) standalone via `/next` and (2) as the final step in `/build-prd`. In context (1), spawning an agent adds latency and complexity for no benefit — the skill runs in the user's session. In context (2) within build-prd, the continuance step runs after the retrospective and before PR creation — it can be invoked as a skill call by the team lead rather than spawning a separate teammate.
**Alternatives considered**: Spawning a dedicated `continuance` agent teammate in build-prd — rejected because it would require wiring up task dependencies and adds an agent spawn just for a read-only analysis step. The agent definition file (`plugin/agents/continuance.md`) still exists as a reference for the agent's role and capabilities, but the skill handles the execution.

## Decision 3: Backlog Deduplication Strategy

**Decision**: Conservative title-based matching — read existing `.kiln/issues/` file titles, compare with the new gap's description. If no match found, create a new issue. Prefer false positives (new issue for something already tracked) over false negatives (missing a gap).
**Rationale**: PRD explicitly states "conservative matching — prefer creating a new issue over missing one." Fuzzy matching across markdown content is unreliable without embeddings or NLP, and those are out of scope.
**Alternatives considered**: Content-based similarity scoring — rejected as over-engineered for a markdown-based system. The agent's language model naturally does title comparison when reading the existing issues.

## Decision 4: GitHub CLI Graceful Degradation

**Decision**: Wrap all `gh` commands in availability checks (`command -v gh` + `gh auth status`). If unavailable, skip those sources and note "GitHub sources skipped — gh CLI not available or not authenticated" in the report.
**Rationale**: FR-014 requires graceful degradation. Many development environments (CI, air-gapped, fresh installs) lack `gh` or authentication.
**Alternatives considered**: Making `gh` a hard requirement — rejected because it would break `/next` in environments without GitHub integration.

## Decision 5: Report File Naming

**Decision**: Use `.kiln/logs/next-<YYYY-MM-DD-HHmmss>.md` format as specified in FR-005.
**Rationale**: Timestamp-based naming enables multiple reports per day and sorts chronologically. The `.kiln/logs/` directory is the standard location for pipeline outputs per kiln's architecture.
**Alternatives considered**: Sequential numbering — rejected because timestamps are self-documenting and avoid collisions.

## Decision 6: Build-prd Integration Point

**Decision**: Add continuance as a skill invocation after the retrospective step and before PR creation in `/build-prd`.
**Rationale**: The continuance analysis should include retrospective findings (so it must run after). It should inform the PR description (so it runs before PR creation). It's advisory — failure does not block the PR.
**Alternatives considered**: Running as a spawned agent teammate — rejected (see Decision 2). Running before retrospective — rejected because it would miss retrospective action items.
