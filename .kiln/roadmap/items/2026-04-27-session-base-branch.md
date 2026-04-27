---
id: 2026-04-27-session-base-branch
title: "Session base-branch model — agent runs branch off a 'session base', not main; merges land on the session branch first"
kind: research
date: 2026-04-27
status: open
phase: 90-queued
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

---

## Brainstorm resolution (2026-04-27)

The original 8 open design questions resolved through a focused brainstorm session. The shape is now PRD-ready.

### Mode is the architectural primitive (not just session-base)

The session-base-branch model is one behaviour inside a broader **mode** primitive that distinguishes user-driven from AI-driven sessions:

- `mode: user-driven` (default) — no auto-session-start; ship-class commands behave as today; `/kiln:kiln-session-start` available as opt-in
- `mode: autonomous` — session-start fires automatically on first ship-class command; ship cycles target the session base; punctuated by review gates; ends only when user runs `/kiln:kiln-session-end`

Mode lives in `.kiln/kiln.state` (gitignored). Detection: state-file value if set; TTY heuristic + `KILN_MODE` env var as fallback. Wheel-runtime context is intentionally NOT a signal — keeps mode portable across consumer projects regardless of wheel adoption.

### Review gate — mid-session human checkpoint

Distinct from per-PR audit. The gate is a *pause* mechanism inside a session, not a *terminator*. Loop: agent ships N cycles → gate fires → human evaluates + provides input (captures, fixes, feedback) → user runs `/kiln:kiln-resume` → gate clears, counters reset → agent picks up new captures and continues → eventually user runs `/kiln:kiln-session-end` to promote.

While `awaiting: true`, all ship-class commands refuse to run (pre-flight check on `kiln.state.review_gate.awaiting`).

State schema:

```yaml
mode: autonomous
session:
  slug: foo-bar
  base_branch: session/foo-bar-20260427
  started_at: <iso>
  plugin_version: 000.001.009.519
review_gate:
  awaiting: false
  set_at: null
  reason: null              # "cycle-threshold" | "prd-flag" | "queue-empty" | "manual"
  cycles_since_clear: 0
  cycle_threshold: 5
```

### Cycle definition — one merge to session base

Cycle counter increments on every merge to the session base, regardless of which skill produced it (`build-prd`, `merge-pr`, hotfix). Countable via `gh pr list --base session/<slug> --state merged --search "merged:>=<set_at>"`. Anything finer (tasks, commits) over-fires; anything coarser (PRDs) requires kiln to track PRD-shipped state across skill boundaries.

### V1 trigger set

| # | Trigger | Default | Notes |
|---|---|---|---|
| T1 | Cycle count — N merges to session base since last clear | 5, configurable | within-session count fallback |
| T3 | Explicit PRD flag — `requires_human_review: true` in PRD frontmatter | off, opt-in | user-set at distill time only; never auto-derived from blast_radius or any other signal |
| T-empty | Queue empty — no captures, no open PRDs, no roadmap items without PRD | always-on | fires gate with `reason: queue-empty`; user provides input or runs session-end |

Explicitly NOT triggering the gate: blast_radius, session-end, post-PR-audit completeness. Auto-triggering on blast_radius defeats the value prop ("I built this so AI can ship cross-cutting fixes"); session-end is a separate user-initiated event; per-PR audit is its own gate at finer grain.

### Resume flow (`/kiln:kiln-resume`)

After clearing the gate, the agent walks this in order:

1. New captures since `set_at` (in `.kiln/issues/`, `--feedback`, `--roadmap`)? → run `/kiln:kiln-distill` on them → ship resulting PRD via build-prd
2. Else open PRDs in `docs/features/` queue? → pick next, run build-prd
3. Else open roadmap items with no PRD? → bundle into distill candidate set, distill, ship
4. Else (truly empty) → fire gate with `reason: queue-empty`; halt awaiting human input

V2 amends step 4 with a vision-deliberation sub-agent that reasons over vision + recent activity and proposes new items as the gate's payload (see V2 backlog #2).

### Session-end (`/kiln:kiln-session-end`) — user-initiated only

Never auto-fires. Workflow:

1. Run cumulative tests against session base
2. Show diff vs main
3. Prompt: promote (ff/squash-merge to main) or stay (keep session branch around for further review)
4. On promote: merge to main, retire session branch, reset `kiln.state.session` block

### Build-prd integration (S1 → B1, B2)

- Step 5 (branch creation) — branch from `session.base_branch` if `kiln.state.session` set; else current behaviour. Back-compat preserved.
- Step 7 (audit-pr / `gh pr create`) — `--base <session-branch>` if in session; else default. Read base from state file.
- Step 4b.5 auto-flip — fires on merge regardless of target; works as-is. Diagnostic line should record target branch for traceability.

### Hooks

- `require-feature-branch.sh` — add `session/` to allowlist so capture skills can run from session base without bouncing.
- `require-spec.sh`, `block-env-commit.sh`, `version-increment.sh` — no changes.

### V1 scope (locked)

1. Mode primitive in `.kiln/kiln.state` (gitignored)
2. Session lifecycle: auto-start in autonomous mode → ship cycles → review gates → user-initiated `/kiln:kiln-session-end` → promote to main
3. Review gate with T1 + T3 + T-empty
4. `/kiln:kiln-resume` 4-step flow
5. `/kiln:kiln-session-end`
6. Pre-flight gate check on all ship-class commands
7. `/kiln:kiln-next` mode-aware + gate-aware
8. `require-feature-branch.sh` allowlist update for `session/`

### V2 backlog (separate items to spawn)

1. **T-AI evaluator** — sub-agent fires gate on quality/uncertainty signals (audit compliance, smoke depth, retro insight_score, decision-divergence-from-precedent). Reads precedent corpus generated by V1's gate history.
2. **Vision-deliberation sub-agent** — extends `/kiln:kiln-next` or `/kiln:kiln-distill`. Reads vision + recent activity + current state, returns proposed items with reasoning at `queue-empty`. Role-as-noun naming convention (`vision-deliberator` or `next-action-proposer`). Sub-agent returns via SendMessage; calling skill renders to user.
3. **Plugin-version snapshot at session-start** — answers original Q8. Records plugin version at session-start; warns at session-end if changed.
4. **Multi-session concurrency** — answers original Q7. V1 assumes single-machine sessions with distinct slugs; V2 handles parallel sessions.

---

## Why this is `kind: research` and not `kind: feature`

The research output IS the resolution above. The V1 *implementation* should be spawned as a separate `kind: feature` item via `/kiln:kiln-distill --addresses 2026-04-27-session-base-branch` — that PRD is sizeable (new state file, two new skills, build-prd integration, hook update) and deserves its own focused distill session, not stacked on this brainstorm's tail.

## Addresses

- Tangentially related to `2026-04-27-auto-flip-on-async-merge.md` — both are "what happens after the agent finishes" lifecycle gaps. The merge-pr skill being distilled there will need to learn the session-base target when V1 of this lands. Keep them as separate items though; this one is broader scope.
