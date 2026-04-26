---
title: "build-prd pipeline does not auto-flip roadmap item status/state on PR merge"
type: improvement
severity: medium
category: workflow
source: manual
github_issue: null
date: 2026-04-25
repo: https://github.com/yoshisada/ai-repo-template
files:
  - .kiln/roadmap/items/2026-04-23-wheel-user-input.md
  - plugin-kiln/scripts/roadmap/update-item-state.sh
  - plugin-kiln/skills/kiln-build-prd/SKILL.md
  - plugin-kiln/skills/kiln-roadmap/SKILL.md
status: promoted
roadmap_item: .kiln/roadmap/items/2026-04-25-build-prd-auto-flip-item-state.md
---

## Description

When `/kiln:kiln-build-prd` ships a PRD via merged PR, the roadmap items the PRD was distilled from are NOT automatically advanced. They stay frozen at whatever state `/kiln:kiln-distill` set (`status: in-progress, state: distilled`) even after the PR has merged and the work is live.

Concrete example: `wheel-user-input` shipped via PR #155 (merged 2026-04-25 at 00:23 UTC). One day later, `.kiln/roadmap/items/2026-04-23-wheel-user-input.md` still showed:

```yaml
status: in-progress
state: distilled
# no `pr:` field, no shipped_date, nothing
```

The drift was only caught during a `/kiln:kiln-distill --phase 09-research-first` run when the FR-020 single-in-progress-phase invariant tripped, forcing a manual audit of `08-in-flight`. Two of the four items in that phase were stale (the second was still genuinely unbuilt — `claude-md-audit-reframe` — but the staleness on `wheel-user-input` masked the real conflict).

The workaround was a manual flip via `plugin-kiln/scripts/roadmap/update-item-state.sh <path> shipped` followed by a python frontmatter patch to update `status: shipped` and add `pr: 155` (since `update-item-state.sh` only touches the `state:` line — see its own `Usage:` comment).

## Impact

- **Roadmap state stops being trustworthy as a source of "what's still in flight"** the moment any PRD ships without manual cleanup. `/kiln:kiln-roadmap --phase start <new>` is the canary — it bounces with FR-020 conflict naming the wrong phase, and the user has to audit by hand to figure out which items are genuinely-not-yet-built vs stale.
- **The phase-completion invariant becomes unenforceable in practice.** The intent of "only one phase in-progress" is to keep focus, but if shipped items don't auto-shipped-flip, every phase-end requires a manual sweep across all items — exactly the kind of toil this whole layer is supposed to eliminate.
- **Provenance is lost.** No `pr:` back-reference on the item means future debugging (e.g., bisecting which build PR introduced a regression in a feature) requires a separate `git log` walk instead of just reading the item's frontmatter.
- **`/kiln:kiln-roadmap --check`** (the FR-022 consistency report) does not catch this class of drift — it currently reports `state:distilled` items where the PRD file is missing, but does not cross-reference whether the PRD's build branch has merged.

## Suggested Fix

Two complementary changes; either alone would mostly close the gap, both together would close it cleanly.

### A — Auto-flip on PR merge (the proactive fix)

In `/kiln:kiln-build-prd` (or a post-merge step it owns), after the PR merges:

1. Read the merged PRD's `derived_from:` frontmatter to identify the roadmap items the PRD was distilled from.
2. For each item path matching `.kiln/roadmap/items/*.md`:
   - Run `plugin-kiln/scripts/roadmap/update-item-state.sh <path> shipped`
   - Patch frontmatter: `status: shipped`, add `pr: <number>` (the merged PR number).
3. Commit the item-frontmatter patches in the same merge or as an immediate follow-up commit on `main`.

This requires `update-item-state.sh` (or a sibling helper) to also touch `status:` — currently it only touches `state:`. A new `update-item-status.sh` helper, or extending the existing one to take `--status <value>`, would do it.

### B — Detection helper (the reactive safety net)

Extend `/kiln:kiln-roadmap --check` (FR-022 of structured-roadmap) with an additional cross-check:

For every item with `state: distilled` or `state: specced` AND a populated `prd:` field:
- Resolve the PRD's expected build branch (heuristic: `build/<theme-slug>-YYYYMMDD` matching the PRD's `theme:` and `distilled_date:`).
- Query `gh pr list --state merged --head <branch>` (or scan `git log --all --grep="<theme-slug>"` for offline mode).
- If a merged PR exists, flag the item as "build merged but item state stale" with the PR number and a one-liner copy-paste fix suggestion (`update-item-state.sh <path> shipped`).

This catches every existing drifted item across the 81-item roadmap in one sweep, not just future ones. Especially important since this issue almost certainly affects more items than just `wheel-user-input` — every PRD that has shipped since the structured-roadmap layer landed (PR #153) is a candidate for the same staleness.

### Bonus — cheap version

If A is too invasive (touching the build pipeline is expert review-cost), ship B alone first as a tripwire. `/kiln:kiln-roadmap --check` already exists; adding the merged-PR cross-reference is bounded scope and gives the maintainer a one-command audit instead of a manual sweep.
