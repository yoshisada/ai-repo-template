# Specifier Agent Friction Notes

**Agent**: specifier
**Feature**: shelf
**Date**: 2026-04-03

## What went well

- PRD was comprehensive with per-command plans and FR tables — minimal ambiguity
- Existing kiln spec examples provided clear format reference
- Plugin structure (Markdown SKILL.md files) is simple — no complex dependency chains or build steps to plan around

## Friction points

- **Template mismatch for non-code plugins**: The spec/plan/tasks templates assume compiled code with `src/`, `tests/`, function signatures, and coverage gates. For a Markdown-only plugin, most of these don't apply. The interface contracts had to be adapted from "function signatures" to "skill input/output + MCP call sequences." Future improvement: a plugin-specific template variant.
- **Constitution gates N/A for plugins**: 80% test coverage, E2E testing, and interface contracts (as function signatures) are all N/A for Markdown skill files. The constitution check section is mostly "N/A" entries. This is technically correct but feels like wasted space.
- **Task granularity for SKILL.md files**: Each skill is a single file, so each task is essentially "write this one file." The tasks template encourages finer granularity (models, services, endpoints) that doesn't map to the plugin authoring pattern.

## Suggestions for future runs

- Consider a `plugin-skill-template.md` for spec/plan/tasks that's tailored to Markdown-only Claude Code plugins
- Interface contracts for skills should define MCP call sequences and input/output shapes rather than function signatures
