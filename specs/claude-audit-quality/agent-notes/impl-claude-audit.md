# impl-claude-audit friction notes — Themes A-E

**Owner**: impl-claude-audit
**Branch**: build/claude-audit-quality-20260425
**Phase**: 2A.A through 2A.E
**Files touched**: `plugin-kiln/skills/kiln-claude-audit/SKILL.md`, `plugin-kiln/skills/kiln-doctor/SKILL.md`, `plugin-kiln/rubrics/claude-md-usefulness.md`, `specs/claude-audit-quality/tasks.md`

## Summary

Themes A-E landed cleanly. NFR-001 bash-side bench post-PR median = **0.693 s** (5-run sorted: 0.591, 0.641, 0.693, 0.803, 0.859) vs pre-PR baseline 0.786 s — **PASS** (+30% gate is 1.022 s; post-PR is below the baseline within noise — none of my edits added bash work). NFR-004 backward compat preserved: every existing rubric rule continues to fire as before; all new rules + reordering are purely additive.

Five commits, one per theme: T010-T013 (Theme A) + T020-T026 (Theme B) committed in one combined commit b0590c3 (the post-T013 commit was swept into impl-tests-and-retro's Theme F commit 936659f — see "Friction 1" below). Theme C = 4ad85a3. Theme D = 9853688. Theme E = pending separate commit at this note's write time.

## What was confusing

### Friction 1 — Co-occupancy of the staging area with impl-tests-and-retro

I staged my Theme A files (rubric preamble + SKILL.md Step 3 contract + SKILL.md Step 3.6 invariant) and was about to commit when impl-tests-and-retro's Theme F commit landed first. The commit message claimed "this commit does not touch claude-md-usefulness.md or kiln-claude-audit/SKILL.md" but the diff stat showed +14 / +60 lines for those files — i.e., my staged Theme A changes were swept into Theme F's commit (936659f).

This is not catastrophic — the work is in the tree on the same branch — but the git history is now slightly misleading: anyone running `git log --follow -- plugin-kiln/rubrics/claude-md-usefulness.md` will see Theme A changes attributed to Theme F's commit message. I worked around it by including a clarifying note in my Theme B commit message (b0590c3) saying "Theme A landed in 936659f's diff stat alongside Theme F". A more graceful workflow would have either (a) used worktrees for parallel implementers (each gets their own staging area) or (b) had the orchestrator queue commits per implementer with explicit ordering. **PI Proposal 1 (below)** suggests the latter.

### Friction 2 — Step renumbering risk-vs-reward in T032

The contracts/interfaces.md §4 ordering says:
```
Step 1, 2, 3, 3.5, 4, 4.5, 5, 6
```

The pre-PR SKILL.md had 13 steps with sub-numbering (`1`, `1b`, `2`, `2.5`, `3`, `3.5` (sync), `3b` (external), `4`, `5`). T032 demanded reordering to put substance pass at Step 2. Doing this faithfully required:
- Renaming existing Step 2 (rubric load) → Step 1c
- Renaming existing Step 2.5 (classify) → Step 1d
- Inserting NEW Step 2 (substance pass)
- Renaming Step 3.5 (sync composers) → Step 3.7 (because the new Step 3.5 is the invariant per contracts §4)
- Renaming Step 3.6 (invariant from Theme A) → Step 3.5
- Renaming Step 3b (external) → Step 5
- Splitting Step 4 (write) → Step 4 (render) + Step 6 (write)
- Renaming Step 5 (report) → Step 7
- Adding Step 4.5 (sibling preview placeholder, filled in Theme E)

That's 9 mechanical renames + 2 inserts touching ~13 anchor lines in a single 700-line file. The risk of accidentally orphaning a back-reference (e.g. another step pointing at "Step 3.5" meaning sync composers when I'd just renamed it to invariant) was real. I mitigated by (a) doing the renames in dependency order (deepest first), (b) adding inline `> **Renumbered from X → Y**` notes at each rename site so back-readers can resolve, and (c) verifying with grep after each rename. **PI Proposal 2 (below)** suggests a build-time anchor-validation step.

