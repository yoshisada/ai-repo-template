# Retrospective: pipeline-workflow-polish

**Branch**: `build/pipeline-workflow-polish-20260401`
**Date**: 2026-04-01
**PR**: #37
**Pipeline Duration**: ~18 minutes (spec commit to PR)
**FR Coverage**: 16/16 (100%), 0 blockers

## Pipeline Timeline

| Phase | Duration | Notes |
|-------|----------|-------|
| PRD commit + branch creation | ~8 min | Includes branching from main |
| Spec + plan + tasks (specifier) | ~2 min | Single commit, all 16 FRs |
| Implementation (2 parallel agents) | ~5 min | 8 commits, clean parallel split |
| Audit + PR (auditor) | ~2 min | 1 commit (blockers.md), PR created |
| Total | ~18 min | Efficient for 16 FRs |

## What Went Well

1. **Clean parallel split**: Two implementers (impl-pipeline: 13 tasks, impl-tooling: 6 tasks) operated on disjoint file sets with zero merge conflicts. The task breakdown's file ownership table was the key enabler.

2. **100% FR coverage**: All 16 FRs passed audit with no blockers. The spec-to-implementation traceability (FR tags in commit messages and code) was consistent.

3. **Spec quality**: The specifier produced a complete spec, plan, contracts, and tasks in a single commit. The contracts/interfaces.md file gave implementers unambiguous placement guidance.

4. **Commit discipline**: Each implementer grouped related FRs into logical commits (FR-001-003, FR-004-006, etc.) rather than one-commit-per-task or one-giant-commit.

5. **Non-compiled nature acknowledged**: The pipeline correctly recognized this as a non-compiled feature and skipped the 80% coverage gate (though the validation script itself wasn't run as a self-test — T018/T019 deferred).

## Friction Points and Analysis

### F1: build-prd SKILL.md file size (700+ lines)

**Source**: impl-pipeline agent notes.

**Problem**: Reading and editing a 700+ line skill file requires multiple offset/limit passes, slowing orientation and increasing the chance of edit conflicts.

**Prompt Rewrite**: Add to implementer prompt: "For files over 500 lines, read the table of contents or section headers first (lines 1-30) to orient, then read only the target section."

**Structural Fix**: Consider splitting build-prd/SKILL.md into composable sections (e.g., `build-prd/sections/agent-prompts.md`, `build-prd/sections/pipeline-steps.md`) that the main SKILL.md includes by reference.

### F2: Version-increment hook causes "file modified since read" errors

**Source**: impl-pipeline agent notes.

**Problem**: The version-increment hook fires on every Edit/Write, modifying tasks.md between reads. Agents must re-read files after edits to avoid stale content errors.

**Prompt Rewrite**: Add to implementer prompt: "After any Edit/Write to a file in the plugin directory, the version-increment hook may modify VERSION and tasks.md. Re-read any file you plan to edit again immediately before the next edit."

**Note**: FR-011 (this very feature) partially addresses this by staging version changes rather than committing them, but the underlying re-read issue remains.

### F3: T018/T019 (self-validation) deferred

**Problem**: The validation script created in FR-001 was not run against the pipeline's own output. This means the feature that adds validation was itself not validated by that feature — a missed opportunity for dogfooding.

**Prompt Rewrite**: Add to auditor prompt: "If the feature includes a validation script or test tool, the audit MUST run it against the feature's own artifacts as a self-test. Do not defer this."

### F4: Only one implementer wrote friction notes

**Problem**: Only impl-pipeline wrote agent notes. impl-tooling, specifier, and auditor did not. The retrospective has incomplete signal.

**Prompt Rewrite**: Add to ALL agent prompts (not just implementers): "Before marking your task complete, write friction notes to `specs/<feature>/agent-notes/<your-role>.md`. Include: what went well, friction points, and suggestions. This is required, not optional."

### F5: No teammate responses to retrospective queries

**Problem**: By the time the retrospective agent ran, other agents had already completed and may have shut down. The message-based feedback collection yielded no responses.

**Prompt Rewrite**: Change retrospective approach — instead of messaging teammates (who may be gone), rely on agent-notes/ files written during execution. Add to retrospective agent prompt: "Do not depend on SendMessage responses from teammates. Read `specs/<feature>/agent-notes/*.md` as your primary input. SendMessage is supplementary."

### F6: Specifier prompt vs /specify skill tension

**Source**: impl-pipeline agent notes.

**Problem**: FR-005 adds spec directory naming enforcement to the specifier's prompt inside build-prd. But the specifier invokes /specify, which has its own directory-creation logic. There may be a conflict between the two naming approaches that wasn't tested.

**Structural Fix**: The specifier prompt in build-prd should pass the canonical spec directory name as an argument to /specify rather than adding separate instructions that may conflict with the skill's built-in logic.

## Communication Effectiveness

| Aspect | Rating | Notes |
|--------|--------|-------|
| Spec clarity | High | 16 FRs well-defined with acceptance scenarios |
| Task decomposition | High | Clean parallel split, no conflicts |
| Contract compliance | High | All FRs traced to implementations |
| Agent coordination | Medium | No runtime conflicts, but feedback loop incomplete |
| Prompt completeness | Medium | Missing agent-notes requirement for most roles |
| Retrospective signal | Low | Only 1/4 agents provided notes, no message responses |

## Recommendations for Next Pipeline Run

1. **Require agent-notes from all roles** — make it a gate, not optional
2. **Split large SKILL.md files** — build-prd is becoming unwieldy
3. **Self-test validation tools** — if the feature adds tooling, the audit must run it
4. **Retrospective should read files, not wait for messages** — teammates may be done
5. **Pass canonical names as arguments** — avoid prompt-vs-skill instruction conflicts
6. **Add section anchors to large files** — helps agents navigate efficiently
