# Retrospective Notes — Clay Ideation Polish

**Date**: 2026-04-22
**Agent**: retrospective (team member #4)
**Branch**: `build/clay-ideation-polish-20260422`
**PR**: https://github.com/yoshisada/ai-repo-template/pull/138
**Spec**: `specs/clay-ideation-polish/`

## Summary of the pipeline

A 4-agent pipeline (specifier → implementer → auditor → retrospective) took a PRD with 12 FRs / 3 NFRs / 6 SCs across 5 Markdown skills to a merge-ready PR with zero blockers in ~4 hours of elapsed wall time. All 25 tasks marked `[X]`. Verdict PASS. Audit reported zero gaps to document in `blockers.md`.

## Did the single-implementer size feel right?

**Yes.** 17 implementation tasks × 5 phases × 5 files is near the top end of single-implementer size but still cohesive because the five files share a common schema (intent/parent frontmatter + four inlined bash predicates). Splitting by phase would have forced contracts-duplication work per implementer. Splitting by file would have fragmented Phase D, which deliberately touches one file (`clay-create-repo/SKILL.md`) across three related logical branches. The implementer explicitly flagged that they did D1+D2+D3 as one continuous edit — parallelizing that would have introduced merge conflicts.

**Signal to preserve**: when phases touch overlapping sections of the same file, keep them in one implementer.

## Did the 3-decision lock hold?

**Yes, fully.** Specifier's `plan.md` Decisions 1/2/3 (filesystem-only parent detection; missing intent → `marketable`; sub-idea intent prompted fresh) were confirmed by implementer and accepted by auditor without amendment. The team-lead brief pre-flagging these decisions before the specifier even ran is the load-bearing move — specifier's plan.md treated the Decisions section as a confirmation rather than an exploration, saving cycles.

**Signal to preserve**: team-lead pre-flagging of contentious decisions in the specifier brief eliminates mid-pipeline re-negotiation.

## Did the `--intent` no-flag double-standard cause friction?

**No friction in practice.** Implementer explicitly surfaced this in their note ("One flag I want to surface… I did NOT introduce a `--intent=` CLI flag anywhere"). The contrast with `--parent=<slug>` (which DOES exist on `clay-new-product`) was clear because the brief distinguished them: intent is a user-facing classification that should always prompt (NFR-003), while `--parent` is plumbing for programmatic sub-idea creation. One rule with one exception, both spec'd.

**Signal to preserve**: when two similar-looking features diverge (prompt vs flag), the PRD must state the rationale for each side, not just the rule.

## Was stacking on PR #135 a problem?

**Non-event for the pipeline, mild friction for review.** Auditor documented both resolution paths (merge #135 first, OR rebase) in the PR body's `## Dependency` section. The pipeline agents did not need to coordinate with #135's agents — different feature, different spec, different branch. The only cost is that PR #138's GitHub diff includes #135's commits until the base PR lands.

**Signal to preserve**: stacked-branch `## Dependency` section in the PR body is the right pattern. It documents intent without forcing the human to guess whether the overlap is deliberate.

## What worked

1. **Contracts/interfaces.md as MVP.** Both implementer and auditor called this out independently. The four bash helper idioms (`is_parent_product`, `list_sub_ideas`, `read_frontmatter_field`, `--parent` parser) were small enough to inline verbatim in every consumer skill, which made cross-skill drift impossible. Auditor's grep gates (`grep -nE '\-\-intent'`, `grep -nE '\-\-parent'`) were trivial because the predicates are bit-identical everywhere. Evidence: auditor's "Cross-skill consistency checks" section (4 PASSes, all traced to contracts).

2. **Per-phase commit cadence.** Five phase commits (`0885aac`, `5b80c84`, `25f0724`, `ce49447`, `ebfc1ab`) + auditor's Phase F commit (`d6a1d8d`) made audit trivially traceable. Auditor: "I could jump straight to 'does phase-D's commit match FR-010/011?' without rereading the full skill body each time."

3. **Static smoke walkthrough for skill-only PRDs.** `smoke-results.md` as a static code-path walkthrough against fixtures is the correct shape when there is no test runner and agents cannot invoke slash commands live. Auditor: "a sustainable pattern for other skill-only PRDs." Human operator still has the 4 DG gates in the PR body for the pre-merge live check.

4. **3-decision lock in team-lead brief.** Every plan-phase decision was pre-flagged before specifier ran; plan.md confirmed rather than debated them. Zero mid-pipeline amendments.

5. **Per-plugin VERSION propagation in version-bump.sh.** Auditor ran it once (`000.001.003.015` → `000.001.004.000`) and it synced to all 5 `plugin-*/package.json` + 5 `plugin-*/.claude-plugin/plugin.json` + root VERSION. No manual cross-file editing needed.

## What was painful (3-6 items)

1. **Phase D density in `clay-create-repo/SKILL.md`.** After layering 4 sub-idea + shared-repo branches alongside the original flat-product paths, the skill body is "noticeably denser" (implementer's language). Both implementer and auditor flagged this — works correctly, every branch is commented with its governing FR, but the file is harder to scan than before. Follow-on refactor candidate, not a merge blocker.

2. **Unspec'd UX in parent-row display.** Implementer had to interpret 4 UX judgment calls that the PRD did not pin: parent-row Status/Artifacts display in `/clay:clay-list`, "sibling parent" collision semantics, whether parent `about.md` carries intent, and the Phase D density above. All 4 were ruled deferrable by the auditor. Cost: implementer burned cycles on decisions that should have been pre-resolved or left explicitly open.

3. **No live slash-command invocation from inside an agent session.** Four DG gates (SC-001..SC-005) were punted to the human operator because agents cannot execute `/clay:clay-idea`, `/clay:clay-list`, etc. SC-006 (backwards-compat spot-check) also requires human invocation. This is a kiln platform limitation, not a pipeline-design issue — but it means skill-only PRDs always produce a PR with pending human gates.

4. **"Sibling parent" collision option semantics.** `/clay:clay-idea` Step 2.7 offers "sibling parent (different top-level slug)" as one of three resolutions. Spec says "Create a different top-level slug." Implementer interpreted as "start over with a new flat slug"; another valid reading is "create another parent next to the existing one." Auditor accepted the simpler reading. First-user friction risk is low but real — should be user-tested.

5. **Intent default on missing frontmatter is silent.** NFR-002 backwards-compat is preserved by treating missing `intent:` as `marketable` with no log line or warning. If a user expected demand-validation framing in `/clay:clay-idea-research` on an old product, they won't understand why it's the default. Specifier called this an "acceptable for now" trade-off with a future backfill prompt as escape valve.

6. **Orphan test files left over from a previous phase.** Auditor's final commit (`99d6399`, from an earlier pipeline) mentions removing "orphan fix-recording tests" left over after a file deletion. Not a clay-ideation-polish issue directly, but a signal that deletion cleanup lives downstream of the implementer's phase commits. Consider an auditor step "grep for refs to deleted files" to catch these.

## Specific prompt rewrites

### Rewrite 1 — pre-flag UX judgment calls in team-lead brief

**File**: `plugin-kiln/skills/kiln-build-prd/SKILL.md` (team-lead brief scaffolding)

**Current** (implied by this pipeline's brief): decision locks called out for explicit architectural choices (parent-detection rule, missing-intent default, sub-idea schema), but UX display choices (parent-row columns, option-wording for collision prompts) were left for implementer.

**Proposed**: Add a fifth paragraph to the specifier brief template: "Before specifying, scan the PRD for any 'when X shows Y' UX claims. For each, either (a) add a concrete example to spec.md's Scenarios section, or (b) mark it explicitly `UX-DEFER` in plan.md with a one-line justification. Do NOT let the implementer discover unspec'd UX as judgment calls mid-edit."

**Why**: The implementer's note §1–§3 lists 3 unspec'd UX points they had to interpret. The auditor accepted all 3, but they still cost implementation cycles and create "what did we actually ship?" ambiguity for follow-on PRDs.

### Rewrite 2 — auditor orphan-ref grep step

**File**: `plugin-kiln/skills/audit/SKILL.md` (or wherever the auditor checklist lives for skill-only PRDs)

**Current**: Auditor verifies PRD → spec → code → test traceability via grep of FR/NFR/SC IDs.

**Proposed**: Add a "dangling-reference sweep" step: after confirming FR compliance, grep the full repo for references to any files the implementer deleted or renamed in their phase commits. Report hits as blockers unless the implementer's note explicitly calls them out as "intentionally retained historical path."

**Why**: The `99d6399` auditor commit from a parallel pipeline ("Remove orphan fix-recording tests") shows this cleanup consistently falls to the auditor. Codifying it as an explicit step prevents accidental misses.

### Rewrite 3 — stacked-branch documentation pattern

**File**: `plugin-kiln/skills/kiln-build-prd/SKILL.md` (auditor brief scaffolding for stacked PRs)

**Current** (derived from this pipeline): auditor manually decided to add the `## Dependency` section to PR #138's body.

**Proposed**: Add to the auditor brief: "If the feature branch was cut from a non-`main` base (e.g. `git merge-base HEAD main` does NOT match the branch point), the PR body MUST include a `## Dependency` section listing (a) the base PR number, (b) both resolution paths (merge base first / rebase after base merges), and (c) the list of commits that belong specifically to this feature (to disambiguate from the base's commits in the GitHub diff view)."

**Why**: This pipeline proved the pattern works (auditor's note §"stacking observation"). Making it a standing instruction means we get the same quality of dependency disclosure for every stacked PR, not only when the auditor thinks to add it.

### Rewrite 4 — encourage contracts-as-MVP pattern for multi-file skill-only PRDs

**File**: `plugin-kiln/skills/plan/SKILL.md` (or `templates/plan-template.md`)

**Current**: `plan.md` requires contracts/interfaces.md for every plan, which is appropriate when the contracts describe function signatures in code.

**Proposed**: Add an explicit branch for "skill-only" (Markdown-only) PRDs: "If the feature changes only Markdown skill bodies, contracts/interfaces.md MUST include (a) any shared bash predicate ≥3 lines long that appears in more than one skill, verbatim, and (b) any shared frontmatter schema. The implementer is instructed to COPY these verbatim (not paraphrase) into each consumer skill. The auditor runs a bit-identical grep across all consumer skills as a PASS gate."

**Why**: This pipeline's four predicates (`is_parent_product`, `list_sub_ideas`, `read_frontmatter_field`, `--parent` parser) were the single biggest driver of audit clarity. Codifying the pattern means other skill-only PRDs get the same audit tractability for free.

## Preservable patterns

- **Contracts-as-MVP** (Rewrite 4). Small inlineable predicates + bit-identical grep gate.
- **3-decision lock in team-lead brief.** Pre-flag contentious plan-phase decisions so specifier confirms rather than debates.
- **Per-phase commit cadence.** Five phases = five commits, each tagged with its governing FRs, makes auditor's job straight-line.
- **Static smoke walkthrough for skill-only PRDs.** When there's no test runner and no live slash-command invocation, `smoke-results.md` + `SMOKE.md` runbook + PR-body DG gates for human operator is the right shape.
- **Stacked-branch `## Dependency` section in PR body.** Documents base PR, both resolution paths, and feature-specific commit list.
- **Per-plugin VERSION propagation via `scripts/version-bump.sh`.** Auditor runs one command, all 11 VERSION-bearing files agree.

## Open items for follow-on PRDs

1. **Phase D density refactor.** `clay-create-repo/SKILL.md` with 4 sub-idea + shared-repo branches is dense. Candidate for a preamble-helper factoring (implementer's suggestion).
2. **Parent-row UX in `/clay:clay-list`.** Currently renders `—` for parent Status/Artifacts columns. Could show an aggregate status across children (e.g., "1/3 PRD-created"). 1-commit follow-on if users request it.
3. **"Sibling parent" collision prompt semantics.** Is the third option "start over with a new flat slug" or "create another parent next to the existing one"? Worth a quick user test before committing to either.
4. **Backfill prompt for missing `intent:` frontmatter.** NFR-002 keeps legacy flat products silent, but a one-shot `/clay:clay-intent-backfill` skill would close the gap without touching the always-marketable default.

## Evidence trail

- PR: https://github.com/yoshisada/ai-repo-template/pull/138
- Phase commits: `0885aac` `5b80c84` `25f0724` `ce49447` `ebfc1ab` `d6a1d8d`
- Agent notes: `specs/clay-ideation-polish/agent-notes/{specifier,implementer,auditor,retrospective}.md`
- Smoke walkthrough: `specs/clay-ideation-polish/smoke-results.md`
- Version state: `000.001.003.015` → `000.001.004.000`

## Call: apply any prompt-rewrite commit now?

**No.** The four rewrites above touch kiln skill internals that deserve their own focused PRD — lumping them into a clay-ideation-polish retrospective commit would violate the per-feature scope discipline this pipeline just demonstrated. Deferring to `/kiln:kiln-fix` or a dedicated "kiln build-prd brief polish" PRD.
