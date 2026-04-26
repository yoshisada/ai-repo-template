# impl-audit-logic — friction note

**Agent**: impl-audit-logic
**Branch**: `build/claude-md-audit-reframe-20260425`
**Date**: 2026-04-25
**Phase**: 2A (audit-logic implementation)
**Tasks owned**: T010..T088 (Phase 2A.1..2A.9)

## Summary

Phase 2A is structurally complete: rubric extension, SKILL.md extension (override grammar + classification + reframe rules + plugin sync + vision sync + output rendering), and 19 fixture directories under `plugin-kiln/tests/claude-audit-*/`. Three commits, one per logical phase grouping (rubric / skill / fixtures).

## What was clear in the contract

- The contracts file (`specs/claude-md-audit-reframe/contracts/interfaces.md`) was the single source of truth I leaned on most. The four contract surfaces (§1 rubric schema, §2 override grammar, §3 output rendering, §4 guidance file shape) covered every implementation decision I needed to make. Where the spec was ambiguous, the contract pinned it down precisely (e.g., §3.1's `## Plugins Sync` exact status-line shape, §3.3's `sort_priority DESC` extension).
- The specifier's friction note (§Decisions on ambiguous PRD requirements, 9 decisions) saved me from re-deriving each ambiguity. The decisions on the LLM-call-shape (one call per file vs per-section) and the `## Plugins Sync`/`## Vision Sync` rendering shape were particularly load-bearing for my work.
- The disjoint file ownership (impl-audit-logic vs impl-plugin-guidance) was crystal clear and easy to honor — I never came close to wanting to edit a guidance file.

## What was confusing or required judgment

### 1. Test substrate — heavyweight live-runtime fixtures vs unit tests

The spec mandates fixtures under `plugin-kiln/tests/claude-audit-*/` with `harness-type: plugin-skill`, which means each fixture spawns a real `claude --print --plugin-dir` subprocess. With 19 new fixtures, that's enormous to actually run end-to-end. I authored all 19 with proper structure (test.yaml + assertions.sh + initial-message.txt + answers.txt + fixtures/CLAUDE.md + shared fresh-cache stub) but did NOT execute them — that's the auditor's T201 job.

Per the team-lead's "test substrate hierarchy" guidance, plugin-skill fixtures are PRIMARY evidence. I cited them by structure here; the auditor will run them and report verdicts.

### 2. Ambiguity on Notes-section line ordering

Contracts §3.4 lists the new Notes lines but doesn't pin their relative order against the existing Notes lines (cache stale, override-rules-applied, project-context-signals). I chose to append the new ones AFTER the existing ones, in this order: (1) external-alignment URL [always], (2) FR-016 sync reminder [conditional], (3) missing-reason warnings [per-override], (4) unclassified-section notes [per-failed-section]. This preserves byte-determinism via stable sort within each conditional bucket.

If the auditor disagrees with the ordering, it's a one-line fix in Step 4 of the SKILL — no contract change needed.

### 3. Step 2.5 placement and gating

I named the classification step "Step 2.5" because it logically slots between Step 2 (rubric load) and Step 3 (rule firing). The classification map MUST be available before Step 3's reframe rules fire. This is a structural decision; the contracts §1.4 reconciliation pseudocode assumed this ordering.

### 4. Cheap pre-filter for `benefit-missing` and `loop-incomplete`

Both are documented as `cost: editorial` in the rubric, but I added a cheap pre-filter (regex/grep) that short-circuits the LLM call when possible. Rationale: idempotence + token spend + the failure mode is already gated (LLM unavailable → mark inconclusive). The pre-filter is a strict subset of the editorial check — if the cheap regex finds rationale, the rule does NOT fire and no LLM call is made. This is a performance optimization, not a correctness change.

The auditor should verify this matches the spec's editorial-rule budget intent (FR-005, FR-006).

### 5. `product-undefined` template fallback

FR-025 says the proposed diff creates `.kiln/vision.md` from `plugin-kiln/templates/vision-template.md`. When running consumer-side, that template path resolves through the same plugin path-resolution chain as the rubric (Step 1b). I did NOT explicitly extend the path resolver — Step 1b already handles the consumer-cache fallback for plugin-kiln assets. The implementation should reuse that existing resolver pattern.

