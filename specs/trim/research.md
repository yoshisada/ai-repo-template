# Research: Trim Plugin

## Decision: Plugin Structure Pattern

**Decision**: Follow the exact same plugin structure as `plugin-shelf/`.
**Rationale**: All plugins in this repo (kiln, shelf, wheel, clay) use the same pattern: `.claude-plugin/plugin.json` manifest, `skills/` directory with SKILL.md files, `workflows/` with JSON files, `templates/` for scaffolding, and `package.json` for npm distribution. Consistency reduces cognitive overhead.
**Alternatives considered**: Custom structure — rejected because it would diverge from the established pattern for no benefit.

## Decision: Workflow Engine

**Decision**: Use wheel workflows for all multi-step operations.
**Rationale**: The wheel engine (`plugin-wheel/`) provides deterministic step ordering, command-first/agent-second execution, output persistence to `.wheel/outputs/`, and context passing between steps. This is the established pattern per FR-004 and FR-021 in the PRD.
**Alternatives considered**: Inline skill logic — rejected because multi-step operations need observability, resumability, and deterministic ordering.

## Decision: Configuration Format

**Decision**: Plain-text key-value file (`.trim-config`) at repo root, same pattern as `.shelf-config`.
**Rationale**: Human-readable, no parser needed beyond `grep`/`cut`, works with existing shell-based command steps. Per FR-002 in the PRD.
**Alternatives considered**: JSON config — rejected because it requires `jq` for writes and is harder to edit manually. YAML — rejected for same reason plus no native Bash parser.

## Decision: Component Mapping Format

**Decision**: JSON file (`.trim-components.json`) at repo root.
**Rationale**: Component mappings have structured data (arrays of objects with typed fields). JSON is human-readable per NFR-002, parseable with `jq` in command steps, and the natural format for structured data. Per FR-003 in the PRD.
**Alternatives considered**: Key-value format — rejected because the data is too structured (nested objects with timestamps).

## Decision: Framework Detection Strategy

**Decision**: Detect via presence of config files and package.json dependencies in command steps, before agent steps run.
**Rationale**: Deterministic detection via file/dependency scanning is reliable and fast. The command step writes the detected framework to `.wheel/outputs/` so agent steps know exactly what to generate. Per FR-005/FR-009 in the PRD.
**Alternatives considered**: User prompt — rejected because it adds friction. Agent-based detection — rejected because it's non-deterministic.

## Decision: Penpot Interaction Model

**Decision**: All Penpot interactions go through Penpot MCP tools in agent steps only.
**Rationale**: MCP tools are only available to agents, not command steps. Command steps handle data gathering (config, code scanning, framework detection). Agent steps handle all Penpot reads/writes. Per NFR-003 in the PRD.
**Alternatives considered**: Direct Penpot API calls — explicitly rejected by NFR-003.

## Decision: Plugin Resolution at Runtime

**Decision**: Workflows resolve the trim plugin install path by scanning `installed_plugins.json`, falling back to `plugin-trim/`.
**Rationale**: Same pattern as shelf workflows. Supports both development (local `plugin-trim/`) and installed (cache path) scenarios. Per FR-022 in the PRD.
**Alternatives considered**: Hardcoded path — rejected because it breaks when installed as a package.
