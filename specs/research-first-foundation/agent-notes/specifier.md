# Specifier friction note — research-first-foundation

**Teammate**: specifier (task #1)
**Branch**: `build/research-first-foundation-20260425`
**Date**: 2026-04-25

## Status

Spec/plan/tasks/contracts authored and committed (`6cc7ea6`). Thresholds reconciled against `research.md §baseline` per the orchestrator's §1.5 protocol — SC-S-001 widened from 60s → 240s, NFR-S-001 widened from ±2 tokens → ±10 tokens absolute per `usage` field. **Thresholds reconciled against research.md §baseline.**

## What worked

- The team-lead's `## CHAINING REQUIREMENT` section was excellent — it preempted the kiln slash-commands' habit of saying "next: run /plan" and then stopping. Without that override I would have stalled three times.
- The team-lead's `## BASELINE THRESHOLD RECONCILIATION` block was specific enough to act on without ambiguity. The "what to do if PRD literal is unreachable" branch (rewrite + flag) was the right script.
- `wheel-test-runner-extraction/spec.md`'s shape was a good template to follow — particularly the `## Resolution of PRD Open Questions` and `## Reconciliation Against Researcher-Baseline` patterns.
- `research.md §baseline` was already commit-shaped before I checked — researcher-baseline ran ahead of my schedule. The "Aggregation summary for the specifier" table at the bottom of research.md was a gift; I just had to accept the recommendations.
- Constitution Article VII's `contracts/interfaces.md` requirement forced me to nail down exit codes / stdin shapes / report structure before tasks generation — that paid off in the §11 canonical summary table.

## What was confusing

- The kiln:specify skill's instruction set assumes you'll run `.specify/scripts/bash/create-new-feature.sh` with `--short-name` to scaffold a numeric-prefix dir. The team-lead OVERRODE that with "MUST be `specs/research-first-foundation/` — no numeric prefix." The skill doesn't have a "skip the create-new-feature.sh script and use a pre-existing dir name" branch. I authored the artifacts manually instead of running the script, which works but bypasses the template-copy logic. **PI-N suggestion below**.
- The kiln:plan skill similarly assumed `setup-plan.sh` would derive paths from branch name + `.specify/init-options.json`. With a non-standard spec dir slug, this is ambiguous. I bypassed the script.
- The kiln:tasks skill's instruction set assumes `check-prerequisites.sh --json` resolves the FEATURE_DIR. Same workaround.
- The "Skip step 1-4 and jump to step 6" branch in kiln:specify (when an existing spec is found) is for re-runs; my case was a fresh spec in a non-standard dir, which the skill doesn't quite cover.
- I had no easy way to verify the recalibrated 240 s budget against the actual harness fixed-cost ahead of T027 (the smoke task). This is implicitly an "implementer surprise" risk — if the lightest-profile 6× projection actually lands at 250 s on a slower CI runner, T014's ≤ 240 s assertion will fire. Researcher-baseline acknowledged this as ~30% headroom; I'm trusting the math but a CI matrix with arm64 + x86 would test it. Not a v1 concern.

## Handoff frictions

- The `researcher-baseline` teammate was running in parallel and committed `research.md §baseline` ahead of my reconciliation step. I checked the orchestrator's BASELINE THRESHOLD RECONCILIATION block twice to confirm the right ordering (it's: spec.md drafted → check baseline → reconcile thresholds → commit reconciled spec → run /tasks). That ordering is correct as written.
- The reconciled SC-S-001 budget (240 s) is documented in three places: spec.md, plan.md, contracts/interfaces.md §6. I had to update all three. The orchestrator's protocol says "Re-derive SC-001 + NFR-001 thresholds from live measurements" — it might be cleaner if there were a single canonical location and the others linked.

## Suggestions for next pipeline (PI-N format)

### PI-N-001 — kiln:specify needs a "use existing spec dir" branch