The result is non-monotonic textual order in the file (Step 5 textually appears between Step 3.7 and Step 3.5 because I did in-place renames rather than moving large blocks). The execution order is still sound — each step's preamble names its predecessors and successors explicitly — but a reader scrolling top-to-bottom will see step labels out of numerical order. I noted this in the T032 task-completion line and flagged it for auditor verification.

### Friction 3 — `signal_type: substance` for `recent-changes-anti-pattern` collides with topical grouping

Per contracts §2: `recent-changes-anti-pattern` has `signal_type: substance` (sorts to top of Signal Summary alongside the four FR-006..FR-009 substance rules) BUT the contract also says "lives under whatever existing section groups the freshness/bloat rules (impl picks the location to minimize churn)." These two cuts conflict — substance rules are under `## Substance rules` (a new section); freshness/bloat rules are under `## Rules` (the existing section).

I chose topical grouping: placed `recent-changes-anti-pattern` adjacent to `recent-changes-overflow` in `## Rules` (so a maintainer reading about Recent Changes finds both rules together), and added an explicit clarifying paragraph in the rule body noting "co-located with `recent-changes-overflow` for topical grouping but evaluated under the substance rules' precedence". This satisfies the contract's spirit while keeping topical co-location.

## What guidance was missing

1. **Step renumber strategy**: contracts/interfaces.md §4 listed the target step numbers but did not specify whether to (a) rename in place (text non-monotonic, smaller blast radius) or (b) physically reorder large blocks (text monotonic, higher blast radius). I chose (a). The contract should call this out: "Implementer MAY rename in place; textual non-monotonicity is acceptable as long as each step's preamble names its execution-order predecessors/successors."

2. **Co-occupancy protocol**: when two implementers concurrently edit the same branch, the workflow doesn't specify how to serialize commits. The plan.md said "impl-claude-audit and impl-tests-and-retro share zero files" — TRUE for the file LIST, but staging area is shared, so concurrent `git add` + `git commit` pairs can sweep across implementers. A worktree-per-implementer or commit-queue pattern would prevent this.

3. **`recent-changes-anti-pattern` placement**: contracts §2 said "minimize churn" but didn't disambiguate the substance-vs-topical placement conflict. Resolved by topical grouping + clarifying paragraph; would have been faster with explicit guidance.

## PI proposals (bold-inline format — Current must be a verbatim substring of the target file)

### PI 1 — Worktree-per-implementer or commit serialization in build-prd

**File**: `plugin-kiln/skills/kiln-build-prd/SKILL.md`

**Current**:
```
The user interacts primarily with the team lead. Your work is coordinated through the task system and teammate messaging.
```

**Proposed**:
```
The user interacts primarily with the team lead. Your work is coordinated through the task system and teammate messaging.

**Co-occupancy hazard**: when two implementers (e.g. impl-A and impl-B) work on the same branch concurrently, their staging areas are shared. If both `git add` and one commits before the other, the second's staged changes get swept into the first's commit. Mitigations: (a) use git worktrees per implementer (recommended for >1 concurrent implementer), (b) serialize commits via the team-lead acting as commit gatekeeper, or (c) accept the sweep and add a clarifying note to the next commit message.
```

**Why**: Observed during claude-audit-quality build (commit 936659f's diff stat included +60 lines to kiln-claude-audit/SKILL.md attributed to a Theme F commit message that explicitly disclaimed touching that file; those lines were impl-claude-audit's Theme A staged changes, swept in by the concurrent impl-tests-and-retro commit). Git history is now slightly misleading. A worktree-per-implementer pattern would have prevented this.

### PI 2 — Build-time anchor validator for SKILL.md cross-references

**File**: `plugin-kiln/skills/kiln-claude-audit/SKILL.md`

