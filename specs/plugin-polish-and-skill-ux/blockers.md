# Blockers: Plugin Polish & Skill UX

## Resolved

No blocking issues found. All 12 FRs pass code-level verification.

## Non-Blocking Observations

### OBS-001: Workflow agent instruction does not reference repo/files fields

**FR**: FR-011, FR-012
**Severity**: Low (non-blocking)
**Description**: The `report-issue-and-sync.json` workflow's `create-issue` agent instruction does not mention the `repo` or `files` frontmatter fields. The `/report-issue` SKILL.md compensates by extracting these values *before* invoking the workflow, so the fields are in conversation context. However, if the workflow is invoked directly via `/wheel-run kiln:report-issue-and-sync` (bypassing the skill), the agent may not populate these fields.
**Mitigation**: The template at `plugin-kiln/templates/issue.md` includes these fields, so the agent has the schema. The SKILL.md path (primary usage) correctly pre-populates them. Direct workflow invocation is an edge case.
**Resolution**: Acceptable as-is for this build. Can be addressed in a future polish pass by adding `repo` and `files` guidance to the workflow agent instruction.