**File**: `plugin-kiln/skills/specify/SKILL.md`
**Current**: Step 0 says "if FEATURE_DIR exists AND `spec.md` exists inside it, skip steps 1-4." It does NOT cover "FEATURE_DIR exists but spec.md does NOT exist (caller pre-created the dir to enforce a non-numeric slug)."
**Proposed**: Add a Step 0.5 — if a non-empty `--spec-dir <abs-path>` arg is passed (or detected via env `SPECIFY_SPEC_DIR`), skip the `create-new-feature.sh` invocation entirely and write spec.md directly into that path. The team-lead's "MUST be `specs/<slug>/` — no numeric prefix" pattern is recurring; future pipelines will need this exit.
**Why**: every team-mode pipeline run hits this friction. The current workaround is "manually author spec.md and skip the script," which works but bypasses checklist generation + bookkeeping.

### PI-N-002 — kiln:plan + kiln:tasks similar issue

**File**: `plugin-kiln/skills/plan/SKILL.md` + `plugin-kiln/skills/tasks/SKILL.md`
**Current**: Both run `.specify/scripts/bash/(setup-plan|check-prerequisites).sh --json` to resolve paths. The scripts derive paths from branch name + `.specify/init-options.json`.
**Proposed**: Same fix as PI-N-001 — accept a `--feature-dir <abs-path>` override that bypasses path derivation entirely.
**Why**: same as above; pipelines with non-standard spec dirs need a clean opt-out.

### PI-N-003 — orchestrator BASELINE THRESHOLD RECONCILIATION should explicitly say "update plan.md + contracts/interfaces.md too"

**File**: `~/.claude/teams/<team-name>/config.json` (or wherever the team-lead's spec-instructions template lives)
**Current**: "Re-derive SC-001 + NFR-001 thresholds from live measurements. If a PRD literal is unreachable, rewrite the threshold (or add tolerance band) in spec.md and flag the recalibration in spec.md `## Open Questions`."
**Proposed**: Append "Update SAME thresholds in plan.md §Technical Context (Performance Goals, Constraints) and contracts/interfaces.md §6 Performance budgets to keep the three artifacts mutually consistent."
**Why**: I almost forgot to update plan.md and contracts/interfaces.md. The team-lead's instructions only mention spec.md.

### PI-N-004 — researcher-baseline `## Aggregation summary for the specifier` table is gold; canonicalize it

**File**: researcher agent template (likely `plugin-kiln/agents/researcher-baseline.md` if it exists, or the team-lead's role-instance instructions)
**Current**: Researcher emitted an `## Aggregation summary` table on its own initiative (the PRD doesn't mandate it).
**Proposed**: Make it a required section. Headers: `Item | Verdict | Recommended change`. This made my reconciliation 80% faster — I just had to accept or argue with the recommendations rather than re-deriving them.
**Why**: high-leverage. Specifier reconciliation is the bottleneck; aggregating directives saves a lot of re-reading.

### PI-N-005 — provide a one-line "thresholds reconciled against research.md §baseline" canonical phrase

**File**: orchestrator instructions
**Current**: "Note explicitly in your friction note: 'thresholds reconciled against research.md §baseline'"
**Proposed**: ✅ already done; this note IS that canonical phrase. Consider extending the convention to mark spec.md FRs/NFRs/SCs that were reconciled — e.g. "(RECONCILED 2026-04-25)" tag suffix. I did this manually.

## Unresolved

- T014 (`research-runner-pass-path/run.sh`) asserts wall-clock ≤ 240 s. If a slow CI runner busts this, the implementer will need a `--budget-seconds` flag on the assertion (or a per-runner override). Documented in plan.md §Risks but not yet a blocker.
- `bashcov` availability in CI (NFR-S-010 fallback) — plan §Decision 5 punts to "fixture suite as coverage proof." First implementation pipeline should re-evaluate if `bashcov` is easy to add.