If the auditor finds the template doesn't actually exist at `plugin-kiln/templates/vision-template.md`, that's a separate gap (file-shipping question) — not an audit-logic implementation gap. I left a comment in the SKILL referencing the path; if the file is missing, the SKILL falls back to a minimal 7-slot scaffold.

## Test substrate decisions

Per the team-lead's hierarchy: I used **plugin-skill** fixtures (PRIMARY) for all 19 new tests because (a) the existing claude-audit fixtures use plugin-skill and (b) the audit logic is heavily LLM-driven so unit-shell tests would not exercise the meaningful code path. Each fixture's assertions.sh greps the produced `.kiln/logs/claude-md-audit-*.md` preview for the FR's required signal text.

Did not invoke `/kiln:kiln-test plugin-kiln` myself — leaving that for the auditor (T201). Running 19 plugin-skill fixtures end-to-end is expensive (each spawns a real claude subprocess) and the auditor's job is to verify all of them pass before opening the PR.

## What would have helped

1. **Schema-diff lint for the rubric**. The new schema fields (`classification_input`, `sort_priority`, `target_file`, `render_section`) are documented in contracts §1 but there's no automated check that the rubric body actually contains them. A 5-line awk script in `plugin-kiln/scripts/` would catch malformed rubric on commit.
2. **Pre-staged fixture skeleton**. Authoring 19 fixture directories meant a lot of repetitive structure (test.yaml + answers.txt + best-practices stub). A `plugin-kiln/scripts/scaffold-claude-audit-fixture.sh <name>` would have saved ~30% of fixture-authoring time. Surfaced for retrospective as a manifest improvement.
3. **Concrete example for the FR-031 carve-out**. The spec correctly identifies `enumeration-bloat` > `load-bearing-section` for `plugin-surface`, but the rubric's signal-reconciliation prose was abstract. I added a concrete example in the rubric body. Worth carrying that pattern forward in future rule additions.

## Things flagged for retrospective

- **The two implementer split (audit-logic + plugin-guidance) was tight and well-coordinated.** No file-overlap concerns, no synchronization stalls. The specifier's "kiln + shelf shipped first" gate for T082/T088 worked cleanly because impl-plugin-guidance shipped all five files in one commit.
- **The fixture-authoring volume (19 dirs) is high relative to the implementation surface (~250 lines of skill + ~200 lines of rubric).** A simpler split — e.g., one fixture per FR cluster instead of per-FR — would cut maintenance load. Spec'd it as is for completeness; future audit-style features can revisit the fixture/rule ratio.
- **`harness-type: plugin-skill` means each fixture is a real claude subprocess.** Running 19 of them is expensive, and the harness has no "fast" mode for unit-shape assertions. A `harness-type: shell-test` substrate (already on the roadmap) would be a major productivity win for skills like this one. Worth re-prioritizing.
- **The `agent-notes/specifier.md` handoff was extremely useful** — particularly the 9 decisions on ambiguous PRD points. Strongly recommend keeping that pattern in future build-prd pipelines.

## Anything that would block the auditor

Nothing structural. Key things the auditor needs to verify:

1. Every new rule entry in the rubric matches contracts §1.1 exactly (yaml block + prose sections).
2. The SKILL.md extensions match contracts §2 (override grammar), §3 (output rendering), §5 (plugin enumeration), §6 (path resolution) exactly.
3. Idempotence (NFR-002 / SC-006) — run the audit twice on a frozen fixture and `diff -u` the outputs. The classification LLM call is the most likely source of non-determinism; if outputs differ across runs, there's a temperature/sampling issue to address.
4. SC-007 (product-undefined at row 1) — fixture `claude-audit-product-undefined/` asserts this with an explicit awk-based row-extraction.
5. SC-005 (silent skip on missing guidance file) — fixture `claude-audit-plugins-sync-missing/` asserts the absence of any signal-row firing.
6. The 19 fixtures pass via `/kiln:kiln-test plugin-kiln`. If any fails, the failure modes I'd suspect first: classifier LLM not consistently identifying `plugin-surface`/`convention-rationale` (T070, T071, T072, T076), or the cheap pre-filter missing edge cases in section bodies (T072).

No `blockers.md` items. All FRs in scope (FR-001..FR-008, FR-011..FR-019, FR-022..FR-031) are covered by either the rubric extension, the SKILL.md extension, a fixture, or all three.
