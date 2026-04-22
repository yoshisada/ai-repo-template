# Interfaces: First-Class Skill Prefix Convention

## Scope

This feature is a **rename refactor**. There is no new runtime code, no exported functions, no new data structures, and no new APIs.

Per the project constitution (Principle VII — "Interface Contracts Before Implementation"), this artifact must define the exact signatures that implementation must match. For a pure rename refactor, the "interface" is the rename table itself: the single source of truth that every implementer (and the auditor) must conform to.

## Interface Contract

The single source of truth for this feature is the **Rename Table** in [`../plan.md`](../plan.md#rename-table-complete--single-source-of-truth).

Every implementer MUST:

1. Only rename skills listed as **RENAME** in the table.
2. Leave skills marked **NO-OP** untouched (directory name AND frontmatter `name:` unchanged).
3. Use the exact new directory name and the exact new frontmatter `name:` value shown in the table. No variations (no abbreviations, no case changes, no alternate separators).
4. For each renamed skill, update the frontmatter `name:` field to match the new directory name exactly.

Every auditor MUST:

1. Verify every row in the table matches the final repo state.
2. Verify no skill name exists in the repo that is not listed in the table.
3. Verify the five pipeline-internal kiln skills (`audit`, `implement`, `plan`, `specify`, `tasks`) are still bare.
4. Verify the two already-prefixed kiln skills (`kiln-cleanup`, `kiln-doctor`) are unchanged.

## Workflow JSON Filename Contract

Workflow JSONs whose filenames correspond to a renamed skill follow the same rename (see `plan.md` → "Workflow JSON Alignment (FR-004)"). Workflow JSONs that do not correspond to a skill keep their current filename.

## Cross-Reference Contract

Every live reference to an old skill name in an updatable file (SKILL.md, agent `.md`, workflow `.json`, template, hook, `CLAUDE.md`, `docs/**/*.md`) MUST be rewritten to the new name. The grep gate (SC-001) enforces this with zero dangling references outside the excluded paths listed in `plan.md`.

## Signature Change Policy

If the rename table in `plan.md` needs to change during implementation (e.g., a skill was discovered to actually be a helper, not a first-class skill), the table in `plan.md` MUST be updated **first**, before any implementer acts on the change. This artifact is informational; `plan.md` is authoritative.

## No Exported Functions

There are no exported functions to contract-specify. This section exists solely to satisfy constitution Principle VII; a rename refactor has no runtime surface.
