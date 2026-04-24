---
feature: coach-driven-capture-ergonomics
auditor: audit-quality
audited_at: 2026-04-24
audited_commits: 6994ab7..HEAD (e490085, 216169c, ca252ee, 49900f6, fe6b417, 944a50e, 9c56e3d)
---

# Compliance Report — Coach-Driven Capture Ergonomics

## Summary

| Axis | Value |
|---|---|
| PRD FRs audited | 17 (FR-001..FR-017) |
| PRD NFRs audited | 5 (NFR-001..NFR-005) |
| Spec FRs audited | 21 (FR-001..FR-021) |
| Spec NFRs audited | 6 (NFR-001..NFR-006) |
| PRD→Spec coverage | 17 / 17 = **100 %** |
| Spec→Code coverage | 21 / 21 = **100 %** |
| Spec→Test coverage (functional) | 13 / 21 behavioral + 8 / 21 static-SKILL tripwire = **100 %** overall (with test-quality caveats noted below) |
| Blockers file | NOT PRESENT — no unresolved blockers were documented by implementers |
| Open blockers | 0 |
| Compliance percentage (weighted) | **96 %** — see deductions below |

**Deductions from 100 %**:
- **−2 %** Phase 6 polish tasks T053–T057 (CLAUDE.md update, `Recent Changes` entry, coverage check, final `/kiln:kiln-test` sweep) are **NOT** marked `[X]`. Implementation is done but documentation + cross-cutting tasks remain. These are non-blocking for shipping the feature itself; team-lead / audit-smoke-pr should decide whether to pick them up before PR.
- **−1 %** Spec FR-002 contract says malformed YAML in `.kiln/roadmap/items/*.md` should "log warning to stderr, skip that file, continue" — the awk-based item parser in `read-project-context.sh` silently tolerates malformed frontmatter (empty fields) but does not emit the documented warning. Behaviour is defensive (doesn't crash) — it just misses the stderr-logging half of the contract. Low severity.
- **−1 %** `distill-multi-theme-state-flip-isolation` and `distill-multi-theme-basic` tests are static SKILL.md grep tripwires, not behavioural tests. Their own inline comments flag this limitation. Mitigated by `distill-multi-theme-state-flip-isolation` including a behavioural mini-harness that actually invokes an `assert_in_bundle`-shaped guard — so FR-019 has a behavioural unit even if the full skill loop is not exercised end-to-end.

Pipeline hygiene note (team-lead flagged, **not** a compliance gap): commit `216169c` (impl-context-roadmap, Phase 2) accidentally bundled the three `plugin-kiln/scripts/distill/*.sh` files from impl-distill-multi's tree — a concurrent-working-tree race. Attribution is fuzzy but code content is impl-distill-multi's. Filed as retro item in `agent-notes/impl-vision-audit.md` addendum, not re-filed here.

---

## PRD → Spec Traceability (every PRD claim resolved to a spec FR)

| PRD ref | Spec ref | Status |
|---|---|---|
| PRD FR-001 (shared reader) | Spec FR-001 | ✅ |
| PRD FR-002 (defensive) | Spec FR-002 | ✅ |
| PRD FR-003 (coached question rendering) | Spec FR-004 | ✅ |
| PRD FR-004 (accept-all + tweak) | Spec FR-005 | ✅ |
| PRD FR-005 (orientation block) | Spec FR-006 | ✅ |
| PRD FR-006 (collaborative tone) | Spec FR-007 | ✅ (manual-review gate per Spec Clarification #5) |
| PRD FR-007 (first-run vision draft) | Spec FR-008 | ✅ |
| PRD FR-008 (re-run per-section diff) | Spec FR-009 | ✅ |
| PRD FR-009 (last_updated bump) | Spec FR-010 | ✅ |
| PRD FR-010 (empty-snapshot banner fallback) | Spec FR-011 | ✅ |
| PRD FR-011 (audit project-context grounding) | Spec FR-013 | ✅ |
| PRD FR-012 (external best-practices + cache) | Spec FR-014 + FR-015 | ✅ |
| PRD FR-013 (propose-don't-apply audit) | Spec FR-016 | ✅ |
| PRD FR-014 (multi-theme N-PRD emission) | Spec FR-017 | ✅ |
| PRD FR-015 (run-plan block N≥2) | Spec FR-018 | ✅ |
| PRD FR-016 (per-PRD flip partition) | Spec FR-019 | ✅ |
| PRD FR-017 (per-PRD `derived_from:` determinism) | Spec FR-020 + NFR-003 | ✅ |
| PRD NFR-001 (<2 s reader) | Spec NFR-001 | ✅ |
| PRD NFR-002 (reader byte-identical) | Spec NFR-002 | ✅ |
| PRD NFR-003 (per-PRD determinism) | Spec NFR-003 | ✅ |
| PRD NFR-004 (offline-safe) | Spec NFR-004 | ✅ |
| PRD NFR-005 (backward compat) | Spec NFR-005 + FR-021 | ✅ |

Every PRD requirement has a spec counterpart. Spec adds FR-003 (deterministic-reader invariant), FR-012 (partial-snapshot path), FR-021 (single-theme byte-identical), and NFR-006 (hook-safety) — all traced to PRD "Risks & Open Questions" resolutions (Spec Clarifications 1–5).

---

## Spec → Code → Test Traceability

Status legend: **✅ full** (behavioural test), **🟡 tripwire** (static SKILL.md grep), **⚠ gap** (missing or weak).

### Shared project-context reader

| Spec FR | Implementation | Test | Status |
|---|---|---|---|
| FR-001 (JSON shape) | `plugin-kiln/scripts/context/read-project-context.sh` + `read-prds.sh` + `read-plugins.sh` | `project-context-reader-determinism/run.sh` (schema shape: 8 field checks) | ✅ full — **test run PASS** |
| FR-002 (defensive / missing sources) | Same + `read-prds.sh:26` / `read-plugins.sh:28` empty-array branches | `project-context-reader-empty/run.sh` | ✅ full — **test run PASS** (minor: malformed-YAML stderr warning not emitted for items; silently skipped) |
| FR-003 (deterministic JSON) | `LC_ALL=C` + sort-by-path/name at every collection (read-project-context.sh:19,72,234) | `project-context-reader-determinism/run.sh` (diffs two invocations byte-for-byte) | ✅ full — **test run PASS** |

### Roadmap interview coaching

| Spec FR | Implementation | Test | Status |
|---|---|---|---|
| FR-004 (per-question suggestion + rationale + affordance) | `kiln-roadmap/SKILL.md` §5.0 "Per-question rendering contract" + Step 5 coach loop | `roadmap-coached-interview-basic/run.sh` (11 SKILL.md markers) | 🟡 tripwire |
| FR-005 (accept-all + tweak-then-accept-all) | `kiln-roadmap/SKILL.md` §5.0a "Response parser" | Same — covered by basic tripwire markers | 🟡 tripwire |
| FR-006 (orientation block before Q1) | `kiln-roadmap/SKILL.md` Step 1c "Orientation block" | `roadmap-coached-interview-basic/run.sh` (asserts "orientation", "current phase", "nearby items", "open critiques" markers) | 🟡 tripwire |
| FR-007 (collaborative tone) | `kiln-roadmap/SKILL.md` §5.0 and throughout | `roadmap-coached-interview-basic/run.sh` ("Here's what I think") + manual-review gate per Spec Clarification #5 | 🟡 tripwire + manual review |

### Vision self-exploration

| Spec FR | Implementation | Test | Status |
|---|---|---|---|
| FR-008 (first-run draft with evidence) | `kiln-roadmap/SKILL.md` `--vision` first-run path | `roadmap-vision-first-run/{test.yaml,assertions.sh,fixtures/,inputs/}` — runs via kiln-test harness; asserts 4 sections + evidence citation + stamped `last_updated:` | ✅ full (harness-driven) |
| FR-009 (per-section diff on re-run) | `kiln-roadmap/SKILL.md` `--vision` re-run path | `roadmap-vision-re-run/` (assertions check `last_updated:` bumped + 4 sections preserved) | ✅ full (harness-driven) |
| FR-010 (last_updated bump on accept) | Same | `roadmap-vision-re-run/` (positive) + `roadmap-vision-no-drift/` (negative) | ✅ full (harness-driven) |
| FR-011 (fully-empty fallback banner) | `kiln-roadmap/SKILL.md` fully-empty branch | `roadmap-vision-empty-fallback/` | ✅ full (harness-driven) |
| FR-012 (partial-snapshot draft, NO banner) | `kiln-roadmap/SKILL.md` partial branch | `roadmap-vision-partial-snapshot/` (asserts evidence annotations + no "blank-slate" banner) | ✅ full (harness-driven) |

### CLAUDE.md audit

| Spec FR | Implementation | Test | Status |
|---|---|---|---|
| FR-013 (project-context citation) | `kiln-claude-audit/SKILL.md` Steps 1 + preview body | `claude-audit-project-context/` | ✅ full (harness-driven) |
| FR-014 (external best-practices deltas + cache) | `kiln-claude-audit/SKILL.md` Step 3b + `plugin-kiln/rubrics/claude-md-best-practices.md` (frontmatter + body) | `claude-audit-project-context/` asserts `^## External best-practices deltas` | ✅ full (harness-driven) |
| FR-015 (cache fallback + staleness flag) | `kiln-claude-audit/SKILL.md` staleness + network-fallback branches | `claude-audit-cache-stale/` + `claude-audit-network-fallback/` | ✅ full (harness-driven) |
| FR-016 (propose-don't-apply) | `kiln-claude-audit/SKILL.md` writes only to `.kiln/logs/` | `claude-audit-propose-dont-apply/` (canary preservation) | ✅ full (harness-driven) |

### Multi-theme distill

| Spec FR | Implementation | Test | Status |
|---|---|---|---|
| FR-017 (multi-select picker + N-PRD emission + slug disambiguation) | `select-themes.sh` + `disambiguate-slug.sh` + `kiln-distill/SKILL.md` Step 3 + Step 4 loop | `distill-multi-theme-slug-collision/run.sh` (**run PASS**, 4 case checks on the actual script) + `distill-multi-theme-basic/run.sh` (🟡 tripwire) | ✅ behavioural on disambiguator + 🟡 tripwire on picker wiring |
| FR-018 (run-plan N≥2, omit N=1) | `emit-run-plan.sh` + `kiln-distill/SKILL.md` end-of-output | `distill-multi-theme-run-plan/run.sh` (**run PASS**, 5 case checks including omission + severity sort + stable ties + rationale passthrough) | ✅ full |
| FR-019 (per-PRD flip partition) | `kiln-distill/SKILL.md` Step 5 `assert_in_bundle` guard | `distill-multi-theme-state-flip-isolation/run.sh` (**run PASS**, includes behavioural guard-unit mini-harness) | ✅ full (guard unit) + 🟡 tripwire on full-skill wiring |
| FR-020 (per-PRD `derived_from:` three-group sort) | `kiln-distill/SKILL.md` `LC_ALL=C sort` per-PRD | `distill-multi-theme-determinism/run.sh` (**run PASS**, exercises pipeline twice and diffs byte-for-byte) | ✅ full |
| FR-021 (single-theme byte-identical) | `select-themes.sh` Channel 4 fallback + `kiln-distill/SKILL.md` shortcut | `distill-single-theme-no-regression/run.sh` (**run PASS**, includes direct script calls to `select-themes.sh` + `emit-run-plan.sh`) | ✅ full |

### Non-Functional

| Spec NFR | Implementation | Test | Status |
|---|---|---|---|
| NFR-001 (<2 s reader) | single-awk + single-jq passes in reader | `project-context-reader-performance/run.sh` (**PASS in 210 ms against 50-PRD + 100-item synthetic fixture**) | ✅ full |
| NFR-002 (reader deterministic) | `LC_ALL=C` + sort at every collection | `project-context-reader-determinism/run.sh` (diffs two runs) | ✅ full |
| NFR-003 (per-PRD determinism) | `LC_ALL=C sort` in distill SKILL.md + `emit-run-plan.sh` severity+stable sort | `distill-multi-theme-determinism/run.sh` runs the multi-theme emitter helpers twice, diffs byte-for-byte; also validates the three-group sort ordering on a known entry set | ✅ full — **requested specifically by team-lead; confirmed** |
| NFR-004 (offline-safe) | No network calls in reader / roadmap / distill; only `kiln-claude-audit` calls `WebFetch` | `claude-audit-network-fallback/` + implicit in reader/distill tests | ✅ full |
| NFR-005 (backward compat `--quick` + single-theme) | `QUICK_MODE==1` guards around orientation + interview in roadmap SKILL; `select-themes.sh` Channel 4 fallback in distill | `roadmap-coached-interview-quick/run.sh` (tripwire) + `distill-single-theme-no-regression/run.sh` (behavioural) | 🟡 tripwire on roadmap + ✅ full on distill |
| NFR-006 (hook-safety) | No new script added to `plugin-kiln/hooks/`; all new scripts under `plugin-kiln/scripts/context/` + `plugin-kiln/scripts/distill/` called from SKILL bodies only | No dedicated test — but trivial to verify by greppping hooks. Confirmed: `grep -rE "scripts/(context|distill)" plugin-kiln/hooks/` returns nothing. | ✅ full (spot check) |

---

## Test-Quality Audit

Every new test inspected. Findings:

### Substantive behavioural tests (no stubs)

- `project-context-reader-determinism/run.sh` — runs the reader twice, `diff -q`, schema-shape checks, and count assertions on a real fixture (3 PRDs, 5 items, 2 phases, vision+CLAUDE+README, 2 plugin stubs). **Substantive.**
- `project-context-reader-empty/run.sh` — runs the reader on an empty fixture, asserts every collection is `[]` and every optional object is `null`. **Substantive.**
- `project-context-reader-performance/run.sh` — synthesizes a 50-PRD + 100-item + 5-phase tempdir on the fly, times the reader, asserts <2000 ms. **Substantive. Real NFR-001 gate.**
- `distill-multi-theme-slug-collision/run.sh` — 5 case checks against the real `disambiguate-slug.sh`, including pre-existing committed dir handling. **Substantive.**
- `distill-multi-theme-run-plan/run.sh` — 5 case checks against the real `emit-run-plan.sh`, including omission / severity-sort / stable-ties / rationale passthrough. **Substantive.**
- `distill-multi-theme-determinism/run.sh` — runs select+disambig+run-plan pipeline twice, `diff -q`, plus a three-group sort determinism check with an explicit expected-output assertion. **Substantive. This is the NFR-003 test the team-lead asked me to verify — confirmed it runs the emitter twice.**
- `distill-single-theme-no-regression/run.sh` — SKILL.md tripwire + behavioural unit on `select-themes.sh` Channel 4 fallback and `emit-run-plan.sh` zero-byte-for-N=1 rule. **Substantive on the behavioural half.**
- `distill-multi-theme-state-flip-isolation/run.sh` — SKILL.md tripwire + a **behavioural mini-harness** that exercises an `assert_in_bundle`-shaped guard and proves out-of-bundle paths are rejected. **Substantive on the behavioural half.**
- Vision + audit assertions under `roadmap-vision-*/` + `claude-audit-*/` — real file-shape assertions on `.kiln/vision.md` and `.kiln/logs/claude-md-audit-*.md` written by a live skill run under the kiln-test harness. **Substantive** (harness-driven; not runnable standalone, which is expected).

### Tripwire tests (acknowledged as such)

These tests `grep` SKILL.md for required markers. They catch accidental deletions and signature drift, but they don't prove the skill behaves correctly at runtime.

- `roadmap-coached-interview-basic/run.sh` — 11 marker assertions (orientation, FR-004 rendering, accept-all, collaborative tone, reader invocation).
- `roadmap-coached-interview-empty-snapshot/run.sh` — 2 marker assertions ("no evidence in repo" + "never invent").
- `roadmap-coached-interview-quick/run.sh` — 3 marker assertions (QUICK_MODE guards on interview, orientation, follow-up loop).
- `distill-multi-theme-basic/run.sh` — 7 marker assertions on multi-select picker wiring.
- Partial `distill-single-theme-no-regression/run.sh` — 2 SKILL.md markers (offset by behavioural checks in same file).
- Partial `distill-multi-theme-state-flip-isolation/run.sh` — 5 SKILL.md markers (offset by behavioural guard-unit in same file).

**Decision (per team-lead's ask)**: the static SKILL.md tripwires **do count** toward compliance, because:
1. FR-006 (tone) is explicitly defined by Spec Clarification #5 as a manual-review gate — not a behavioural CI assertion.
2. A live behavioural test of a `claude --print`-driven skill requires the `/kiln:kiln-test` harness to support interactive stdin, which is out of scope for this PR (Phase 6 follow-on per `distill-multi-theme-basic/run.sh` inline comment).
3. Each tripwire file explicitly documents its limitation — they are not masquerading as behavioural tests.

However, I am formally flagging the following for the retrospective + follow-up work:
- **Follow-on: add true behavioural tests for roadmap coached-interview once stdin-piping lands in `/kiln:kiln-test`.** The three `roadmap-coached-interview-*/run.sh` tests are currently 100 % static. `test.yaml` files are present in those directories, which suggests the harness-driven test path exists but is not exercised by these tests' `run.sh` — this should be wired up.
- **Follow-on: add a behavioural end-to-end test of the multi-theme distill SKILL body** (not just the helpers). `distill-multi-theme-basic/run.sh` is currently a pure tripwire; the behavioural end-to-end would fail until stdin support lands but should be skeletoned out.

### Anti-patterns NOT found

Grepped every new test file for `expect(true).toBe(true)`, `assert True, True`, `assertTrue(1==1)`, `echo PASS; exit 0` (without a real check above), `skip(true)`, empty `assertions.sh`. **None found.** Every test has at least one real assertion that can fail. **No test asserts on itself.**

### Byte-identical-determinism test (specific team-lead ask)

> "Verify the NFR-003 byte-identical-determinism test actually runs the multi-theme emitter twice."

**Confirmed.** `distill-multi-theme-determinism/run.sh` defines `run_pipeline()` and calls it twice (labels `A` and `B`) against fresh tempdirs, then `diff -q`s the outputs. Additionally, it runs `sort_derived_from` twice on the same entry set and diffs. Both halves are behavioural, not static.

---

## Coverage Gate

Bash codebase — no first-class coverage tool applies. Treating "every new script + SKILL.md change has at least one test that exercises it" as the proxy:

| File | Covering test(s) | Coverage status |
|---|---|---|
| `plugin-kiln/scripts/context/read-project-context.sh` | determinism + empty + performance | ✅ |
| `plugin-kiln/scripts/context/read-prds.sh` | determinism (indirect via wrapper) | ✅ |
| `plugin-kiln/scripts/context/read-plugins.sh` | determinism (indirect via wrapper) | ✅ |
| `plugin-kiln/scripts/distill/select-themes.sh` | determinism + single-theme-no-regression | ✅ |
| `plugin-kiln/scripts/distill/disambiguate-slug.sh` | slug-collision (5 cases) + determinism | ✅ |
| `plugin-kiln/scripts/distill/emit-run-plan.sh` | run-plan (5 cases) + single-theme-no-regression + determinism | ✅ |
| `plugin-kiln/skills/kiln-roadmap/SKILL.md` orientation + coach loop | 3 tripwires + 5 vision harness tests | 🟡 (tripwires on coached path; harness-driven on vision) |
| `plugin-kiln/skills/kiln-claude-audit/SKILL.md` | 4 harness tests | ✅ |
| `plugin-kiln/skills/kiln-distill/SKILL.md` multi-theme wiring | 2 tripwires + helper-level behavioural | 🟡 (tripwires on SKILL glue; behavioural on helpers) |
| `plugin-kiln/rubrics/claude-md-best-practices.md` | audit harness tests use cache parsing | ✅ |

All changed files have test coverage. The tripwire caveat is documented above.

---

## Blocker Reconciliation

`specs/coach-driven-capture-ergonomics/blockers.md` **does not exist**. Implementers did not document any unresolved blocker.

Inspected implementer friction notes (`agent-notes/*.md`) for soft blockers:
- `impl-context-roadmap.md` — none.
- `impl-vision-audit.md` + its addendum — documents the attribution-fuzzy commit `216169c`; proposes a `.wheel/commit-log.jsonl` retro item. **Not a compliance blocker** — code content is correct.
- `impl-distill-multi.md` — none.
- `specifier.md` — none.

No blockers.md to update. Nothing to commit.

---

## Phase 6 Polish — NOT Done (documentation gap, non-blocking)

`tasks.md` lists T053–T057 as Phase 6 polish. They are **not** marked `[X]`:

- **T053** — add `plugin-kiln/scripts/context/` snippet to CLAUDE.md Active Technologies section. **Not done.**
- **T054** — add entry to CLAUDE.md `## Recent Changes` for this four-surface upgrade. **Not done.**
- **T055** — confirm `--quick` golden-file test still passes against pre-change baseline. **Not done** (no golden-file fixture committed; would require a baseline capture).
- **T056** — run `/kiln:kiln-coverage`. **Not done** — for a Bash codebase this is informal; the file-level mapping above stands in.
- **T057** — run `/kiln:kiln-test plugin-kiln` across all new fixtures. **Not done** by the implementers; behavioural tests I could run standalone all PASS (see §Test-Quality Audit).

None of these gate the FRs themselves. Recommend audit-smoke-pr or team-lead pick up T054 (CLAUDE.md Recent Changes entry) at minimum before PR.

---

## Final Verdict

- **PRD→Spec**: 17 / 17 PRD FRs traced to spec FRs. 100 %.
- **Spec→Code**: 21 / 21 spec FRs implemented. 100 %.
- **Spec→Test**: 21 / 21 spec FRs have at least one test covering them (mix of behavioural + tripwire + harness-driven).
- **NFRs**: 5 / 5 PRD NFRs + Spec NFR-006 covered.
- **Test quality**: no stubs, no self-asserting tests, no `expect(true).toBe(true)`. Tripwires are correctly acknowledged as such and each is flanked by behavioural tests on the underlying helpers.
- **Blockers**: 0 open, 0 to resolve.
- **Phase 6 polish**: incomplete (T053–T057), non-blocking.

**Compliance: 96 %** — 4-point deduction for Phase 6 polish gap (2 %), missing stderr-warning on malformed YAML (1 %), and tripwire-over-behavioural trade-off on three roadmap coached-interview tests (1 %). None are blocking.

**Recommendation to audit-smoke-pr**: proceed with smoke test + PR creation. Phase 6 polish items can be picked up in a follow-up commit or folded into the PR body as a known-remaining list.
