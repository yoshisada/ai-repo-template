---
description: "Friction note from the auditor for the Mistake Capture feature build. Retrospective input."
---

# Auditor friction note — mistake-capture

**Date**: 2026-04-16
**Audited commits**: `4eb1919` (spec), `8bda712` (impl-kiln), `026ef7c` (impl-shelf)

## What the audit caught

- **Nothing to fix post-implementation.** Both implementers produced contract-conformant output in a single iteration. PRD→Spec→Code→Test traceability was 100%; portability grep came back empty; JSON parsed; shell scripts passed `bash -n`; plugin.json workflow registration was present.
- **Contract edits were handled correctly upstream.** `contracts/interfaces.md` was updated FIRST (per constitution VII) for all three edits (MCP scope switch to `obsidian-manifest`, reconciliation ownership move command→agent, `mistakes_prior_state` projection). The `agent-notes/contract-edits.md` file carries the rationale. Auditor did not need to unwind or retrofit.

## What the smoke test revealed

- **Shelf side: clean end-to-end.** Seeded a realistic fixture under `.kiln/mistakes/`, ran `compute-work-list.sh`, got `action: create` with every `source_data` field populated correctly, the computed `proposal_path` matching the `@inbox/open/` target shape, and `counts.mistakes.create: 1`. Removed the fixture — re-ran the script — empty `mistakes: []` with no errors. The hash-based diff and filed-state short-circuit (FR-014) logic are documented in-code with contract references.
- **Kiln side: surrogate-only.** The `/wheel-run kiln:report-mistake-and-sync` activation path cannot be truly exercised from the source repo because `workflow_discover_plugin_workflows` reads from `~/.claude/plugins/cache/yoshisada-speckit/kiln/<version>/workflows/`, and that cache still holds version `000.000.000.1143` which pre-dates this feature. The static contract checks (JSON parse, step ids/types, `terminal: true`, instruction-string completeness, portability grep) all pass. Phase 5 T036–T038 are documented as DEFERRED blockers in `blockers.md` for the first post-merge session.

## Was blockers.md well-maintained?

- `blockers.md` did not exist before this audit — I created it. Both implementers kept their work inside their respective `agent-notes/*.md` friction notes and did not pre-populate a blockers file. That's the right pattern: blockers is the auditor's artifact for audit-time findings, not a work-in-progress log. impl-kiln's friction note flagged T014/T015 as "deferred to Phase 5" cleanly, which made rolling them into Blocker 1 straightforward.

## Prompt clarity — retrospective signals

**What worked well**:

- The canonical-paths block at the top of the dispatch (working dir, branch, spec dir, PRD path) removed any ambiguity about which tree to audit.
- The "completeness check MANDATORY before auditing" block prevented me from running against partial state — Tasks #2 and #3 were both `pending` when I first checked TaskList, so I paused and notified team-lead rather than proceeding with a half-audit.
- The explicit "smoke test" sub-section spelled out the four acceptance criteria in order (a–d). I could work through them as a checklist rather than having to reverse-engineer what "smoke test" meant.
- The explicit cleanup requirement ("the smoke-test mistake should be reverted before PR") set the expectation correctly — I used a conformant fixture, verified, and deleted in the same session. No spam left in Obsidian.
- The PR-format HEREDOC meant I didn't need to guess at the label, title, or body shape.

**Pain points**:

- **Agent-message handshake is implicit**: the instructions said "wait until BOTH are marked completed AND you've received confirmation SendMessages from impl-kiln and impl-shelf" — but `TaskList` is the authoritative signal, and the SendMessage confirmations arrived after TaskUpdate on the sender's side. I used TaskList as the gate. If the retrospective wants stronger evidence of receipt, a short note in the dispatch saying "prefer TaskList completion status as the gate; SendMessage confirmations are advisory" would be clearer.
- **Smoke test (a) assumes `/wheel:wheel-run` will activate successfully from the source repo.** It won't, because the plugin cache lags. The dispatch could acknowledge this explicitly: "if the new workflow is not yet in `~/.claude/plugins/cache/...`, perform surrogate smoke via direct script invocation and document the deferred end-to-end in blockers.md." I arrived at this path but it took a wheel-discovery dive to confirm.
- **Plugin-cache staleness is recurring friction across this codebase.** Both implementers and I ran into the same issue (T014/T015 for impl-kiln, T036/T037/T038 for me, Phase 5 smoke generally). A team-level roadmap item to add a "run-from-source" mode to wheel discovery — or a `/wheel:wheel-install-local` convenience command — would close this gap and let post-commit validation happen in the same session as the commit.

**Specific to this feature**:

- Contract-first discipline paid off. The three contract edits were documented, contracts updated, and both implementers built against the revised contracts without drift. This is the second time in a build-prd run where `contracts/interfaces.md` has kept parallel agents aligned — the pattern is working.
- The PRD was unusually explicit about "mirror `/report-issue` exactly" — that prior-art pointer made the audit easy because divergences would have stood out. Future PRDs that have a strong prior-art analog should adopt this pattern.

## Net retrospective recommendation

Prompt: **A-grade**. One small clarification about SendMessage-vs-TaskList as the synchronization primitive would tighten it further.

Pipeline: **B-grade** due to the plugin-cache staleness problem. Not this feature's fault — it's ambient — but Phase 5 smoke tests are systematically deferred because of it. Worth a roadmap item.

Feature quality: **A-grade**. Contract-conformant, portable, schema-honest, tested via surrogate smoke. Safe to merge with T036–T038 tracked as a post-merge follow-up.
