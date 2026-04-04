# Specifier Agent Friction Notes

**Agent**: specifier
**Feature**: wheel
**Date**: 2026-04-03

## What Went Well

- PRD was thorough — 28 FRs with clear descriptions made spec writing straightforward
- The PRD already had user stories that mapped cleanly to the spec template format
- FR numbering in the PRD (FR-001 through FR-028, with FR-017/018 gap) was consistent and traceable

## Friction Points

1. **FR numbering gap**: The PRD skips FR-017 and FR-018. Not a blocker but causes confusion when cross-referencing — you wonder if you missed something. Recommend keeping FR numbers sequential or documenting the gap reason.

2. **Template vs reality mismatch**: The spec template assumes a TypeScript/JavaScript project (examples use `.ts` files, `export function` syntax). The interfaces template is entirely TypeScript. Wheel is a Bash project — had to adapt the contract format significantly to represent Bash function signatures with positional args, stdout output, and exit codes instead of typed returns.

3. **Workflow definition format**: The PRD lists "YAML or JSON" as an open question but the non-functional requirements (NFR-004: no dependencies beyond jq/bash) effectively answer it — must be JSON. Had to make this decision in the spec rather than having it resolved in the PRD.

4. **Scope of contracts/interfaces.md**: For a Bash project, "interface contracts" means something different than for a typed language. There are no type signatures — instead, conventions about stdin/stdout, exit codes, and global variables serve as the contract. The template didn't account for this well.

## Suggestions for Improvement

- Add a Bash-specific section to the interfaces template (or make the template language-agnostic)
- PRDs should resolve open questions before reaching the specifier — the "YAML vs JSON" question was answerable from the requirements
- Consider adding a "tech stack" field to the spec template so downstream agents know what language/tooling they're working with without re-reading the PRD
