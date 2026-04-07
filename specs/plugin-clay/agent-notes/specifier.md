# Specifier Friction Notes — Plugin Clay

**Agent**: specifier
**Date**: 2026-04-07

## What Went Smoothly

- PRD was comprehensive with 37 well-defined FRs — minimal ambiguity
- External skill references (founder-prd, idea-research, project-naming, github-repo-prd) from yoshisada/skills were fetchable via `gh api` and provided clear implementation patterns
- Existing plugin conventions (kiln/wheel/shelf) made the directory structure and manifest design straightforward
- Wheel's existing `workflow.sh` library gave a clear integration point for FR-028-031

## Friction Points

1. **Wheel workflow discovery design required inference**: The PRD's FR-028 says "extend plugin.json schema to support a workflows field" but doesn't specify how wheel discovers plugins. I inferred scanning `.claude/plugins/*/plugin.json` — this may not match the actual Claude Code plugin installation path. Implementers should verify the real plugin installation directory.

2. **No marketplace.json reference**: kiln and shelf have `marketplace.json` but wheel does not. The format isn't documented anywhere. I created a task for it (T002) but implementers may need to look at kiln's copy for reference since it doesn't exist as a checked-in file.

3. **PRD Mode B/C underspecified**: FR-016 defines three modes but Mode B ("feature addition to existing product") and Mode C ("PRD-only repo") have minimal detail on directory structure or how they differ from Mode A in practice. The create-prd implementer will need to make design decisions here.

4. **Plugin installation in create-repo**: FR-026 says "Install kiln, wheel, and shelf plugins in the new repo" but the mechanism for installing Claude Code plugins programmatically isn't documented. This may require `claude plugin install` or manual `.claude/plugins/` setup.

5. **clay_derive_status is inlined, not shared**: Since clay skills are Markdown, there's no shared library. The status derivation logic must be kept in sync between clay-list and clay-sync manually. This is a maintenance risk.

## Blockers

None — all FRs are implementable with the current tech stack.
