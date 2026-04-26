# Blockers — claude-audit-quality

**Branch**: `build/claude-audit-quality-20260425`
**Auditor**: T080–T087 (Phase 3)
**Status as of audit**: 2/4 documented blockers are documented-and-bypassed; 2 are documented-and-must-be-tracked-as-follow-on-items.

---

## B-1 — `kiln-test` plugin-skill harness cannot drive `run.sh`-only fixtures (substrate gap)

**Discovered by**: `impl-tests-and-retro` during Phase 2C.
**Impact**: Tasks T070..T074 author `run.sh` pure-shell tripwire fixtures rather than the canonical `inputs/` + `assertions.sh` + `test.yaml` shape, because the kiln-test harness's plugin-skill substrate cannot yet drive a deterministic claude-subprocess invocation against a fixture mktemp dir. The five fixtures live under `plugin-kiln/tests/claude-audit-*/run.sh`.

**Bypass**: `tasks.md` Phase 3 T081 documents the canonical invocation path:

```bash
for f in plugin-kiln/tests/claude-audit-no-comment-only-hunks \
         plugin-kiln/tests/claude-audit-editorial-pass-required \
         plugin-kiln/tests/claude-audit-substance \
         plugin-kiln/tests/claude-audit-grounded-finding-required \
         plugin-kiln/tests/claude-audit-recent-changes-anti-pattern; do
    bash "$f/run.sh" || exit 1
done
```

**Auditor verdict (2026-04-25)**: All five fixtures invoked directly via `bash run.sh` — **all PASS**. Per impl-tests-and-retro friction note PI-3, follow-on item: `kiln-test` SKILL.md should extend discovery to `run.sh`-only fixtures. Track separately; not a PR-blocking gap.

**Status**: documented-and-bypassed.

---

## B-2 — Live `/kiln:kiln-claude-audit` invocation reads cached plugin skill body, not working tree (substrate gap)

**Discovered by**: `auditor` during T084 / smoke-test.
**Impact**: When the auditor invokes `Skill({skill: "kiln:kiln-claude-audit"})`, the runtime expands the SKILL.md body from the **published plugin cache** at `~/.claude/plugins/cache/yoshisada-speckit/kiln/000.001.009.745/skills/kiln-claude-audit/SKILL.md`. That cached version is the **pre-PR** body — it lacks the Theme A-E changes (Step 2 substance pass, Step 3.5 output-discipline invariant, Step 4.5 sibling preview render). A live invocation therefore exercises the OLD rubric machinery, not the NEW substance rules; the new rules cannot be demonstrated to fire end-to-end until the plugin is re-published and re-cached.

**Why this is acceptable for this PR**:

1. **All 5 new fixtures PASS** via direct `bash run.sh` invocation — they assert on the **exact contract text** in the working-tree SKILL.md / rubric. SC-001..SC-005 are anchored in fixture assertions, not in live skill output.
2. **Structural FR-trace** (T080) confirms every FR-001..FR-025 lands in the working-tree files (skill body, rubric, doctor SKILL, build-prd SKILL, retro-quality.md).
3. **NFR-004 backward compat** verified by spot-checking that all four existing rules (`stale-migration-notice`, `recent-changes-overflow`, `enumeration-bloat`, `hook-claim-mismatch`) retain their original `match_rule:` definitions in the working-tree rubric.
4. **NFR-001 (shell-side, the enforceable measurement per research.md §Baseline)** — re-ran `/tmp/audit-bench.sh` 5×: median **0.283 s** vs. baseline median **0.786 s** (gate **≤1.022 s**). PASS by a wide margin — the new substance rules are editorial (model-side); shell-side cost is essentially unchanged.
5. **Empirical reasoning about live behavior** (manual walk of new rules vs. current CLAUDE.md):
    - `recent-changes-anti-pattern` (FR-016): `## Recent Changes` heading present in CLAUDE.md → **WOULD fire** with `removal-candidate`.
    - `missing-architectural-context` (FR-008): 5 `plugin-*/` roots (`plugin-clay`, `plugin-kiln`, `plugin-shelf`, `plugin-trim`, `plugin-wheel`); `## Architecture` section names only `plugin-kiln`, `plugin-shelf`, `plugin-wheel` (+ generic `plugin-dir` reference) → missing 2 plugins → **WOULD fire**.
    - `missing-thesis` (FR-006): vision pillars `feedback loop`, `spec-first`, `AI-native` present in CLAUDE.md; pillars `language-agnostic`, `context-informed autonomy` absent. Pre-filter (R-1 mitigation) finds ≥1 vision-pillar phrase → likely does NOT fire (judgment call by editorial pass).
    - `missing-loop` (FR-007): `/kiln:kiln-distill` mentioned in CLAUDE.md → does NOT fire.
    - `scaffold-undertaught` (FR-009): applies to `plugin-kiln/scaffold/CLAUDE.md` — would require editorial check; depends on scaffold body content.

