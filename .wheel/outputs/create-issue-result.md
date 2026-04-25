---
step: create-issue
status: success
issue_file: .kiln/issues/2026-04-24-spec-directory-lacks-temporal-ordering.md
issue_id: 2026-04-24-spec-directory-lacks-temporal-ordering
title: "specs/ directory has no temporal ordering — hard to see what was built when; inconsistent with docs/features/ which is date-prefixed"
type: improvement
severity: medium
area: kiln
category: ergonomics
---

## Step result

Created new backlog issue: `.kiln/issues/2026-04-24-spec-directory-lacks-temporal-ordering.md`

**Classification**
- type: improvement
- severity: medium
- area: kiln
- category: ergonomics

**Duplicate scan**
No exact duplicate locally. Related existing note in Obsidian: `branch-and-spec-directory-naming-is-inconsistent-causes-agent-co` — addresses naming-format inconsistency; this issue addresses temporal-ordering absence. Different aspects of the same pain surface; cross-referenced in the new issue.

**Relevant repo observations**
- `specs/` — 46 entries, alphabetical only
- `docs/features/` — all date-prefixed (YYYY-MM-DD-<slug>)
- One legacy spec (`specs/001-kiln-polish`) has a numeric prefix from before convention settled

**User description (verbatim)**
> we need to figure out how to number specs or something. its a bit of a mess not being able to see what was built when.
