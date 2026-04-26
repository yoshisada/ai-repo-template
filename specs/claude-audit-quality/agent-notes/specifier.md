# Agent friction note — specifier

**Confirmation (per team-lead Step 1.5 instruction)**: thresholds reconciled against `specs/claude-audit-quality/research.md` §Baseline.

## What was confusing

1. **NFR-001 scope wasn't pinned in the PRD.** The PRD's NFR-001 reads "audit duration MUST NOT increase by more than 30%" without saying which portion of `/kiln:kiln-claude-audit` "duration" refers to. The skill is a Claude Code Skill (model-driven) with both bash-side script work and editorial-LLM passes. Researcher-baseline picked the bash-side scope (the only thing measurable from a sub-agent shell) and documented why. I propagated that choice into spec.md NFR-001 with an explicit carve-out, and added OQ-1 (soft "near-cap" warning) and OQ-2 (editorial-pass tax as follow-on) so the auditor can re-run the gate without ambiguity.

2. **NFR-003 carve-out wasn't in the PRD.** The PRD's NFR-003 says "byte-identical Signal Summary + Proposed Diff" but doesn't acknowledge that this PR's NEW substance rules will produce DIFFERENT bytes vs the pre-PR baseline by definition (the rules didn't exist before). Without an explicit carve-out, the auditor would either (a) wrong-flag the substance-rules' new content as an NFR-003 violation, or (b) silently accept any byte change as "expected post-PR." I added a within-scope idempotence carve-out per the team-lead's Step 1.5 instruction (lifted from the PI applied in commit `3ac305c`): NFR-003 binds to two same-scope runs on unchanged inputs, NOT to cross-PR comparison. Spec.md NFR-003 documents the auditor's verification recipe.

3. **`external` is a section, not a `signal_type` value.** The PRD's FR-010 says output ordering is "substance → mechanical → external best-practices," which reads like `external` is being added as a `signal_type`. Researcher-baseline confirmed it is in fact a separate-section concept (`## External best-practices deltas`), not a rubric `signal_type` value. I reconciled this in NFR-004 (existing rules' schema is preserved; `external` stays a section). The contracts/interfaces.md §1 "schema changes this PR introduces" lists `signal_type` enum gain (`substance` only) — no `external`.

4. **`scaffold-undertaught` (FR-009) determinism question.** "Load-bearing concepts" is editorial. Without enumeration, two implementers would derive different sets. I added OQ-6 reconciliation in spec.md: enumerate three concept families — (a) thesis (vision pillar), (b) loop (input → consumer → output), (c) architectural pointer (e.g. "scaffold deploys via X"). The rule fires per missing family; proposed diff inserts one paragraph per missing family.

5. **`recent-changes-anti-pattern` (FR-016) byte-identity vs apply-time usefulness.** OQ-1 of the PRD asks whether the proposed-diff body should name the current phase explicitly (`.kiln/roadmap/phases/10-self-optimization.md`) or use a generic placeholder. Generic preserves byte-identity across re-runs (NFR-003 anchor); current-phase is more useful at apply time. Reconciled to generic in the diff body, with a one-line companion comment in Notes naming the current phase. Notes is not part of the byte-identity contract, so this preserves NFR-003 while giving apply-time information.

## What guidance was missing

- **No worked example of how to pin scope of a non-shell-runnable measurement to an NFR.** The PRD's NFR-001 / NFR-003 didn't tell the specifier (me) or the researcher what "duration" or "byte-identical" binds to. The team-lead's Step 1.5 instruction is the right escape hatch, but the next PRD that has a Skill-side measurement will hit the same gap. PI proposal below addresses this.

- **No example of a within-scope vs cross-PR distinction in NFR-003 wording.** The team-lead lifted the carve-out pattern from commit `3ac305c` (kiln-build-prd SKILL.md Step 1.5), which is the right place — but the PRD-distillation step that emits the PRD doesn't yet know to carve out byte-identity for NEW rules. Future PRDs introducing new content rules will need the same carve-out.

- **No template for the interface-contracts file specific to "rubric rule additions + skill body section reorder."** I had to derive the §-structure of `contracts/interfaces.md` by looking at the prior `claude-md-audit-reframe` PR. Useful starting point but every audit-quality PR is going to extend the rubric in a similar way; a shared `templates/contracts-rubric-extension.md` would help.

