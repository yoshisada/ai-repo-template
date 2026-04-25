---
status: open
source: retrospective
prd: cross-plugin-resolver-and-preflight-registry
priority: medium
suggested_command: /kiln:kiln-fix
tags: [retro, prompt, /specify, build-prd]
---

# `/specify` auto-numbers the spec directory, conflicting with team-lead's canonical-path mandate; specifier had to bypass the script

**Date**: 2026-04-24
**Source**: cross-plugin-resolver retrospective; specifier friction note §"Spec-directory-naming guard rail"

## Description

The team-lead brief was unambiguous: "spec directory MUST be `specs/cross-plugin-resolver-and-preflight-registry/` (no date, no number prefix)." The `/specify` skill, however, calls `.specify/scripts/bash/create-new-feature.sh` which auto-numbers + auto-prefixes (e.g. `specs/00N-cross-plugin-resolver/`). Running the literal slash command would have produced the wrong directory and required a manual rename mid-pipeline.

The specifier worked around this by authoring spec.md, plan.md, tasks.md, research.md, and contracts/ directly at the canonical path — treating the team-lead's "chain them in one uninterrupted pass" mandate as license to skip the slash commands entirely. That worked, but it's an unstated convention; a future specifier without this context would either (a) run /specify literally and rename, or (b) ask the team-lead for clarification, costing a round-trip.

## Proposed prompt rewrite

**File**: `plugin-kiln/skills/specify/SKILL.md` AND/OR `.specify/scripts/bash/create-new-feature.sh`

**Current**: `create-new-feature.sh` always auto-numbers + auto-prefixes; no `--dir-name` override.

**Proposed**: Add a `--dir-name <slug>` flag to the script (passes through to `mkdir`, skips numbering); document in `/specify` SKILL.md:

```markdown
> **Canonical-path override**: pass `--dir-name <slug>` to skip auto-
> numbering when a calling pipeline (build-prd, kiln-fix) already specifies
> the directory. The skill's default behavior (auto-number + prefix) is
> still right for ad-hoc human-driven /specify invocations. The build-prd
> team-lead prompt should always pass `--dir-name` per its PRD-slug
> convention.
```

**Why**: This was friction the specifier could route around because the team-lead's brief was clear, but the brittleness compounds: every future build-prd run with a canonical-slug mandate either bypasses /specify (losing the script's other affordances — branch creation, .specify/ initialization) or accepts a rename step. A `--dir-name` flag aligns the slash-command path with the build-prd path and removes the silent convention.

## Forwarding action

- Add `--dir-name` flag to `create-new-feature.sh`.
- Update `plugin-kiln/skills/specify/SKILL.md` to document it.
- Update `plugin-kiln/skills/kiln-build-prd/SKILL.md` to recommend that the team-lead pass `--dir-name <slug>` rather than authoring artifacts directly when invoking `/specify`.
