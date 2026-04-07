# Specifier Friction Notes: Developer Tooling Polish

**Agent**: specifier
**Date**: 2026-04-07

## What was confusing or slow

1. **Branch already existed**: The team lead had already created the branch `build/developer-tooling-polish-20260407` and the spec directory naming was pre-determined. The `/specify` skill's create-new-feature.sh script was unnecessary since the branch was already checked out. I skipped it and used `check-prerequisites.sh` instead, which correctly detected the existing branch and feature directory.

2. **Skill template overhead**: The `/specify` skill's step-by-step instructions are extensive (8 major steps with substeps). For a straightforward two-skill feature like this, much of the template machinery (clarification questions, multi-iteration validation) was unnecessary. The spec was complete on the first pass with zero NEEDS CLARIFICATION markers.

3. **Plan template boilerplate**: The plan template includes many options for different project types (web app, mobile, etc.) that don't apply to plugin skill development. Had to strip all of that out.

## What could be improved

1. **Skill-type shortcut**: For features that are "add a new Claude Code plugin skill," a lighter-weight template path would save time. The current flow is optimized for full application features with models, services, APIs, and tests.

2. **Agent context update noise**: The `update-agent-context.sh` script appends tech stack entries to CLAUDE.md's "Active Technologies" section. This section is growing long with repeated similar entries. Consider deduplicating or rotating old entries.

3. **Tasks template assumes tests**: The tasks template heavily emphasizes TDD and test phases. For plugin skills (Markdown + Bash), there's no test framework — the template's test sections are all N/A. A conditional template section would be cleaner.

## Issues with the PRD or instructions

- PRD was clear and well-structured. Two independent features with clean FR separation made parallel agent assignment straightforward.
- The instruction to use `specs/developer-tooling-polish/` (no numeric prefix) was clear and correctly followed.
- No issues with the team lead's instructions — the sequential specify->plan->tasks flow worked as expected.
