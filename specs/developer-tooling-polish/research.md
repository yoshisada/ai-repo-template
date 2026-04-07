# Research: Developer Tooling Polish

## R-001: Wheel Workflow JSON Schema

**Decision**: Reuse the existing workflow JSON schema from `plugin-wheel/lib/workflow.sh`. Workflows have `.name`, `.steps[]` with `.id`, `.type`, and optional `.workflow` for composition.

**Rationale**: The `workflow_load()` function already validates these fields. Using the same expectations ensures consistency.

**Alternatives considered**: Defining a separate schema — rejected because the engine already defines the canonical format.

## R-002: Wheel Validation Approach

**Decision**: Perform inline validation in the skill rather than sourcing `workflow.sh` directly, because SKILL.md files are Markdown with embedded Bash snippets (not full shell scripts that can `source` libraries). Use `jq` to check JSON validity and required fields.

**Rationale**: SKILL.md Bash blocks run as independent snippets in the Claude Code runtime, not as a single sourced script. Each code block is self-contained.

**Alternatives considered**: Sourcing `plugin-wheel/lib/workflow.sh` — rejected because skill Bash blocks don't maintain shared shell state across steps.

## R-003: Test File Discovery Patterns

**Decision**: Scan for test files matching these patterns: `**/*.test.{js,ts,jsx,tsx}`, `**/*.spec.{js,ts,jsx,tsx}`, `tests/**/*`, `__tests__/**/*`, `e2e/**/*`. Exclude `node_modules/`.

**Rationale**: These cover Playwright (primary), Vitest, Jest, and Mocha — the most common JS/TS test frameworks. The spec says v1 focuses on Playwright with general heuristics for others.

**Alternatives considered**: Only Playwright files — rejected because the audit should be broadly useful.

## R-004: Test Overlap Detection Heuristics

**Decision**: Use conservative text-based heuristics for v1:
1. Extract `test()` / `it()` / `describe()` blocks and their descriptions
2. Compare test descriptions for high similarity (exact or near-duplicate names)
3. Look for identical selector patterns, URL patterns, or assertion targets across tests
4. Flag tests with >80% line similarity as potential duplicates

**Rationale**: Semantic analysis would require AST parsing which is too complex for a Bash/Markdown skill. Text heuristics with conservative thresholds avoid false positives.

**Alternatives considered**: Full AST parsing — rejected because it requires Node.js dependencies (violates zero-dependency constraint).

## R-005: Audit Report Format

**Decision**: Markdown report with sections: Summary, Duplicate Scenarios, Redundant Assertions, Recommendations. Each finding includes file paths, line references, and estimated redundancy.

**Rationale**: Markdown is machine-parseable (for pipeline integration per FR-011) and human-readable.

**Alternatives considered**: JSON report — rejected because markdown is more consistent with existing `.kiln/` artifacts.
