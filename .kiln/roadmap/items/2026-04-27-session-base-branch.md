---
id: 2026-04-27-session-base-branch
title: "Session base-branch model — agent runs branch off a 'session base', not main; merges land on the session branch first"
kind: research
date: 2026-04-27
status: open
phase: 89-brainstorming
state: planned
blast_radius: cross-cutting
review_cost: careful
context_cost: "2 sessions"
---

# Session base-branch model — agent runs branch off a 'session base', not main; merges land on the session branch first

## The idea

Today, every `/kiln:kiln-build-prd` run branches off whatever HEAD the user is currently sitting on (often `main`). When the PR merges, it lands on `main` directly. This is fine for one-PR-per-session work but breaks down when:

- The user wants to chain multiple PRDs in a single working session and review the cumulative diff before any of it touches `main`
- The user wants to test the combined effect of N independent PRs against the same starting point before merging anything to `main`
- A session goes wrong and needs to be rolled back wholesale (not per-PR)
- The user wants to "stage" a session's worth of work for review by another stakeholder before promoting to `main`

Proposal: introduce a **session base-branch** concept.

- A session declares (or auto-generates) a base branch — e.g. `session/<slug>-<YYYYMMDD>` — branched off `main` at session start
- Every `/kiln:kiln-build-prd` run inside the session branches off the **session base branch**, not `main`
- PR merges land on the **session base branch**, not `main`
- `main` stays unchanged for the duration of the session
- At session end: run the test suite against the session base branch, review the cumulative diff vs `main`, then either fast-forward / squash-merge the session base into `main`, or abandon

## Why this matters

The current model conflates "the agent's working trunk for this session" with "the project's trunk." That's fine when sessions ship one PR at a time, but the value proposition of a mostly-autonomous build system is multi-PR sessions. The session-base-branch model lets the user batch-review a session's output without giving up build-prd's per-PR audit trail.

Also: easier to test. Today, if I want to verify that PR #189 + PR #186 + a third just-shipped PR all play nicely together at runtime, I have to merge them all to `main` and pray. Session base branch lets me run the integrated suite against the session branch first.

## Open design questions

These need answers before this can be a feature PRD — capturing here so the brainstorm has structure.

1. **How is the session base branch declared?** Auto on first `/kiln:kiln-build-prd` of a session (heuristic: branch from `main` if currently on `main`, else assume current branch is the session base)? Explicit `/kiln:kiln-session-start <slug>` skill? Implicit when running `/kiln:kiln-next` in a fresh session?
2. **How does build-prd know what the session base is?** Reads from `.kiln/session.config` (gitignored)? From a sentinel branch-name pattern? From the current branch at invocation time?
3. **How do PR merges land on the session branch instead of `main`?** GitHub PR `base` parameter when audit-pr creates the PR (`gh pr create --base session/<slug>-...`). This is mostly mechanical but needs the session base branch to be pushed to origin first.
4. **What about Theme A auto-flip?** If the PR's base is the session branch, does the auto-flip still run on session-branch-merge? Probably yes — the lifecycle event is "PR merged" regardless of target branch. But `/kiln:kiln-roadmap --check`'s merged-PR cross-reference needs to look at session-branch merges too, not just `main` merges.
5. **What about the session-end "promote to main" step?** Is it a single fast-forward / squash-merge? Does it run the full test suite first? Does it produce a single super-PR for the cumulative session diff, or just merge directly?
6. **Conflict with branch-naming hooks?** `kiln-build-prd` Step 5 derives `BRANCH_NAME="build/${FEATURE_SLUG}-$(date +%Y%m%d)"` from the PRD path. The session-base-branch model needs the build-prd branch to be `build/<feature>` off the session base, not off `main`. Sequence matters: session-start FIRST, then build-prd off the session base.
7. **Multi-session concurrency?** Two parallel sessions on different machines branching off `main` at different commits — do they need to coordinate? Probably no for V1 (sessions are scoped to one machine), but worth flagging.
8. **Plugin update mid-session?** If the user updates the kiln plugin mid-session, the cached SKILL.md changes but the session base branch contains the old code. Does this matter for reproducibility? (Probably yes — the session base branch should snapshot the plugin version too.)

## Suggested cheapest version (V0)

Before designing the full feature, prototype manually:
- User runs `git checkout -b session/foo-20260427` from `main`
- Inside the session, runs `/kiln:kiln-build-prd <feature1>` — uses normal `build/` branch off the session
- audit-pr creates PR with `--base session/foo-20260427` instead of `--base main`
- Repeat for `<feature2>`, `<feature3>`
- At session end, run cumulative tests, then `git checkout main && git merge --ff-only session/foo-20260427`

If the manual flow is ergonomic and useful, formalize it. If it's friction, the design questions above need rethinking.

## Addresses

- Tangentially related to `2026-04-27-auto-flip-on-async-merge.md` — both are "what happens after the agent finishes" lifecycle gaps. Keep them as separate items though; this one is broader scope.

## Why this is `kind: research` and not `kind: feature`

The eight open design questions above need answers before any code. That's the textbook "research" shape per `kiln-roadmap` §6.3 — what's the decision this unblocks (yes/no on session-base-branch model), what's the time-box (one session of design + V0 prototype), what's done look like (a feature PRD with acceptance criteria, OR a "rejected — too costly" ADR).
