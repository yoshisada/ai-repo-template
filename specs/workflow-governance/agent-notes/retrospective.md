# Retrospective Friction Note — workflow-governance

**Agent**: retrospective
**Date**: 2026-04-24
**Branch**: `build/workflow-governance-20260424`
**Issue**: https://github.com/yoshisada/ai-repo-template/issues/160
**PR**: https://github.com/yoshisada/ai-repo-template/pull/159

## What was confusing

1. **The git-add-all sweep (commit `a340652`) took real archaeology to understand.** The commit subject said "complementary /plan enum-check follow-on" but `git show --stat` revealed 15 pi-apply files. Without the team-lead brief's explicit callout, this would have looked like an attribution bug rather than a multi-agent concurrency hazard. The pipeline has no automated detection — I had to cross-reference impl-governance's friction note + impl-pi-apply's friction note + `git show` payloads to confirm the mechanism (shared index, default `git commit` swept staged-but-uncommitted files). **Takeaway**: a pipeline that runs N parallel implementers against a shared working tree is a concurrency system and deserves the same rigor as one — locks, explicit paths, or `--only` flags.

2. **auditor-2's friction note was the most useful input.** It was the only friction note with a concrete prompt-design proposal (pick one: `/audit` OR bespoke procedure, not both). Impl-governance and impl-pi-apply's notes surfaced follow-ons but auditor-2's directly explained a stall. When future pipelines spawn replacement agents, the replacement's brief should explicitly ask "why might the original have frozen?" — the replacement is in the best position to diagnose.

## Where I got stuck

- **No direct access to the original auditor's output or friction note.** The auditor-2 replacement wrote the only auditor friction note on file. The original auditor's 8-hour silent period left no artifact — so the root-cause analysis for the stall is inferential (auditor-2's hypothesis about `/audit` + bespoke procedure collision). A future pipeline improvement: replacement agents should inherit the stalled agent's partial transcript if the runtime can serialize it, or at minimum the team-lead should capture what the stalled agent's last heartbeat looked like before replacement.

- **Counting "what went well" is harder than counting "what went wrong."** The pipeline shipped 100% PRD compliance across 13 FRs / 5 NFRs / 6 SCs with one 8-hour stall and one attribution bug — strong objective success. But retrospectives tend to over-weight incidents over baseline success. I tried to balance by leading the issue body with a "What worked well" section citing concrete mechanisms (contract-first parallelization, fixtures-as-contracts, team-lead brief prescriptiveness) so those patterns get reinforced, not just the defects.

## What could be improved in the retrospective process

1. **Retro agents should be able to read prior retros.** This pipeline had no access to historical retro issues, so "has this happened before?" questions (e.g., the contract enum drift bit the pipeline a second time per impl-governance's note) had to be answered from friction notes alone. A `/kiln:kiln-pi-apply` pass over `label:retrospective` issues (FR-009..FR-013, which *this* PRD just shipped) is the right tool going forward — PI-1 on the next retro pass should be "apply Rewrites 1–9 from #160." Meta-loop is now closed.

2. **State-snapshot briefings for replacement agents are load-bearing.** auditor-2 cites the team-lead's pre-computed snapshot as the reason it could complete in one turn. This should be a first-class output of the team-lead role, not a heroic effort per-incident. Proposed in issue #160 "Other proposed changes."

3. **Prompt-rewrite format worked well.** The File/Current/Proposed/Why blocks in the retro issue are greppable — future `/kiln:kiln-pi-apply` passes can mechanically extract Current/Proposed pairs. Worth standardizing as the retrospective template.

## Concrete follow-ons (from issue #160)

- **HIGH**: Rewrite 1 — ban `git add -A` in implementer prompts; Rewrite 2 — shrink auditor stall window to 5 min; Rewrite 3 — pick `/audit` OR bespoke procedure, not both.
- **MEDIUM**: Rewrite 4 — already-shipped check in `/kiln:kiln-distill`; Rewrite 5 — verification-only FR detection in `/specify`; Rewrite 7 — `/plan` enum cross-check against validators; Rewrite 9 — `confirm-never-silent` scope disambiguation in `/specify`.
- **LOW**: Rewrite 6 — spec-dir naming rule visible in `/specify` prompt; Rewrite 8 — PRD template prompts for hash-algorithm names when dedup/pi scope present.
- **Other**: `harness-type: static` substrate; FR-013 fixture for `/kiln:kiln-next`; `validate-item-frontmatter.sh --target-basename` flag; CLAUDE.md cap review; Clarifications as first-class spec section.

## What went well with the retrospective itself

- All four prior agents wrote friction notes before completing their tasks (the safety-net gate held). Zero polling of live agents required.
- Task gate passed cleanly — tasks #1–#4 all completed before retrospective claimed task #5.
- The concrete-commit + concrete-line-number discipline (per team-lead brief) made every finding auditable in under 30 seconds — no vague claims survived.

## Status at task completion

- Retrospective issue filed: https://github.com/yoshisada/ai-repo-template/issues/160 (label: `build-prd`)
- 9 prompt-rewrite proposals, each grounded in a specific File/Current/Proposed/Why block quoting exact text from source files
- 7 "Other proposed changes" for skill/template/team-structure follow-ons
- Friction note committed; task #5 will be marked complete; team-lead notified
- Pipeline complete.
