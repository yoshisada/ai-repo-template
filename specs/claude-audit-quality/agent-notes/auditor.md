# Auditor friction notes — claude-audit-quality

**Branch**: `build/claude-audit-quality-20260425`
**Phase**: 3 (audit + smoke + PR creation)
**Date**: 2026-04-25

## What worked

- **5/5 fixtures PASS via direct `bash run.sh`** — the structural-tripwire approach (assertion on exact contract text in SKILL.md / rubric) gave a reliable, fast-running SC-001..SC-005 evidence chain that didn't require live skill invocation. Total runtime <1 second.
- **NFR-001 baseline definition in research.md was actionable** — the bench script was reproduced verbatim; running it 5× post-PR took ~2 seconds and produced a clear pass (median 0.283s vs gate 1.022s, 0.27× the cap).
- **Structural FR-trace via `grep -n` against SKILL.md / rubric / build-prd SKILL** — 25/25 FRs resolved cleanly with file:line citations.

## What hit friction

### Friction 1 — Live `/kiln:kiln-claude-audit` invocation reads cached plugin skill body, not working tree

When I invoked `Skill({skill: "kiln:kiln-claude-audit"})`, the runtime expanded the **pre-PR** SKILL.md body from `~/.claude/plugins/cache/yoshisada-speckit/kiln/000.001.009.745/skills/kiln-claude-audit/SKILL.md`. That cached version lacks Step 2 (substance pass), the renumbered Step 3.5 (output-discipline invariant), and Step 4.5 (sibling preview). A live run therefore exercises the OLD rubric machinery, not the NEW substance rules — so SC-006 (substance row in audit log on live CLAUDE.md) cannot be empirically demonstrated end-to-end until the plugin re-publishes.

I documented this as **B-2** in `blockers.md` (substrate gap, not implementation gap) and proceeded with structural verification + manual reasoning about which substance rules WOULD fire on the current CLAUDE.md.

**PI proposal**:

