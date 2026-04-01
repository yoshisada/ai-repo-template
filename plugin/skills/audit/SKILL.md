---
name: "audit"
description: "Run a PRD compliance audit against the current implementation. Called automatically at the end of /implement. Checks both directions: PRD→Spec and Spec→Code→Test. Attempts to fix gaps, or requires documented blockers."
---

## PRD Compliance Audit

This audit runs as the final step of `/implement`. It checks compliance in **both directions** and either fixes gaps or documents blockers.

### Phase 1: Gather Context

1. Read `docs/PRD.md` — extract every functional requirement, user story, and deliverable.
2. Read `.specify/memory/constitution.md` for governing principles.
3. Find all specs in `specs/*/spec.md` — extract all FR-NNN requirements.
4. Find all tasks in `specs/*/tasks.md` — verify all are marked `[x]`.

### Phase 2: PRD → Spec Coverage (CRITICAL — run this FIRST)

**For each requirement in the PRD** (functional requirements, deliverables, user stories):

Check if at least one spec FR covers it. Produce a table:

```
| PRD Requirement | Covered by FR | Status |
|-----------------|---------------|--------|
| "base starter from Takeout" | FR-001, FR-002 | PASS |
| "clear docs for setup" | — | FAIL |
```

**If any PRD requirement has NO covering FR, this is a FAIL — not a note, not LOW priority.**

For each uncovered PRD requirement:

1. **Add the missing FR** to `specs/<feature>/spec.md`:
   - Assign the next available FR number (e.g., FR-020)
   - Write a testable requirement that satisfies the PRD
   - Add an acceptance scenario under the appropriate user story

2. **Add a task** to `specs/<feature>/tasks.md` for the new FR

3. **Implement the new FR** — write the code and tests

4. **If the FR cannot be added** (PRD requirement is contradictory, out of scope, or blocked):
   - Document in `specs/<feature>/blockers.md` (see Phase 4)

**Do NOT proceed to Phase 3 until every PRD requirement has a covering FR (or a documented blocker).**

### Phase 3: Spec → Code → Test Coverage

For each FR-NNN in the spec:

| Check | How | Grade |
|-------|-----|-------|
| Spec → Code | Does source code contain `// FR-NNN` comment? | PASS / FAIL |
| Code → Test | Does a test reference the acceptance scenario? | PASS / FAIL |
| Tech stack | Does the implementation use the PRD's required tech stack? | PASS / FAIL |
| Scope creep | Is anything built that wasn't in the spec? | PASS / WARN |

Produce a summary table:
```
| FR | Spec→Code | Code→Test | Status |
|----|-----------|-----------|--------|
| FR-001 | PASS | PASS | ✓ |
| FR-020 | PASS | PASS | ✓ (new — added in Phase 2) |
```

### Phase 4: Fix or Block

**If compliance >= 100%**: Report PASS. Implementation is complete.

**If compliance < 100%**: For each failing check:

1. **Attempt to fix** — if the gap is:
   - PRD requirement has no FR → **add FR to spec, implement it, test it** (Phase 2)
   - Missing `// FR-NNN` comment → add it to the correct function
   - Missing test scenario reference → add the comment to the test
   - Missing test for an acceptance scenario → write the test
   - Missing implementation for a spec FR → implement it
   - Report what was fixed and re-run that check

2. **If the gap cannot be fixed** — because:
   - The PRD requirement contradicts another requirement
   - A dependency is unavailable (API, service, hardware)
   - The requirement is out of scope for the current phase
   - The tech stack constraint makes it impossible

   Then **require a blocker entry**:

   Create or append to `specs/<feature>/blockers.md`:
   ```markdown
   ## Blocker: [PRD requirement or FR-NNN] — [description]

   **Status**: BLOCKED
   **Reason**: [specific reason this cannot be fixed]
   **Impact**: [what user-facing functionality is affected]
   **Resolution path**: [what would need to change — PRD update, dependency available, etc.]
   **Date**: [ISO date]
   ```

3. **After all gaps are addressed** (fixed or blocked):
   - Re-run the full audit (Phase 2 + Phase 3) on fixed items
   - If any blockers were written, **STOP and ask the user**:
     ```
     PRD Audit: X of Y requirements pass. Z blockers documented.

     Blockers:
     - [requirement]: [reason]

     These are documented in specs/<feature>/blockers.md.
     Do you want to proceed with these known gaps? (yes/no)
     ```
   - Wait for user confirmation before continuing
   - If user says no → halt, leave blockers.md for review
   - If user says yes → proceed, implementation is accepted with documented gaps

### Phase 5: Report

Final output:
```
PRD Coverage: XX% (Y/Z PRD requirements have covering FRs)
FR Compliance: XX% (Y/Z FRs implemented and tested)

- PASS: N requirements fully covered end-to-end
- FIXED: N gaps resolved during audit (including N new FRs added)
- BLOCKED: N requirements with documented blockers
- FAIL: N requirements still failing (should be 0)
```

### Rules

- **Phase 2 (PRD→Spec) runs FIRST and is a hard gate** — uncovered PRD requirements are not notes or warnings, they are failures that must be addressed
- Read actual source files, not just filenames
- Quote specific file:line when citing gaps
- Distinguish "not implemented" from "implemented differently than specified"
- Never silently skip a failing requirement — every gap must be fixed or blocked
- New FRs added during audit get the next sequential number
- The user MUST confirm if any blockers exist before the audit passes
