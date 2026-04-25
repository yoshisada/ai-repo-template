# Agent Friction Notes: audit-pr

**Feature**: agent-prompt-composition (combined audit + smoke + PR creation)
**Date**: 2026-04-25
**Pipeline**: kiln-prompt-composition team
**PR**: https://github.com/yoshisada/ai-repo-template/pull/173

## What Was Confusing

- **Step 4b ordering relative to PR creation.** The audit-pr prompt instructs me to (1) reconcile blockers.md, (2) run smoke, (3) run Step 4b lifecycle archival with a PR back-ref, (4) create the PR. But Step 4b *needs* the PR URL for the back-ref, which only exists after Step 4 fires. I resolved by creating the PR first (without the archival commit folded in), then doing Step 4b as a second commit on the same branch — the squash-merge collapses both into one logical PR. Worth a one-line note in the audit-pr prompt template: "Step 4b runs *after* PR creation; the back-ref commit is pushed to the same branch."
- **Pre-existing untracked files in the working tree.** I found `scripts/compile-agents.sh`, `.claude/settings.json`, and a `.kiln/issues/2026-04-25-pipeline-bypass-loophole-plugin-source-repos.md` untracked. They originated from a parallel `/kiln:kiln-report-issue` background workflow (visible in `.wheel/outputs/create-issue-result.md`), NOT from either implementer's commits. I confirmed they're out-of-scope (no implementer commit references them) and excluded them from the PR. The 12-file "uncommitted" warning from `gh pr create` is expected and benign for this run, but a noisy auditor could mistake those for in-scope drift. Worth filtering ambient `.wheel/`, `.kiln/logs/`, `.kiln/roadmap/phases/` deltas in a future audit-pr template.

## Where I Got Stuck

- **NFR-8 disjoint partition false alarm.** My first `comm -12` over file lists touched by Theme A vs Theme B commits showed 11 "overlapping" files. Closer inspection revealed all 11 were either (a) auto-version-bump artifacts driven by the `version-increment.sh` PreToolUse hook (VERSION + every plugin's package.json + plugin.json) or (b) `specs/agent-prompt-composition/tasks.md` where each track marks its own `[X]` checkboxes. After excluding those, substantive overlap = ∅. Conclusion: NFR-8 is satisfied, but the verification path needs a documented exclusion list. Filing as friction because the next audit-pr will hit the same noise.

## What Could Be Improved

- **NFR-8 verification helper script.** A `plugin-kiln/scripts/audit/verify-disjoint-partition.sh` that takes two commit ranges and emits a clean overlap diff (excluding hook-driven version metadata + tasks.md per-track flips) would compress the (c) checklist item from 5 minutes of manual `comm` plumbing to one shell call. Add to follow-on backlog.
- **PR-body length guidance.** The audit-pr prompt says "PR body MUST include: SC-1..SC-8 verdicts, all 6 (a)-(f) checklist results, links to fixture verdicts, the architectural-rules-documented gate result, and an explicit two-themes-shipped-atomically note." That's 5 mandatory sections + ~40 line minimum. My PR body landed at ~85 lines which is appropriate for a build-prd PR but reviewers may skim. Worth tagging the audit-pr role with a model-default annotation that emphasizes structured tables over prose for verdict reporting (already done — I used tables for SC + checklist).
- **`shipped_pr:` vs `pr:` frontmatter convention.** I added `shipped_pr:` to both roadmap items but the existing `prd:` field uses bare-key naming. Consistency note for the next item flipping to shipped — should the convention be `shipped_pr:` (verb-prefixed lifecycle key) or `pr:` (single-key, contextually unambiguous because adjacent to `shipped_date:`)? Filing as a roadmap-schema question, not a blocker.

## Coordination With Other Tracks

Both implementers (impl-include-preprocessor + impl-runtime-composer) signaled completion cleanly via SendMessage relay through team-lead. The handoff message from impl-runtime-composer included:

- All 4 commit hashes (`c7699f1`, `d5d7579`, `4e731bf`, `5c3ceeb`)
- A pre-computed SC coverage matrix mapping fixtures to SC IDs
- An NFR-8 disjoint-partition pre-verification (every Theme A file last-touched by `c7699f1`, every Theme B file by Theme B's commits) — saved me re-deriving it from scratch

This is the right shape for an implementer→auditor handoff and should be templated into future implementer prompts: *"Before marking your task complete, send the auditor (a) commit hashes in order, (b) SC↔fixture coverage matrix, (c) any pre-computed NFR verifications you ran inline."*

## Substrate Citations (per the §Auditor Prompt — Live-Substrate-First Rule)

Per the new rule from issue #170 fix, I reached for `bash <fixture>/run.sh` directly first (tier-2 substrate), not for structural surrogates. Re-ran all 7 in-scope fixtures inline:

| Fixture | SC | Exit Code | Last-Line Summary |
|---|---|---|---|
| `plugin-kiln/tests/agent-includes-resolve/run.sh` | SC-1, SC-7 | 0 | `PASS: 8/8 assertions` |
| `plugin-kiln/tests/agent-includes-ci-gate/run.sh` | SC-2 | 0 | `PASS: 3/3 assertions` |
| `plugin-wheel/tests/compose-context-shape/run.sh` | SC-3, NFR-6 | 0 | `PASS: compose-context-shape — JSON shape, sorting, determinism, exit codes 2/3/6 all OK` |
| `plugin-wheel/tests/validate-bindings-unknown-verb/run.sh` | SC-4 | 0 | `PASS: validate-bindings-unknown-verb — exit 4 on bad verb, 0 on valid/empty, 1 on malformed/missing` |
| `plugin-wheel/tests/compose-context-unknown-override/run.sh` | SC-5 | 0 | `PASS: compose-context-unknown-override — exit 5 on unknown-agent, exit 4 on unknown-verb, override+merge semantics correct` |
| `plugin-kiln/tests/research-first-agents-structural/run.sh` | SC-6 | 0 | `PASS: research-first-agents-structural — all 3 agents conform to FR-A-10/FR-A-11` |
| `plugin-kiln/tests/claude-md-architectural-rules/run.sh` | SC-8 | 0 | `PASS: claude-md-architectural-rules — all 12 canonical phrases present in CLAUDE.md` |

In addition I ran two inline smoke tests beyond the authored fixtures:
1. **Resolver no-op invariant** (NFR-2): `bash plugin-kiln/scripts/agent-includes/resolve.sh plugin-kiln/agents/test-runner.md` → byte-identical to input ✅
2. **Composer end-to-end smoke** (g): invoked `compose-context.sh --agent-name research-runner --plugin-id kiln --task-spec <stub>` → emitted valid JSON with all 6 stanza sections, exit 0 ✅

## Step 4b Lifecycle Archival

PRD: `docs/features/2026-04-25-agent-prompt-composition/PRD.md`
PR: #173

Roadmap items flipped (status: open→shipped, state: distilled→shipped) with `shipped_date: 2026-04-25` + `shipped_pr: https://github.com/yoshisada/ai-repo-template/pull/173`:

- `.kiln/roadmap/items/2026-04-24-agent-spawn-context-injection-layer.md` (Theme A source)
- `.kiln/roadmap/items/2026-04-25-agent-prompt-includes.md` (Theme B source)

Phase remained `08-in-flight` for both; archival to a `09-shipped` phase is a separate roadmap concern.