**File**: `plugin-kiln/skills/kiln-build-prd/SKILL.md` (or auditor-spawn protocol)
**Current**: When a kiln-build-prd pipeline modifies `plugin-kiln/skills/<skill>/SKILL.md`, the auditor's live skill invocation in Phase 3 reads the published plugin cache (pre-PR skill body), not the working tree. SC-006-style "live verification" gates are unreachable in-pipeline.
**Proposed**: Add an auditor-step pre-flight that detects "this PR modifies a kiln skill body" → emit a documented blocker template `B-PUBLISH-CACHE-LAG` rather than letting the auditor improvise per-pipeline. Cleaner: have the auditor invoke skill-bodies via a `--plugin-dir <repo-root>/plugin-kiln` override (same flag wired into `/kiln:kiln-test`'s subprocess invocations) so live-runtime-against-working-tree becomes the auditor's substrate.
**Why**: This is the SECOND pipeline this run that hit a substrate gap (B-1 `kiln-test` plugin-skill harness; B-2 auditor live invocation). Both have the same shape — "in-session validation against a not-yet-published plugin body". Each new pipeline currently rediscovers the gap.

### Friction 2 — `tasks.md` Phase 3 task list is auditor-dense (8 tasks for 1 owner)

T080..T087 are all tagged `[auditor]` and run sequentially. Most are quick (each ≤30 seconds), but the framing made each step feel like an independent task — vs. the natural "audit checklist" mental model where each task is a checklist item under one umbrella. Marking them `[X]` one-by-one in the auditor's flow added bookkeeping overhead.

**PI proposal**:

**File**: `plugin-kiln/skills/kiln-build-prd/SKILL.md` and `plugin-kiln/skills/tasks/SKILL.md`
**Current**: Phase 3 (auditor) tasks are split into per-action tasks (T080 `/audit`, T081 fixtures, T082 NFR-001, T083 NFR-003, T084 SC-006, T085 SC-008, T086 smoke, T087 PR). One owner; all sequential.
**Proposed**: Collapse Phase 3 into a single auditor task with sub-checklist (e.g. `T080 [auditor] Audit + smoke + PR — runs the full Phase 3 checklist (FR trace, fixtures, NFR-001, NFR-003, SC-006, SC-008, smoke, PR creation, blockers reconciliation)`). The checklist lives in the task description, not as separate task IDs. Frees the spawned `auditor` agent to handle the audit as a single workflow step.
**Why**: 8 sequential tasks with one owner is bookkeeping-heavy for both the agent (8x `TaskUpdate` calls) and the team-lead (8x status checks). The natural mental model is "the audit is one job"; the task system should match that.

### Friction 3 — NFR-001 measurement scope ambiguity

`tasks.md` T082 says: "Re-run `/tmp/audit-bench.sh` script (source in research.md §Baseline) 5 times; compute median; assert median ≤ 1.022 s." But the team-lead's prompt also said: "re-run `/kiln:kiln-claude-audit` 5x against current CLAUDE.md, capture median". These are different measurements:

- `/tmp/audit-bench.sh` measures the SHELL-side portion (deterministic, ~280ms).
- `/kiln:kiln-claude-audit` Skill invocation measures the FULL audit including model-side editorial passes (non-deterministic, can take many seconds; per research.md "NFR-001 is enforceable on the shell-portion measurement... and is **not** enforceable on the editorial portion").

I followed the research.md guidance and used `/tmp/audit-bench.sh` as the canonical NFR-001 anchor.

**PI proposal**:

**File**: `plugin-kiln/skills/kiln-build-prd/SKILL.md` (auditor instruction template) and `templates/spec-template.md` (NFR section guidance)
**Current**: NFR-001 latency-bound spec language ("audit duration MUST NOT increase by more than 30%") doesn't disambiguate "audit duration = shell-side script time" vs. "audit duration = full skill invocation wall-clock". The auditor has to read research.md §Baseline to disambiguate.
**Proposed**: Spec-template guidance for latency NFRs should require the spec to explicitly name the measurement scope (e.g. "shell-side cheap-rule pass via bench script `<path>`", or "full skill invocation including editorial LLM calls"). Auditor task descriptions should reuse the spec-named scope verbatim — no paraphrasing.
**Why**: This is the THIRD friction point in the kiln pipeline around NFR latency measurement scope (see prior pipeline friction in `wheel-as-runtime`). Standardizing the spec template closes a recurring gap.

## Audit-of-pipeline observations

- **Insight density of this PR**: HIGH. The PRD was a faithful 1:1 distillation of 8 roadmap items; the spec/plan/tasks chain preserved FR numbering verbatim; the implementer agents produced detailed friction notes that flagged the substrate gap (B-1) ahead of the auditor's discovery path (B-2). The retrospective should land an `insight_score: 4` or `5` if Theme F's self-rating works.
- **Substrate gaps account for 2/4 documented blockers** (B-1, B-2). Both are substrate, not implementation. They're the right kind of blocker — substrate evolves on a cadence the per-PR pipeline can't drive.
- **Carve-out discipline (NFR-001 shell-side; NFR-003 within-scope idempotence)** worked exactly as the spec authors anticipated. The carve-outs are documented in spec.md and applied in audit verdicts without ambiguity.
- **Fixture authoring as `run.sh` tripwires** (forced by B-1) was unexpectedly clean — the structural assertions are higher-fidelity than a brittle live-skill smoke would have been, because they pin the EXACT contract text rather than reasoning about LLM output shape. Recommend keeping this as a permitted fixture form even after kiln-test gains plugin-skill substrate parity.

## PIs delivered to retrospective

The 3 PI proposals above (substrate-gap escalation; auditor-task collapse; NFR measurement scope disambiguation) should be picked up by the retrospective agent and surfaced as bold-inline PIs in the retro issue body. They are all **process** PIs (not feature requests) and follow the bold-inline `**File** / **Current** / **Proposed** / **Why**` format the retro-quality rubric (FR-025) prefers.
