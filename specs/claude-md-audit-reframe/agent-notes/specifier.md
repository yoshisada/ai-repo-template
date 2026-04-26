# Specifier — friction note

**Agent**: specifier
**Branch**: `build/claude-md-audit-reframe-20260425`
**Date**: 2026-04-25
**Phase**: 1 (Specify + plan + research + tasks)

## Why baseline-checkpoint research was skipped

The team-lead's spawn instructions explicitly stated:

> The PRD's Success Metrics are POST-implementation absolute targets (≥70% classification rate, 100% Why: coverage, etc.) — NOT pre-existing baselines. You do NOT need to run baseline-capture research before /specify.

I confirmed this against the PRD (`docs/features/2026-04-24-claude-md-audit-reframe/PRD.md` §Success Metrics): every metric is forward-looking and only becomes measurable once the new rules ship. There is no existing system state to baseline against:

- The classification rule doesn't exist yet → can't measure classification rate.
- `Why:` line coverage isn't defined yet (FR-005 introduces it) → can't measure baseline coverage.
- The plugin-guidance convention doesn't exist yet → no baseline guidance files.
- Vision sync doesn't exist → no baseline `## Product` mirror.

Phase 0 (research) is documented as skipped in `plan.md`. The auditor should NOT flag this as a missing research artifact — it's intentional.

## Decisions on ambiguous PRD requirements

### 1. PRD numbering gap (FR-020, FR-021 absent)

The PRD jumps from FR-019 to FR-022. Per team-lead instructions, this is intentional and the spec/tasks should NOT renumber to fill the gap. I preserved the verbatim PRD numbering throughout `spec.md`, `plan.md`, `contracts/interfaces.md`, and `tasks.md` so cross-references stay 1:1.

### 2. vision.md >40 lines without fenced markers (FR-023 boundary)

PRD FR-023 says vision.md is mirrored in one of two ways: whole file (≤40 lines) OR fenced region. It does not specify behavior when the file is >40 lines AND has no markers. Decision (recorded in spec.md Edge Cases + contracts §1.1 / §3.2): fire a sub-signal under `product-section-stale` with action `expand-candidate` proposing the user add fenced markers. We do NOT mirror the long file (would bloat CLAUDE.md and undo the reframe).

This is a content-shaping decision. The auditor or a future user can revisit if they prefer a different policy.

### 3. Single classification LLM call vs per-section calls (FR-001)

PRD FR-001 says classification is via "an editorial (LLM) call that reads the section and grades against rule-specific definitions." Could mean per-section or per-file. Decision (recorded in plan.md §Phase 1 → "LLM call shape"): one call per audited file, returning a JSON map `{ heading: classification }`. Rationale: bounded run time, idempotence guarantee, less LLM token spend. Per-section fan-out would be more accurate but blow the budget.

If the auditor wants per-section accuracy, the implementation can be re-cut later — this is a performance/cost decision, not a correctness one.

### 4. `enabledPlugins` settings.json key (FR-011)

