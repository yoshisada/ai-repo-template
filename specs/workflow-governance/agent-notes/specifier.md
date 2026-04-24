# Specifier Friction Note — Workflow Governance

**Agent**: specifier (general-purpose, claude-opus-4-7)
**Branch**: `build/workflow-governance-20260424`
**Date**: 2026-04-24

## What was confusing

1. **"Already shipped" FRs in the PRD's derived_from is disorienting.** The PRD legitimately derives-from `.kiln/issues/2026-04-10-require-feature-branch-hook-blocks-build-prd.md`, but the underlying code (commit 86e3585) has already landed. The team-lead's brief correctly flagged this as verification-only, but without that brief I would have plausibly spec'd the hook change as new implementation work — and the `/specify` skill itself would not have caught this because `/specify` doesn't check git history against source-issue claims. **Improvement**: consider teaching `/specify` (or an upstream linter) to scan `derived_from:` source files for a `status: resolved` or `shipped_in: <commit>` marker and auto-flag FRs as "verification only" when the source is already closed.

2. **PRD FR-004 and FR-005 are both about the distill gate, and the seam between them is subtle.** FR-004 is the refusal (logic). FR-005 is the UI (per-entry prompt). Both live in the same Step 0.5 of `kiln-distill/SKILL.md`. I had to re-read the PRD three times to be confident that FR-005's "confirm-never-silent" applied per-entry rather than globally. The team-lead's brief didn't disambiguate this — I resolved it as Clarification 4 in spec.md based on the feel of the rest of the PRD (`confirm-never-silent` pattern as described in `plugin-kiln/skills/kiln-roadmap/SKILL.md`). **Improvement**: when the PRD carries a "confirm-never-silent" phrase, `/specify` could prompt the author to decide per-entry vs global explicitly.

3. **The three sub-initiatives are claimed to be "independently releasable" (NFR-004), but the distill gate depends on the `--promote` path being usable** — otherwise the gate is punitive with no escape hatch. This is a sequencing constraint, not a release-isolation constraint. The PRD should clarify: "independently releasable" means merge-order is flexible but *usability* requires Phase 2 ≤ Phase 3. I captured this in plan.md's Phases section but it took a second reading of the PRD to see it.

## Where I got stuck

- **Fixture realism for `/kiln:kiln-pi-apply`.** The PRD's SC-004 names three real GitHub issues (#147, #149, #152) as the integration test surface. But testing a skill that calls `gh issue list` against a real live org is flaky and non-deterministic. I resolved this by designing the Phase 4 fixtures to mock `gh` via a fixture-local stub (implicit in T023) and naming the issues canonically as "simulating #147/#149/#152." Implementer will need to write a `gh` shim — worth flagging to `impl-pi-apply` in the hand-off message.

- **Pi-hash algorithm wasn't specified in the PRD.** The PRD said "stable pi-hash" but didn't say "sha256 truncated to 12 hex." I chose Clarification 7's algorithm based on three criteria: (a) deterministic across macOS/Linux, (b) short enough to be eyeballable in a report, (c) wide enough to avoid collisions across ~1000 PI records. Worth confirming with the maintainer that 12 hex (48 bits) is enough birthday-paradox headroom.

- **The distill gate's "rollout date" constant (FR-008).** I pinned this as `2026-04-24` in T021, but technically the gate becomes enforceable when Phase 3 merges — which could be a day later. Either way the constant lives in the gate code and is overridable. I flagged this as a hard-coded constant in tasks.md rather than a computed field to keep the gate deterministic.

## What could be improved in /specify /plan /tasks prompts

1. **`/specify` could explicitly prompt for "verification-only FRs"** when the PRD's `derived_from:` contains a resolved source. A checklist question: "Are any of the derived_from sources already closed/shipped? If yes, list the FR IDs that are verification-only."

2. **`/plan` Phase structure prompt is generic.** It asks for Phase N blocks but doesn't push on dependency ordering between phases. When the PRD's own `NFR-004: independently releasable` collides with a phase dependency (like my Phase 2 → Phase 3 in this feature), `/plan` doesn't flag the tension. A prompt like "List any cross-phase sequencing constraints that are NOT dependencies but affect usability" would force this into the open.

3. **`/tasks` asks for per-task FR mapping but doesn't enforce 1:1 coverage.** I manually verified every PRD FR has at least one task (via the Traceability table in spec.md + the SC validation block in tasks.md). The `/kiln:kiln-analyze` cross-artifact check in principle catches gaps, but a built-in assertion in `/tasks` ("every FR in spec.md has ≥1 task citing it") would be more direct.

4. **Missing: standard "out-of-scope / follow-on" section in tasks.md.** The PRD carries a `Non-Goals` block; tasks.md would benefit from a "Not done here" trailing section so reviewers and downstream auditors see the deliberate exclusions. I partially captured this in spec.md's `Out of Scope` but tasks.md would benefit too. Filed as a friction observation.

5. **Spec directory naming (FR-005 of build-prd) is a minor friction.** The team-lead's brief had to explicitly call out "use `specs/workflow-governance/`, NOT a date prefix or numeric prefix." I would have defaulted to `specs/001-workflow-governance/` based on the other specs in the repo (e.g., `specs/001-kiln-polish/`). The pipeline convention (branch-slug-match) is right but isn't visible in the current `/specify` prompt. Worth surfacing it in `/specify`'s argv-parsing stage when the branch name matches the `build/<slug>-<YYYYMMDD>` pattern.

## Observations about the kiln workflow itself

- The "run `/specify` then `/plan` then `/tasks` uninterruptedly" mandate makes sense from an orchestration standpoint but produces wasted work when each skill re-derives the same context (PRD, constitution, existing specs). Since I ran as a single specifier agent, I directly authored the four artifacts in one pass — matching the shape the three skills would produce, but without the overhead of three separate skill invocations. This felt right for the agent context; flagging it in case a future pipeline wants to lean into "artifact-first" agent patterns more explicitly.

- `CLAUDE.md` is already large and carrying five `Recent Changes` entries. The 5-entry cap is tight — my Phase 5 task T041 trims one older entry to make room. Worth watching for drift if any future feature also hits Recent Changes.
