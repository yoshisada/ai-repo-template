# Research: Trim Design Lifecycle

**Date**: 2026-04-09

## No NEEDS CLARIFICATION Items

All technical context was resolved from the PRD, parent trim PRD, and existing plugin patterns:

### Decision 1: Workflow Pattern
- **Decision**: Use wheel workflow engine with command-first/agent-second pattern
- **Rationale**: Matches existing shelf plugin workflows (shelf-create.json, shelf-full-sync.json). Proven pattern in this repo.
- **Alternatives considered**: Pure skill-based (all logic in SKILL.md) — rejected because multi-step operations need observability via `.wheel/outputs/`

### Decision 2: /trim-flows Does Not Need a Workflow
- **Decision**: Handle /trim-flows subcommands inline in the skill markdown, no workflow JSON
- **Rationale**: Flow management (add, list, sync, export-tests) involves simple file reads/writes to `.trim-flows.json`. No multi-step orchestration or agent handoffs needed. The `sync` subcommand calls Penpot MCP directly from the skill.
- **Alternatives considered**: Workflow with command+agent steps — rejected as over-engineering for file CRUD

### Decision 3: Visual Comparison via Claude Vision
- **Decision**: Use Claude vision (multimodal screenshot analysis) for visual comparison, not pixel-diffing
- **Rationale**: PRD FR-011 explicitly requires semantic comparison. Claude vision identifies meaningful visual differences (layout shifts, color changes, missing elements) vs. noise (anti-aliasing, font rendering).
- **Alternatives considered**: Pixel-diff libraries (pixelmatch, etc.) — rejected per PRD; too noisy for design comparison

### Decision 4: Screenshot Storage
- **Decision**: Store in `.trim-verify/` (gitignored)
- **Rationale**: PRD FR-013 requires screenshots not be committed. Standard pattern for generated artifacts.
- **Alternatives considered**: `.wheel/outputs/` — rejected because screenshots are large binary files, not text outputs

### Decision 5: Plugin Path Resolution
- **Decision**: Scan `installed_plugins.json` at runtime, fall back to `plugin-trim/`
- **Rationale**: Matches shelf plugin pattern (FR-026). Works for both installed and local development.
- **Alternatives considered**: Hardcoded path — rejected; breaks when plugin is installed vs. developed locally
