---
id: 2026-04-24-team-readiness-minimum-diff
title: "team-readiness-minimum-diff — audit which file-based state survives normal git workflows and which needs targeted coordination"
kind: research
date: 2026-04-24
status: open
phase: 90-queued
state: planned
blast_radius: cross-cutting
review_cost: moderate
context_cost: ~1 session
---

# team-readiness-minimum-diff — audit which file-based state survives normal git workflows and which needs targeted coordination

## The decision this unblocks

Whether the vision's "team-ready later" commitment is a cheap follow-on (git-native workflows cover ~most of it) or a structural redesign (we've boxed ourselves in with coordination assumptions that don't survive a second user). Checking the walls now is cheap; discovering them during actual team adoption is expensive.

## Working hypothesis

Most team-collaboration concerns with file-based state reduce to the same problems users already face with git itself — concurrent edits → merge conflicts, number collisions → branch rebases, stale local views → fetch + rebase. If this hypothesis holds, the minimum diff for team-readiness is small: document the git workflow patterns that work, identify the handful of state files that DON'T survive git semantics, and add targeted coordination only for those.

The research is framed as "what breaks git's normal concurrent-editing affordances," not "how do we invent multi-user coordination."

## Scope

Audit every stateful file / directory in the repo and classify each as:

- **Git-native safe** — two users working concurrently produce normal merge conflicts that humans resolve as usual (e.g., `.kiln/roadmap/items/<dated>-<slug>.md` — slug collisions are resolved by the existing uniqueness counter in the roadmap skill, file-level conflicts in Obsidian-mirror bodies are normal text conflicts).
- **Problematic under git but survivable** — state files where concurrent writes produce conflicts but the resolution is mechanical (e.g., `VERSION` auto-increment on every edit → two branches both bump, fourth-segment increments race; fix by rebase-and-rebump).
- **Needs targeted coordination** — state files where concurrent writes break the invariant in ways git can't resolve (candidates to inspect: counter files like `shelf_full_sync_counter` in `.shelf-config`, `.version.lock` directory, `.wheel/state_*.json` if two users run workflows simultaneously, Obsidian mirror writes that target the same note from two sessions).

## Specific things worth inspecting

- `.shelf-config` counter fields (`shelf_full_sync_counter`) — what happens when two users each increment independently and merge?
- `.version.lock` — a transient directory; what's the teardown semantics under concurrent access?
- `.wheel/state_*.json` — per-session state, but the archival path (`.wheel/history/`) needs to not collide on concurrent archives.
- Obsidian mirror writes — two users writing to the same note via MCP; last-write-wins is probably the actual behavior; is that OK or does it silently lose one user's work?
- `.kiln/issues/NNN-*.md` — numeric prefix assignment; do two users creating issues concurrently produce collisions that git doesn't catch?
- Roadmap item slug uniqueness — currently handled via counter suffix, but the uniqueness check is local-only; two users racing wouldn't see each other's writes.

## Out of scope (deliberately)

- Not designing a locking system. Not designing a central state server. Not designing a coordination daemon. The research is an audit; the minimum diff is whatever the audit surfaces as NEEDING coordination — keeping the solo-first / file-based-state thesis intact is the constraint, not "add infrastructure until team-ready."

## Time-box

1 session. This is a classification exercise, not an implementation.

## What "done" looks like

A short decision doc at `.kiln/roadmap/` or `docs/research/` with:

1. A table of every stateful file/directory + its classification (git-native safe / survivable / needs coordination).
2. For "needs coordination" items: one-sentence statement of the actual breakage and a cheapest-possible mitigation sketch (e.g., "move `.shelf-config` counter into a git-merge-safe format" or "require `.wheel/history/` archives to use `<session-id>` in filename to avoid collision").
3. Go/no-go assessment: is team-readiness a cheap follow-on or a structural problem? If cheap, identify the handful of items that must be addressed and their rough scope; if structural, surface the hard blocker and update the vision's team-ready-later commitment to reflect the real cost.

## Audience for the conclusion

You. Input for a future decision on whether to promote team-readiness from "direction" to "active phase" or to downgrade the commitment in the vision if the walls turn out to be closer than expected.

## Cheapest directional answer first

If the full audit is too expensive, a 30-minute scan of just the counter-and-lock files (`.shelf-config`, `.version.lock`, `.wheel/state_*.json`) will surface ~80% of the "needs coordination" candidates. Obsidian-mirror race conditions are second priority.

## Dependencies

- No blocking dependencies — pure audit exercise.
- Pairs naturally with `2026-04-24-language-agnostic-research` — both are low-urgency research items that de-risk future vision-promoted phases before committing to them.
