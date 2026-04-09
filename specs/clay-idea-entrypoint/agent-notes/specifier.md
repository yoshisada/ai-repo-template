# Specifier Friction Notes: clay-idea-entrypoint

**Agent**: specifier
**Date**: 2026-04-07

## What Went Smoothly

- PRD was well-structured with clear FR numbering (FR-001 through FR-014) — mapped directly to spec FRs and tasks
- Existing clay skill files provided strong context for the interface contracts (understanding how SKILL.md files are structured, what frontmatter looks like, how steps are organized)
- The 4-route pattern (new/existing-product/existing-repo/similar-but-distinct) was clearly defined in the PRD — no ambiguity to resolve

## Friction Points

1. **Interface contracts for Markdown skills**: The standard interfaces template assumes TypeScript function signatures. For plugin skills (Markdown + Bash), the "interface" is the file structure, required sections, and behavioral contracts. Had to adapt the contract format significantly — future plugin features could benefit from a Markdown-skill-specific contract template.

2. **Test coverage gate is N/A**: The constitution requires 80% test coverage, but plugin skills have no automated test suite. This is a recurring friction point for all plugin features. The spec notes this as N/A but it feels like a gap in the constitution for plugin-type projects.

3. **clay.config format decision**: The PRD specifies plain-text with space-separated fields, but doesn't address what happens if a local path contains spaces. The spec assumes paths won't have spaces (kebab-case slugs, sibling directories). This is fine for v1 but could be a v2 issue.

## Decisions Made

- Overlap detection is LLM semantic reasoning, not bash string matching — this was stated in the PRD's risks section and carried through to the spec
- clay.config comments (lines starting with #) are supported for future-proofing but not required
- The clay-list table conditionally shows repo columns only when clay.config exists (not empty columns)
