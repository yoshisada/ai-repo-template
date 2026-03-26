---
name: "speckit-audit"
description: "Run a PRD compliance audit against the current implementation. Called automatically at the end of /speckit.implement. Attempts to fix gaps, or requires documented blockers before proceeding."
---

## PRD Compliance Audit

This audit runs as the final step of `/speckit.implement`. It verifies the implementation matches the PRD and spec, attempts to fix any gaps, and provides an escape hatch for legitimate blockers.

### Phase 1: Gather Context

1. Read `docs/PRD.md` for product requirements.
2. Read `.specify/memory/constitution.md` for governing principles.
3. Find all specs in `specs/*/spec.md` — extract all FR-NNN requirements.
4. Find all tasks in `specs/*/tasks.md` — verify all are marked `[x]`.

### Phase 2: Audit

For each PRD functional requirement:

| Check | How | Grade |
|-------|-----|-------|
| PRD → Spec coverage | Does a spec FR cover this PRD requirement? | PASS / FAIL |
| Spec → Code coverage | Does source code contain `// FR-NNN` referencing this FR? | PASS / FAIL |
| Code → Test coverage | Does a test reference the acceptance scenario? | PASS / FAIL |
| Tech stack | Does the implementation use the PRD's required tech stack? | PASS / FAIL |
| Scope creep | Is anything built that wasn't in the spec? | PASS / WARN |

Produce a summary table:
```
| FR | PRD→Spec | Spec→Code | Code→Test | Status |
|----|----------|-----------|-----------|--------|
| FR-001 | PASS | PASS | PASS | ✓ |
| FR-002 | PASS | FAIL | — | ✗ |
```

Calculate overall compliance: `(passing checks / total checks) * 100`

### Phase 3: Fix or Block

**If compliance >= 100%**: Report PASS. Implementation is complete.

**If compliance < 100%**: For each failing check:

1. **Attempt to fix** — if the gap is:
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
   ## Blocker: FR-NNN — [requirement description]

   **Status**: BLOCKED
   **Reason**: [specific reason this cannot be fixed]
   **Impact**: [what user-facing functionality is affected]
   **Resolution path**: [what would need to change — PRD update, dependency available, etc.]
   **Date**: [ISO date]
   ```

3. **After all gaps are addressed** (fixed or blocked):
   - Re-run the audit on fixed items
   - If any blockers were written, **STOP and ask the user**:
     ```
     PRD Audit: X of Y requirements pass. Z blockers documented.

     Blockers:
     - FR-NNN: [reason]
     - FR-NNN: [reason]

     These are documented in specs/<feature>/blockers.md.
     Do you want to proceed with these known gaps? (yes/no)
     ```
   - Wait for user confirmation before continuing
   - If user says no → halt, leave blockers.md for review
   - If user says yes → proceed, implementation is accepted with documented gaps

### Phase 4: Report

Final output:
```
PRD Compliance: XX% (Y/Z requirements)
- PASS: N requirements fully implemented and tested
- FIXED: N gaps resolved during audit
- BLOCKED: N requirements with documented blockers
- FAIL: N requirements still failing (should be 0)
```

### Rules

- Read actual source files, not just filenames
- Quote specific file:line when citing gaps
- Distinguish "not implemented" from "implemented differently than specified"
- Never silently skip a failing requirement — every gap must be fixed or blocked
- The user MUST confirm if any blockers exist before the audit passes
