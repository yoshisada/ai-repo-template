# Research: Shelf Config Artifact

**Date**: 2026-04-03
**Feature**: Shelf Config Artifact

## No NEEDS CLARIFICATION Items

The technical context is fully resolved — no unknowns to research. The feature is straightforward: define a key-value config format and update Markdown skill files to read/write it.

## Decision Log

### D1: Config File Format

**Decision**: Simple key-value format (`key = value`), one key per line, `#` for comments.

**Rationale**: The PRD explicitly requires this format (FR-004, NFR-001). It must be parseable with `grep`, `sed`, `awk` — no JSON/YAML dependency. This is the simplest possible format for 3 keys.

**Alternatives considered**:
- JSON: Rejected — requires `jq` or similar parser, overkill for 3 keys
- YAML: Rejected — requires a YAML parser, adds complexity
- TOML: Rejected — same dependency concern as JSON/YAML
- Dotenv format (`KEY=value`): Considered — similar simplicity but `key = value` with spaces is more readable and matches the PRD example

### D2: Config File Location

**Decision**: `.shelf-config` at the repo root (not in `.kiln/` or `.shelf/`).

**Rationale**: The PRD specifies repo root. It should be visible, committable, and easily discoverable. A dotfile prefix keeps it from cluttering the working directory while remaining accessible.

**Alternatives considered**:
- `.kiln/shelf-config`: Rejected — couples shelf to kiln unnecessarily
- `.shelf/config`: Rejected — adds a directory for a single file

### D3: Path Resolution Priority

**Decision**: `.shelf-config` values take priority over git remote derivation. Explicit user arguments take priority over `.shelf-config`.

**Rationale**: The config represents a deliberate user choice (confirmed during `/shelf-create`). Arguments represent an immediate override. Git remote is the weakest signal — it's a guess.

**Priority order**: argument > .shelf-config > git remote fallback

### D4: When to Write Config

**Decision**: Write `.shelf-config` only after the Obsidian project is confirmed created (after Step 9 in shelf-create, before Step 10 reporting).

**Rationale**: If MCP fails and the project isn't created, writing the config would point to a nonexistent project. The config must reflect reality.
