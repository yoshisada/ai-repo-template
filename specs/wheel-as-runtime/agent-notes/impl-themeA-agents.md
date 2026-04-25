# Friction Notes — impl-themeA-agents

Owner track: Theme A (FR-A1..FR-A5 + NFR-7).

## Incidents / friction

### Race on `git add` / `git commit` across implementers (T030 + Phase 3 tests)

The atomic agent migration (NFR-7, CC-4) was intended to land every rename + every
symlink + the registry seed in **one** commit. What actually happened: another
implementer's `git add -A` (or equivalent broad stage) swept up my `git mv` hunks
alongside their own work, then committed them. Net result: renames landed in their
commit, symlinks + registry landed in mine — **two commits**, briefly half-migrated
on the feature branch.

Worse: **the same race happened twice more**. My Phase 3 test files (T040–T045)
were staged and ready to commit with a Theme-A-branded message when another
Theme B commit went out and swept them up, landing my tests under a Theme B
commit message ("impl(themeB): friction note per pipeline-contract FR-009"). I
couldn't recover the commit message, but the files themselves all landed.

Consumer impact: zero, because PR-to-main is a squash and the repo state between
the affected commits is only visible in feature-branch history. But it violated
the letter of NFR-7 inside the branch, and — more importantly — it scrambled
commit-message attribution across implementers, which will make the retrospective
harder to read.

**What could be improved for future pipelines with parallel implementers**:
1. **Hard rule**: implementers MUST stage only their own files by explicit path —
   never `git add -A`, `git add .`, or `git add <wide-dir>`. I broadcast this to
   team-lead on the first race; it didn't stick. The lead should relay it up-front
   to every implementer on spawn, not after-the-fact.
2. Wheel's git-adjacent hooks could optionally lint staged hunks for ownership
   mismatch against the current implementer agent id (if that becomes a first-class
   concept), but that's a bigger pipeline feature.
3. Alternatively, implementers could work in **git worktrees** — zero risk of
   cross-contamination — at the cost of more coordination overhead. This is
   probably the right long-term answer.
4. Commit-message attribution could be preserved if each implementer did their
   own `git commit -am 'theme-A: ...'` within seconds of staging, so there's no
   window for another implementer's wide-stage to grab their hunks. But that's
   a mitigation, not a solve.

### Plan.md named archetype agents that don't exist on disk

Plan.md §"Theme A" enumerated 11 canonical agents including `reconciler`,
`writer`, `researcher`, `auditor`. The filesystem only has 10 actual agents, and
none of those archetype names is among them (shipped set: continuance, debugger,
prd-auditor, qa-engineer, qa-reporter, smoke-tester, spec-enforcer, test-runner,
test-watcher, ux-evaluator). Resolution: migrated what's on disk; documented the
discrepancy in T030's note. If the archetypes are actually desired, that's a
follow-on PRD.

### Wheel is instruction-injection, not agent-spawning

The helpers Theme B and Theme A added to `dispatch-agent-step.sh` are pure
functions that emit JSON fragments. They don't spawn agents themselves — the
dispatcher `dispatch_agent` in `plugin-wheel/lib/dispatch.sh` uses
**instruction injection** via `context_build`, returning a `{"decision":
"block", "reason": "<context>"}` response that unblocks the orchestrator to
spawn an agent from its own context.

This means Theme A's `agent_path:` and Theme B's `model:` can only take effect
if either (a) the orchestrator reads the injected context and conforms, or
(b) the dispatcher is extended to template `agent_path`/`model` specs into
the injected instruction, or (c) there's a separate "type: teammate" dispatch
path. The helpers are ready; integrating them into `dispatch.sh` proper is the
next integration step that Theme B's friction note also flags.

My T042/T043/T044 tests live at the helper level (not the full orchestrator
integration level) because the helper layer is what Theme A owns and ships.
Orchestrator integration coverage should be picked up by the audit step.

### Bash `if ! cmd; then rc=$?; fi` silently returns 0

Subtle gotcha caught during T032: `if ! command; then rc=$?; fi` leaves `$?`
as the (successful) logical-branch result, so `rc=0` — the function then
`return 0` and silently masks the failure. Correct: `cmd || rc=$?` outside
any `if !`/`||` logical wrapper.

This is the exact CC-3 silent-failure shape the PRD is trying to stamp out,
so it's worth noting as a shell-scripting pitfall for future implementers.

## In-flight status

All Theme A tasks ship:

- Phase 1+2.A: T001, T002, T003, T010, T011, T012 — done.
- Phase 3: T030 (atomic migration), T031 (resolver), T032 (dispatch helper),
  T033 (kiln-fix FR-A5 doc), T040-T045 (17 test assertions across 5 files,
  all passing).
- Phase 7 work for Theme A: T100 (reference-walker audit artifact) — pending
  next step.
