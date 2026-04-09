# Specifier Agent Notes — trim-penpot-layout

**Date**: 2026-04-09

## Friction

- The PRD had 15 FRs but the spec user stories naturally grouped them into 4 stories (2 at P1, 2 at P2). US2 (page separation) ended up being identical to part of US1 (no overlap) because the same positioning + page separation logic covers both. This meant Phase 4 in tasks.md is intentionally empty — the task breakdown merges US1 and US2 implementation.

- The "no new files" constraint is important context that's easy to miss. All deliverables are text edits to existing agent instruction strings inside JSON files. The contracts had to define text blocks to prepend/append rather than function signatures.

- Auto-flow discovery has three separate implementations (push=code scan, pull=Penpot analysis, design=PRD parsing) because each command has different context available. This tripled the flow discovery tasks but each is independent.

## Decisions

- Positioned Components page logic in the same agent steps (push-to-penpot, generate-design) rather than as separate workflow steps, to avoid extra MCP round-trips.
- Flow discovery is a new separate agent step in each workflow rather than embedded in existing steps, because it's a distinct concern that reads different context.
