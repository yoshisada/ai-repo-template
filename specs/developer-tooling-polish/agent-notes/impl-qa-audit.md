# Friction Notes: qa-audit Implementation

**Agent**: impl-qa-audit
**Date**: 2026-04-07
**Tasks**: T002, T009-T016

## What Went Well

- Single SKILL.md file meant all tasks (T009-T014, T016) were implementable in one pass
- Clear contract in interfaces.md with exact report format made implementation straightforward
- Existing skill patterns (qa-checkpoint, kiln-cleanup) provided good templates to follow

## Friction Points

- **tasks.md concurrency**: The shared tasks.md file was modified by the other implementer between my read and write, causing edit failures. Had to re-read before each edit. This is inherent to parallel agents sharing the same tasks.md file.
- **No runtime validation possible**: Since this is a plugin skill (Markdown + Bash instructions for Claude), there's no way to actually execute it during implementation. T015 (E2E validation) was a contract compliance check rather than a true runtime test. The skill will only be validated when run on a consumer project with real test files.

## Blockers

None.

## Suggestions

- For parallel agent workflows, consider giving each agent their own task tracking file to avoid edit conflicts on shared tasks.md.
