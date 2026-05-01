# Specifier friction note — wheel-ts-dispatcher-cascade

Date: 2026-05-01
Author: specifier (build-prd team-mode)

## What was confusing / had to be inferred

- **PRD Q1 vs FR-002**: PRD Q1 asks who owns the post-agent cascade. PRD FR-2 implies the dispatcher is responsible. PRD Risks R-3 is more nuanced: dispatchAgent currently advances cursor on output detection, then the next hook fire's `engineHandleHook` calls dispatchStep on the new cursor. I resolved this in spec §7 / §6 musts by saying dispatchAgent stays unchanged and engineHandleHook routes the next hook fire — the cascade tail then runs from there. This matches the existing TS code shape (dispatchAgent already does the cursor advance) and minimizes surface area. If team-lead wanted dispatchAgent to inline-cascade after marking done, that should be a separate FR and was NOT clearly written in the PRD.
- **PRD's FR-2 "advance cursor first" vs the dispatcher's existing "set status done first" pattern**: existing dispatchCommand sets step status `done` THEN returns. The cascade tail needs to advance cursor BEFORE recursing (idempotency). I encoded this as cascadeNext doing the advance, called AFTER status=done. That matches the PRD's intent (idempotent retry) but the PRD's literal wording in FR-2 (steps 1→2→3→4→5→6) reads as if cursor advance is step 6, AFTER everything else. I chose the operationally-safe ordering (status done → cursor advance + log → recurse / return), and documented it in contracts §4 and spec FR-008. Worth double-checking with team-lead if a stricter literal reading was intended.
- **`engineHandleHook`'s post-dispatch cursor advance + cascade interaction**: the engine ALSO advances cursor +1 after each dispatch when step is done/failed (engine.ts line 144). With the cascade in place, the dispatcher already advanced the cursor as far as it can go (via cascadeNext). The engine's post-dispatch advance becomes a safe no-op (cursor is already past), or in some cases a one-step extra advance. I did NOT remove the engine's advance — it's still needed for non-cascading paths (e.g., dispatchAgent's "output file detected" return → cursor advance happens in dispatchAgent OR in engine; engine's advance covers the case where dispatchAgent doesn't). The plan flags this as R-engine-extract.
- **`maybeArchiveTerminalWorkflow` is module-scoped (`STATE_FILE`)** — the engine.ts current shape uses a module-scoped variable. To call this from `handleActivation` after the cascade returns, I had to introduce `maybeArchiveAfterActivation(stateFile)` as a parameter-taking sibling. The PRD did not call this out; I inferred it from reading engine.ts. Plan task T-050 spells out the extract.

## SC-2/SC-4 baseline reconciliation status

- **SC-2** (count-to-100 < 5 s wall-clock): RECONCILABLE. Baseline = "60 s timeout, workflow never completes." Recorded in `research.md §Baseline`. Trivial reconciliation; no friction.
- **SC-4** (dispatchCommand source ≤ 30 lines growth): RECONCILABLE. Captured baseline = 46 lines via `awk '/^async function dispatchCommand/,/^}/' plugin-wheel/src/lib/dispatch.ts | wc -l`. Soft cap: ≤ 76 lines post-cascade. Recorded in `research.md §Baseline`. PRD explicitly accepts overrun with documented justification. Trivial reconciliation; no friction.

Both SCs reconciled against `research.md §Baseline`.

## Prompt-clarity issues for team-lead (helpful for next pipeline)

1. **Where does the cascade trigger live for the post-agent path?** PRD Q1 + FR-2 + R-3 each say slightly different things. The brief should pre-resolve this rather than leave it as an open question — it's a small but central design decision. I picked the lowest-surface path (dispatchAgent unchanged; engine routes next hook fire); if team-lead disagrees, the implementer needs explicit redirection.

2. **`maybeArchiveTerminalWorkflow` extraction is implicit, not stated.** PRD assumes `archiveWorkflow` (FR-009 of wait-all redesign) "is in place" but doesn't note that calling its trigger from `handleActivation` requires a refactor. The brief should flag this as a known coupling — implementer will hit it on Phase 5.

3. **"30 lines" is on the function, not the file.** SC-004 wording ("dispatchCommand source size grows by ≤30 lines") is unambiguous in the PRD body but easy to misread as "the file grows by ≤30 lines." Brief should clarify if the intent ever shifts to file-level.

4. **No mention of test-coverage gate for the cascade-specific lines.** Constitution Article II says ≥ 80% for new/changed code. The PRD mentions test fixtures (FR-10) but doesn't state a coverage target. I added it to `tasks.md T-080` and spec §8 — but the brief should explicitly call out the constitutional gate so implementers don't skip the coverage step.

5. **Composition test fixture (FR-10 #7) is non-trivial.** The PRD lists it casually but it requires both parent and child workflow fixtures plus an assertion that parent's cursor advances after child archive. That's a multi-hour test on its own. Could be worth flagging as a higher-risk task in the brief.

6. **Cache deploy command is documented in PRD Assumptions but not in tasks.md sample.** I added a `rm -rf ... && cp -r ...` pattern in T-091 to avoid stale-file issues. Brief could pre-canonicalize this command.

## Pipeline-handoff signal

Spec.md, plan.md, contracts/interfaces.md, research.md, tasks.md all written and consistent. Constitution Articles I, II, VII, VIII addressed in spec §8 acceptance gate and tasks.md T-100..T-102. Branch + spec dir name verified per FR-005 of the brief: `specs/wheel-ts-dispatcher-cascade/` (no date prefix, no numeric prefix).

Ready to commit and hand off to impl-wheel.
