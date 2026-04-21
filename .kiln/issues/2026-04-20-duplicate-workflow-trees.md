# Duplicate workflow trees — root workflows/ vs plugin-*/workflows/

**Source**: GitHub #115 (manifest-improvement retrospective), auditor friction note
**Priority**: high
**Suggested command**: `/fix remove or mark-deprecated the root workflows/ tree — audit blanket grep **/workflows/*.json hits scaffold copies with bare plugin-shelf/scripts paths and produces false portability-bug flags`
**Tags**: [auto:continuance]

## Description

The repo has two workflow trees: `plugin-*/workflows/*.json` (the authoritative plugin source) AND `workflows/*.json` at repo root (older/scaffold copies). An auditor running the team-lead's blanket `grep **/workflows/*.json` hits the scaffold copies and surfaces bare `plugin-shelf/scripts/…` paths — a false positive for the FR-16 portability check. The next auditor will hit the same trap. Either delete the root tree, rename it to make the scaffold nature obvious, or update team-lead instructions to scope greps to `plugin-*/workflows/`.