PRD says read enabled plugins from `.claude/settings.json` and `~/.claude/settings.json`. Decision: the exact key name is `enabledPlugins` (per Claude Code's known schema). Recorded in contracts §5 with the literal `jq` expression. If the actual key shape differs in some Claude Code version, the implementation should adapt and update the contract.

### 5. `## Plugins Sync` and `## Vision Sync` output sections (rendering)

PRD Notes section behavior (FR-016) only mandates the trailing reminder line. Decision (contracts §3.1, §3.2): introduce explicit `## Plugins Sync` and `## Vision Sync` headed sections in the output file with status indicators (✅ / ➕ / 🔄 / ➖). This makes the audit log scannable for humans and gives downstream tests a stable grep target.

The trailing FR-016 blockquote appears verbatim inside `## Plugins Sync`, so the contract is preserved.

### 6. Header demotion contract for guidance files (FR-014, FR-028)

PRD FR-014 says `## When to use` is demoted to `#### When to use`. Decision (contracts §4.3): authors write `## When to use` (the natural top-level for the file); the audit demotes on sync. Plugin authors do NOT write `#### When to use` directly. This avoids the awkward "why is this file's top header level 4?" question for authors.

### 7. Implementer split — fixture authoring (T082, T088 dependency on impl-plugin-guidance)

`impl-audit-logic` owns the test fixtures, but two specific fixtures (T082 plugin-sync-passes, T088 plugin-author-update) need real guidance file content to assert against. Decision (tasks.md §Phase Dependencies): `impl-audit-logic` waits for `impl-plugin-guidance` to ship at least kiln + shelf guidance files before completing those fixtures. All other Phase 2A tasks have no dependency on Phase 2B, so the parallel-execution wins are preserved.

This is a coupling point but a tolerable one — both implementers know about it via tasks.md.

### 8. `sort_priority: top` schema extension (FR-025)

FR-025 says `product-undefined` "MUST appear at the top of the Signal Summary table regardless of normal sort order." Decision: add a new optional field `sort_priority: top` to the rubric rule schema (contracts §1.1). Currently only `product-undefined` uses it. This is forward-extensible — future rules with the field will outrank default sort, and the field's absence is the same as `sort_priority: default`.

### 9. `target_file` and `render_section` schema extensions (FR-026)

`product-slot-missing` runs against `.kiln/vision.md` not CLAUDE.md, and renders under a dedicated sub-section. Decision: introduce two new optional rule-schema fields — `target_file:` (defaults to the audited CLAUDE.md path; `product-slot-missing` overrides to `.kiln/vision.md`) and `render_section:` (defaults to the main Signal Summary; `product-slot-missing` overrides to `Vision.md Coverage`). Recorded in contracts §1.1.

These extensions are backward-compatible — existing rules omit both fields and behave as before.

## Handoff notes for implementers

### For `impl-audit-logic`

1. **Read `plugin-kiln/skills/kiln-claude-audit/SKILL.md` end-to-end first.** The existing skill body is ~360 lines and already establishes patterns (Step 1 project context, Step 1b path resolution, Step 2 rubric load, Step 3 cheap+editorial rules, Step 3b external best-practices, Step 4 output, Step 5 report). Your work extends each of these steps — don't re-architect.
2. **The classification call (Phase 2A.3) is a NEW Step 2.5.** It runs ONCE per audited file, before Step 3's rules. Failure gracefully degrades all sections to `unclassified`.
3. **Override grammar extension (Phase 2A.2) lives inside Step 2.** Existing parser handles `key = value` lines and `<rule_id>.<field>` overrides — extend the value-validation switch to recognize the new top-level keys.
4. **`enumeration-bloat` precedence over `load-bearing-section` (FR-031) is the ONE CARVE-OUT** in signal reconciliation. Be careful — the existing reconciliation code prefers `load-bearing-section` unconditionally. You're inverting that for one specific classification value.
5. **Idempotence (NFR-002) is non-negotiable.** Sort everything: plugin enumeration, signal table rows, Vision.md Coverage slots (1..7 fixed order). Test it with the T203 smoke check.
6. **Fixture authoring follows the existing `claude-audit-cache-stale/` and `claude-audit-network-fallback/` shape.** Each fixture has a `run.sh`, fixture inputs, and assertions against the produced `.kiln/logs/` log file. Don't invent a new fixture format.
7. **You do NOT touch `plugin-*/.claude-plugin/claude-guidance.md` files** — those are `impl-plugin-guidance`'s. If reading the file shape needs a parser tweak, the parser lives in your skill body — extend it; don't edit the guidance files.

### For `impl-plugin-guidance`

1. **Five files, one shape.** Read `contracts/interfaces.md` §4 carefully — the shape is constrained. `## When to use` is required (1–3 sentences, NOT a list). The other two sections are optional and entirely omittable.
2. **No skill / command / agent / hook / workflow enumerations anywhere.** This is the whole point of the reframe — guidance describes *what the plugin does* and *why Claude reaches for it*, not *what skills it ships*.
3. **Soft length cap: 10–30 lines per file.** Authors can exceed it but should justify in the friction note. Don't pad.
4. **Use `.kiln/vision.md` as a tone reference.** The vision file is product-narrative-style — your guidance files are sub-vision-style for each plugin. If your file reads like a README, it's wrong.
5. **Wheel's guidance is the trickiest** because wheel is plugin-agnostic infrastructure (per `.kiln/vision.md` "Plugins ship independently — wheel is plugin-agnostic infrastructure"). Cite that constraint. The when-to-use is "when you need workflow dispatch" not "when you need any specific feature."
6. **You do NOT touch the skill body or rubric** — those are `impl-audit-logic`'s. If you find a file-shape constraint that doesn't match the contract, file a SendMessage to specifier or impl-audit-logic — do not edit their files.
7. **All five files can be authored in parallel.** No internal ordering. Commit them all together with your friction note.

### For both implementers

- Mark tasks `[X]` immediately on completion (Article VIII), not batched.
- Commit per phase (not per task — that's too granular for this feature).
- Friction notes go to `agent-notes/<your-agent-name>.md`. Include: what was unclear in the contract, decisions you made on ambiguous points, anything the auditor should know.
- The auditor (Phase 3) verifies your work end-to-end, including the propose-diff-only contract and idempotence. Don't ship anything that fails T203's `diff -u` smoke check.

## Open questions surfaced during specify (NOT blocking)

1. **Anthropic URL stability**: FR-018 cites `https://code.claude.com/docs/en/best-practices#write-an-effective-claude-md`. If the URL moves, the rubric Convention Notes + audit Notes both need updating. Not addressed in this PR; surfaced as a future maintenance concern.
2. **Third-party plugin guidance quality**: FR-009 says plugins MAY ship `claude-guidance.md`. We're shipping references for first-party plugins (kiln, shelf, wheel, clay, trim) but third-party plugins are unconstrained. PRD §Risks documents this; nothing to do here beyond the file-shape contract.
3. **`hook-claim-mismatch` false positive rate**: FR-008 explicitly accepts grep-based false positives (jq filters, non-obvious code paths). We're not measuring the FP rate empirically — just shipping with that disclaimer. If it turns out to be too noisy in practice, the rule can be tightened in a follow-up PR.
4. **`enabledPlugins` settings shape**: contracts §5 assumes the literal key `enabledPlugins`. If Claude Code changes this shape, the contract is updated. Not a concern for this PR.

No blocking ambiguities — proceeded to plan + tasks without escalation.

## What I would do differently next time

- I'd consider asking the team-lead earlier whether the implementer split should be 3 implementers (audit-logic-cheap, audit-logic-editorial, plugin-guidance) instead of 2. The cheap/editorial split inside audit-logic creates a longer Phase 2A pipeline. Two-implementer split is fine for this PR but the parallelism could be higher. Surfaced for retrospective.
- The contracts file got long (~280 lines). Future specs might benefit from splitting `contracts/` into `contracts/rubric.md`, `contracts/output.md`, `contracts/guidance.md`. Not done here for simplicity, but flagged.
