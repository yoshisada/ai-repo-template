# Auditor Friction Notes — wheel-workflow-composition

**Date**: 2026-04-07
**Agent**: auditor

## What went well

- All 18 FRs mapped 1:1 from PRD to spec to code with clear FR-NNN comment annotations.
- The implementer's code was well-structured — each function had its FR references in comments, making traceability straightforward.
- The `parent_workflow` field approach (FR-016) made FR-012/FR-013 fan-in logic clean and auditable. The direct parent reference is more reliable than the PRD's suggested "scan for matching ownership" approach.
- E2e validation tasks (T010-T017) covered all the key scenarios including edge cases (circular, missing refs, depth cap, stop cascade).

## What was confusing

- FR-NNN numbering collision: The wheel plugin has existing FR numbers from prior features (e.g., FR-003, FR-012 mean different things in different contexts). When grepping for `FR-003`, results include both the composition feature's "validate workflow refs" and the original wheel's "dispatch by step type". This made automated tracing noisy — had to manually filter by file context.
- FR-011 vs FR-013: These two FRs overlap significantly. FR-011 says "hook must distinguish parent and child state files" and FR-013 says "hook identifies parent-child by checking workflow step with working status". In practice, the implementation uses `parent_workflow` field (FR-016) for identification, making FR-011 and FR-013 somewhat redundant with each other and with FR-016. The PRD could have consolidated these.

## Where I got stuck

- Initially waited a long time for the implementer to finish because task #1 (specifier) was still in_progress when I first received my assignment. The task dependency chain (#3 blocked by #2 blocked by #1) meant I had to wait through two full phases. Would be useful if the build-prd orchestrator only assigned audit tasks after implementation is confirmed complete.

## Suggestions for improvement

- Consider namespacing FR numbers per feature (e.g., `FR-WFC-001`) to avoid cross-feature collisions in the same codebase.
- For shell-based plugins without a test framework, the audit could benefit from a standardized "validation evidence" format — currently relies on implementer's word that e2e tests passed.
- The PRD's FR-011/FR-013 could be merged or FR-013 could reference FR-016 as the implementation mechanism.
