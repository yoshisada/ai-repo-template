# Retrospective Friction Notes — Plugin Clay

**Agent**: retrospective
**Date**: 2026-04-07

## Pipeline Health

- 37/37 FRs covered (100%)
- 0 blockers
- 0 file conflicts across 4 parallel implementers
- 6/6 agents filed friction notes
- 4 Phase 9 tasks unchecked (validation tasks without an owner)

## Top 3 Actionable Improvements

1. **Assign validation tasks to auditor**: Phase 9 (T015-T018) had no owner. The auditor performed equivalent checks but couldn't mark them. Fix: add auditor row to agent assignment table in tasks.md or auto-assign in `/build-prd`.

2. **Verify integration points in /specify**: The specifier inferred plugin discovery paths from PRD descriptions rather than reading wheel source code. The implementer then had to independently discover the real mechanism. Fix: add "verify integration mechanisms by reading source" to specifier prompt.

3. **Reduce auditor idle time**: The auditor was fully blocked until all implementation completed. Fix: allow incremental audits as phases finish — audit scaffold while skills are still being implemented.

## Secondary Improvements

- Enforce consistent mode labels between spec and plan (don't paraphrase)
- Standardize marketplace.json across all plugins (all or none)
- Consider centralized task marking to avoid concurrent edit conflicts on tasks.md

## Retrospective Issue

https://github.com/yoshisada/ai-repo-template/issues/66