**Current**:
```
- `load-bearing-section` always wins over any other rule for the same section, **EXCEPT** for `enumeration-bloat` (claude-md-audit-reframe FR-031) on `plugin-surface`-classified sections — that rule WINS over load-bearing because re-enumerating runtime-provided context is bloat regardless of citations.
```

**Proposed**:
```
- `load-bearing-section` always wins over any other rule for the same section, **EXCEPT** for `enumeration-bloat` (claude-md-audit-reframe FR-031) on `plugin-surface`-classified sections — that rule WINS over load-bearing because re-enumerating runtime-provided context is bloat regardless of citations.
- **Internal anchor validation** (claude-audit-quality follow-on): whenever this skill body references a Step number (e.g. "Step 3.5 invariant", "Step 4.5 below"), the referenced step MUST exist in the same file. A simple grep-based CI check (`for ref in $(grep -oE 'Step [0-9]+(\.[0-9]+)?[a-z]?' SKILL.md | sort -u); do grep -qE "^## $ref " SKILL.md || echo "orphan: $ref"; done`) can catch broken anchors after a renumber.
```

**Why**: T032's renumbering moved 9 step anchors. I caught all back-references by hand-verification + grep, but a build-time validator would prevent regressions on future renumbers (e.g. when a future PR re-orders Steps again).

### PI 3 — `## Substance rules` + topical-grouping disambiguation in interface contracts

**File**: `specs/claude-audit-quality/contracts/interfaces.md`

**Current**:
```
Each rule below MUST appear in `plugin-kiln/rubrics/claude-md-usefulness.md` as a `### <rule_id>` heading followed by the fenced block, then prose (rationale + known false-positive shape). Order within the rubric file: substance rules grouped under a `## Substance rules` heading, listed in FR order (006, 007, 008, 009); `recent-changes-anti-pattern` lives under whatever existing section groups the freshness/bloat rules (impl picks the location to minimize churn).
```

**Proposed**:
```
Each rule below MUST appear in `plugin-kiln/rubrics/claude-md-usefulness.md` as a `### <rule_id>` heading followed by the fenced block, then prose (rationale + known false-positive shape). Order within the rubric file: substance rules grouped under a `## Substance rules` heading, listed in FR order (006, 007, 008, 009); `recent-changes-anti-pattern` carries `signal_type: substance` (sorts under substance precedence) but is placed adjacent to `recent-changes-overflow` in the existing freshness/bloat group for topical co-location. The rule body MUST contain a one-sentence clarification noting the co-location is by topic, not by signal_type group.
```

**Why**: Implementing `recent-changes-anti-pattern` required resolving "substance signal_type vs topical-grouping placement" without explicit guidance. The current contract wording is ambiguous; the proposed wording makes the convention explicit.

## NFR sanity verification

- **NFR-001** (bash-side ≤ 1.022 s gate): post-PR median = **0.693 s** (5 runs). PASS with significant headroom. Source script: `/tmp/audit-bench.sh` reproduced verbatim from research.md §Baseline.
- **NFR-003** (within-scope idempotence): structural sanity only — full byte-identity verification reserved for auditor T083. New rules' rendering rules are deterministic (sort key extended to substance, fixed-text rendering rules, no wall-clock interpolation in body). No-X-path byte-identity carve-out documented in spec NFR-003.
- **NFR-004** (back-compat): existing rules untouched; all changes additive. New ctx_json_paths field is optional; existing rules without it behave as before. New `signal_type: substance` value extends the enum; existing values preserved.

## Done

- Themes A-E commits: 936659f (Theme A swept in with Theme F) → b0590c3 (Theme B + Theme A commit message clarification) → 4ad85a3 (Theme C) → 9853688 (Theme D) → pending (Theme E).
- Friction note: this file.
- Next: SendMessage to impl-tests-and-retro with subject "rules ready" listing new rule_ids + SKILL.md sections (Phase 2C unblocks).