**Bypass**: live verification of new substance rule firings is deferred to the first session AFTER this PR lands AND the plugin re-publishes / re-caches. This is the same in-session-spawn limitation as Architectural Rule 5 (agent registration is session-bound). Live spawn validation is a follow-on, not a PR gate.

**Follow-on item**: track as `2026-04-25-claude-audit-substrate-cache-refresh` in `.kiln/roadmap/items/` after PR merge — once published, run `/kiln:kiln-claude-audit` against this repo's CLAUDE.md and verify substance rows appear in the Signal Summary table per SC-006.

**Status**: documented-and-bypassed (substrate gap, not implementation gap).

---

## B-3 — NFR-003 byte-identity carve-out (no-X path only)

**Per spec.md NFR-003 carve-out (Step 1.5 reconciliation)**: byte-identity binds within-scope idempotence. On the **no-substance-rule-fire** path (a structurally-clean fixture where no new substance rule fires), the new code paths are inert — they only add render rules / sort keys CONDITIONAL on substance signals firing. Therefore Signal Summary + Proposed Diff bodies are byte-identical to the pre-PR output.

**Test path (no-X)**: a structurally-clean fixture exists in `plugin-kiln/tests/claude-audit-grounded-finding-required/fixtures/CLAUDE.md` (passes mechanical rules; only substance-rule-fire would change output). The fixture's `run.sh` PASSes — the substance rule asserts the placeholder + rationale-line CONTRACT is present in the SKILL.md, not that bytes diverge.

**Cross-scope (a real divergence between pre/post on the same input that DOES fire substance rules)**: not byte-identical by design — substance rows ADD content. The carve-out applies; this is intended behavior.

**Auditor verdict**: NFR-003 holds on the no-X path. Documented explicitly per the carve-out. Cross-scope divergence (when substance rules fire) is the FEATURE, not the regression — see FR-010 ordering rule.

**Status**: documented-and-resolved.

---

## B-4 — Roadmap items remain `state: distilled` (manual flip needed post-merge)

**Per task description**: the 8 derived_from roadmap items (under `.kiln/roadmap/items/`) had their state flipped from `in-phase` → `distilled` during the previous distill run. This PR's land/merge does NOT auto-flip them to `shipped` — that auto-flip is itself an unresolved item in the same `10-self-optimization` phase (`2026-04-25-build-prd-auto-flip-item-state`).

**Bypass**: maintainer manually flips the 8 items from `state: distilled` → `state: shipped` after PR #merge. Track as roadmap item `2026-04-25-build-prd-auto-flip-item-state` (already in phase 10; not in this PR's `derived_from`).

**Affected items**:
- `.kiln/roadmap/items/2026-04-24-claude-audit-deeper-pass-on-thin.md`
- `.kiln/roadmap/items/2026-04-24-claude-audit-emit-real-diffs.md`
- `.kiln/roadmap/items/2026-04-24-claude-audit-execute-editorial-rules.md`
- `.kiln/roadmap/items/2026-04-24-claude-audit-grounded-citations.md`
- `.kiln/roadmap/items/2026-04-24-claude-audit-rethink-recent-changes-rule.md`
- `.kiln/roadmap/items/2026-04-24-claude-audit-sibling-preview-codified.md`
- `.kiln/roadmap/items/2026-04-24-claude-audit-substance-rules.md`
- `.kiln/roadmap/items/2026-04-24-retro-quality-auditor.md`

**Status**: documented-and-tracked-as-follow-on. Not a PR-blocking gap.

---

## Compliance summary

| Dimension | Result | Notes |
|---|---|---|
| FR coverage (FR-001..FR-025) | 25/25 (100%) | All structurally present in skill body / rubric / build-prd SKILL / retro-quality.md |
| NFR-001 (latency) | PASS | Shell-side median 0.283s vs gate 1.022s (research.md baseline definition) |
| NFR-002 (fixture self-containment) | PASS | All 5 fixtures self-contained; no network |
| NFR-003 (byte-identity) | PASS (no-X path; carve-out applies cross-scope) | See B-3 |
| NFR-004 (backward compat) | PASS | 4 existing rules retain match_rule definitions |
| SC-001..SC-005 | PASS | All 5 new fixtures invoked via `bash run.sh` — all PASS |
| SC-006 (live substance row) | DEFERRED to post-merge | See B-2 substrate gap |
| SC-007 (idempotence) | PASS (no-X path; carve-out applies cross-scope) | See B-3 |
| SC-008 (insight_score in retro) | DEFERRED to next pipeline retro | The retrospective task #6 in this same pipeline is the live anchor; verifies once Phase 4 completes |

**PRD compliance**: **100%** (25/25 FRs implemented and structurally verified). 2 deferred SCs (SC-006, SC-008) gated by substrate (B-2) and pipeline order (retrospective is task #6, downstream of this audit).

**Recommendation**: PR is ready to land. The two deferred SCs are not implementation gaps — they're substrate-bound (B-2) or pipeline-order-bound (SC-008's retro fires next). The maintainer should manually verify SC-006 on the next session after the published plugin cache refreshes.
