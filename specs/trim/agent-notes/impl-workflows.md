# Friction Notes: impl-workflows

**Agent**: impl-workflows
**Date**: 2026-04-09
**Scope**: T007-T019 (5 workflows, 5 skills, Phase 8 polish)

## What Went Well

1. **Contracts were precise**: The contracts/interfaces.md had exact command scripts, step IDs, output paths, and frontmatter for every skill and workflow. This eliminated ambiguity and made implementation straightforward.

2. **Shelf patterns were good reference**: The shelf-full-sync.json and shelf-create.json workflows provided clear patterns for command steps, agent steps, context_from, and output fields. The trim workflows follow the same structure.

3. **Research was actionable**: The research.md provided a clear recommendation (MCP-agnostic, agent steps for all Penpot interactions) that directly shaped the workflow design.

## Friction Points

1. **Blocking wait was long**: I was fully blocked until Tasks #1, #2, and #3 completed. I spent the blocked time reading reference code, which was productive but idle time could have been shorter if the spec/plan/tasks pipeline ran faster or if the scaffold and research had been parallelized earlier.

2. **Shared command scripts across workflows**: The `read-config`, `detect-framework`, `read-mappings`, and `resolve-trim-plugin` command steps are duplicated verbatim across all 5 workflows. The wheel engine doesn't have a shared-step or include mechanism, so this is unavoidable duplication. A future `shared_steps` or `step_templates` feature in the wheel engine would reduce maintenance burden.

3. **Update-mappings extraction is fragile**: The pattern of extracting JSON from a ```json code block in an agent's markdown output relies on the agent formatting its output correctly. If the agent writes the JSON differently (e.g., no code fence, or multiple code blocks), the grep-based extraction fails silently. A more robust pattern (e.g., agent writes to a separate `.json` file, or a dedicated extraction step) would be more reliable.

## Suggestions

- Consider adding a `step_templates` or `include` mechanism to the wheel engine for reusable command step definitions.
- Consider having agent steps write structured data to separate files rather than embedding JSON in markdown output.
