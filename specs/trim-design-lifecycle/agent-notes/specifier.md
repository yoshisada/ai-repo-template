# Specifier Friction Notes: Trim Design Lifecycle

**Agent**: specifier
**Date**: 2026-04-09

## Observations

1. **Plugin-trim does not exist yet**: The task instructions say "The parent trim plugin (plugin-trim/) already exists with pull/push/diff/library/design skills from a prior pipeline" but plugin-trim/ does not exist on disk. The spec and plan assume it will be created by a parallel pipeline. The implementer should create the directory structure (skills/, workflows/) but should NOT create the parent plugin's skills (pull, push, diff, library, design) — only the 4 lifecycle skills.

2. **No test suite applicable**: Constitution requires 80% test coverage, but this is a plugin source repo where deliverables are markdown and JSON. The plan marks this gate as N/A. The implementer should not attempt to write tests.

3. **Branch already existed**: The branch `build/trim-design-lifecycle-20260409` was pre-created before the specifier ran. The `/specify` script's branch creation step was skipped since we were already on the correct branch.

4. **Spec directory naming**: Per FR-005 from the parent pipeline, the spec directory is `specs/trim-design-lifecycle/` with no numeric prefix.

## Decisions Made

- `/trim-flows` does NOT get a wheel workflow — subcommands are simple file CRUD handled inline in the skill. This reduces complexity without losing functionality.
- Visual comparison uses Claude vision (multimodal), not pixel-diffing — per PRD FR-011.
- Screenshots stored in `.trim-verify/` (gitignored), not `.wheel/outputs/`.
