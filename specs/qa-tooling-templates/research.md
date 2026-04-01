# Research: QA Agent Optimization, Kiln Doctor Enhancements & Template Improvements

**Date**: 2026-04-01

## R-001: TeammateIdle Hook Support (FR-006)

- **Decision**: Implement FR-006 as prompt-based enforcement within the QA agent definition rather than a `TeammateIdle` hook, since Claude Code's hook system does not support `TeammateIdle` events.
- **Rationale**: The hook system supports `PreToolUse`, `PostToolUse`, `Notification`, and `Stop` events. There is no `TeammateIdle` event type. Adding build-after-message enforcement as agent instructions achieves the same behavioral outcome.
- **Alternatives considered**: (1) Custom `TeammateIdle` hook — not supported by Claude Code. (2) `Stop` hook that checks build state — too late in the lifecycle. (3) Agent prompt instructions — achieves the goal without platform limitations.

## R-002: SubagentStart Hook for Build Enforcement (FR-005)

- **Decision**: Use a `Notification` hook with matcher `SubagentStart` pattern, or embed the build requirement directly in the QA agent instructions and the build-prd team lead instructions.
- **Rationale**: The hooks.json format supports `PreToolUse` matchers. For agent-level enforcement, the most reliable approach is updating the agent definition and the build-prd orchestrator to inject the build-after-message requirement.
- **Alternatives considered**: (1) hooks.json `PreToolUse` on `SendMessage` — would fire for all agents, not just QA. (2) Agent prompt instructions — targeted and reliable.

## R-003: Kiln Manifest Retention Rules Format (FR-011)

- **Decision**: Extend `kiln-manifest.json` with a `retention` key at the directory level, e.g., `"logs": { "required": true, "tracked": false, "retention": { "keep_last": 10 } }`.
- **Rationale**: Keeps retention rules co-located with directory definitions. Existing manifests without `retention` keys continue to work (no cleanup applied).
- **Alternatives considered**: (1) Separate retention config file — adds another file to track. (2) CLI flags only — not persistent.

## R-004: Version-Sync Default Scan Targets (FR-015, FR-017)

- **Decision**: Default scan targets are `package.json` and `plugin/package.json` (project-root only). `package-lock.json` and `node_modules/` are excluded by default. Additional targets and exclusions configured via `.kiln/version-sync.json`.
- **Rationale**: Most kiln projects are npm packages. Scanning only root-level package manifests avoids false positives from lock files and nested dependencies.
- **Alternatives considered**: (1) Scan all `*.json` for version fields — too many false positives. (2) Only scan files listed in config — requires config to exist for basic functionality.

## R-005: Agent Notes Directory Structure (FR-009)

- **Decision**: Each pipeline agent writes to `specs/<feature>/agent-notes/<agent-name>.md` before completing its work. The directory is created by the first agent that writes to it.
- **Rationale**: File-per-agent avoids merge conflicts when multiple agents finish near the same time. Using the agent name (e.g., `implementer-1.md`, `qa-engineer.md`) makes authorship clear.
- **Alternatives considered**: (1) Single file with sections — risk of write conflicts. (2) JSON format — harder for retrospective agent to parse and for humans to read.

## R-006: Issue Template Extraction Location (FR-018, FR-019)

- **Decision**: Extract the issue markdown template to `plugin/templates/issue.md`. The `/report-issue` skill reads from this template. `init.mjs` copies it to `.kiln/templates/issue.md` in consumer projects.
- **Rationale**: Follows the existing pattern where templates live in `plugin/templates/` and are scaffolded to consumer projects by `init.mjs`. Consumer projects can customize their local copy.
- **Alternatives considered**: (1) Keep template inline in the skill — not customizable. (2) Put template in scaffold/ — inconsistent with existing template patterns.