- **No PRD-level guidance on how to handle the retro insight-score's "agent rates itself" reliability concern.** The PRD lists this under R-4 with "if drift, escalate to a separate auditor agent — out of scope for this PRD." That's correct framing but the spec needs to explicitly enforce honest self-rating in the prompt (see contracts §8 "honest self-rating is the contract; if the retro is a status report, the agent emits 1, not 3 to game the threshold"). Without that prompt-level enforcement, the rating is decorative.

## PI proposals (bold-inline format)

**File: `plugin-kiln/skills/kiln-distill/SKILL.md` (PRD frontmatter authoring step)** — **Current**: PRDs emitted by `/kiln:kiln-distill` state NFRs without binding their measurement scope (e.g. "duration MUST NOT increase by more than X%" without naming which bash-side / model-side / wall-clock scope). **Proposed**: when the distill step emits an NFR with a numeric threshold, the prompt asks the model — for each NFR — "what's the minimum verifiable scope this binds to? Is it shell-measurable? Is it cross-PR comparable?" and emits a `scope:` sub-bullet under each NFR pinning the answer. — **Why**: this PRD's NFR-001 + NFR-003 needed the specifier (me) to derive scope from first principles in Step 1.5. Future PRDs with similar NFRs will hit the same gap.

**File: `plugin-kiln/skills/kiln-build-prd/SKILL.md` (Step 1.5 — research → spec reconciliation)** — **Current**: Step 1.5 documents the byte-identity carve-out lesson from PRs introducing new content rules ("byte-identity asserts only on the no-X paths"). **Proposed**: extend Step 1.5 with a generalized check — "for any NFR asserting byte-identity / output stability across runs, identify whether THIS PR's new substance changes the post-run output by definition; if yes, document the carve-out explicitly in spec.md and add an Open Questions entry naming the calibration." — **Why**: this PR needed exactly this carve-out for NFR-003. The current Step 1.5 captures the lesson but as a one-off; generalizing prevents the next PRD from re-deriving it.

**File: `plugin-kiln/templates/spec-template.md` (or wherever the spec scaffold lives)** — **Current**: spec template has `## Open Questions` as a free-form section. **Proposed**: add a sub-template "## Open Questions — Reconciled vs Open" with an explicit `Reconciled (per Step 1.5):` group at the top and `Open (deferred to retrospective):` group at the bottom. — **Why**: this spec ended up with both kinds (OQ-1, OQ-3, OQ-4, OQ-5, OQ-6 reconciled inline; OQ-2 deferred to retro). A reader scanning the spec needs to see at-a-glance which OQs are settled and which are still open. The current free-form section makes this require careful reading.

**File: `plugin-kiln/skills/kiln-claude-audit/SKILL.md` (output shape)** — **Current**: per researcher-baseline's note 2, the skill emits a `## Smoke-test verification` trailer on smoke-scope runs that isn't part of the contracted output shape — this blurs the NFR-003 byte-identity comparison. **Proposed**: either (a) drop the smoke-trailer entirely (smoke is a caller decision, not a Skill output mode), or (b) gate it behind an explicit `--smoke` flag and document the flag in the SKILL header. — **Why**: NFR-003 within-scope assertion gets cleaner if the Skill has one shape, not two. This is queued as OQ-3 / OQ-3-followup for the retro, not in this PR's scope, but it's worth filing as a separate kiln-self-improvement issue.

## Coordination metadata

- Task: #2
- Started: 2026-04-25 (after researcher-baseline DM "baseline ready")
- Owner: specifier
- Blocks: tasks #3 (impl-claude-audit), #4 (impl-tests-and-retro), #5 (auditor)
- Output artifacts: `specs/claude-audit-quality/spec.md`, `specs/claude-audit-quality/plan.md`, `specs/claude-audit-quality/contracts/interfaces.md`, `specs/claude-audit-quality/tasks.md`, this note.
- **Thresholds reconciled against `specs/claude-audit-quality/research.md` §Baseline** — required per team-lead Step 1.5.
