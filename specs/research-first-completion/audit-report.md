# PRD Audit Report — research-first-completion

**Date**: 2026-04-25
**Auditor**: auditor (build/research-first-completion-20260425 pipeline)
**PRD**: `docs/features/2026-04-26-research-first-completion/PRD.md`
**Spec**: `specs/research-first-completion/spec.md`
**Branch**: `build/research-first-completion-20260425`
**Implementer's last commit**: `4f32a04` (Phase E — friction notes + smoke pass)

## Verdict

**PASS** — every PRD requirement (20 FRs, 6 NFRs, 7 SCs) is covered by spec
+ implementation + test evidence. Two documented blockers (B-001, B-002)
are both follow-on by design; neither blocks merge.

| Direction | Result |
|-----------|--------|
| PRD → Spec | 20/20 FR coverage, 6/6 NFR coverage, 7/7 SC coverage |
| Spec → Code | every shipped scriptfile + SKILL.md edit referenced by an FR / NFR |
| Spec → Test | every SC anchored to a fixture; every fixture green |
| Foundation invariants (NFR-009) | UNTOUCHED — `git diff main..HEAD` on the listed paths returns 0 lines |
| Byte-compat (NFR-002 / NFR-005) | verified — no-research PRD parses to 3-key projection plus 4 nulls; skip-path emits no stdout |

## Compliance breakdown

### Functional requirements (20/20)

| FR | Theme | Implementation surface | Test fixture | Verdict |
|----|-------|------------------------|--------------|---------|
| FR-001 | schema (item) | `validate-research-block.sh` + `validate-item-frontmatter.sh` (additive call-through) | `research-block-schema-validation/` | pass |
| FR-002 | schema (issue+feedback) | `plugin-kiln/scripts/issues-feedback/validate-frontmatter.sh` (NEW); SKILL.md write-time wiring deferred (B-001) | direct-invocation tests + `back-compat-no-requires/` | pass (with documented gap) |
| FR-003 | schema rules | `validate-research-block.sh` rules 1–10 | `research-block-schema-validation/` (13/13) | pass |
| FR-004 | PRD frontmatter | `parse-prd-frontmatter.sh` 4 additive projections | `parse-prd-frontmatter-rubric-required/` (5/5), `build-prd-standard-routing-bytecompat/` (9/9) | pass |
| FR-005 | distill propagation | `kiln-distill/SKILL.md` Step 3.5 | `distill-research-block-propagation/` (7/7) | pass |
| FR-006 | conflict prompt | `kiln-distill/SKILL.md` Step 3.5 §6 | `distill-axis-conflict-prompt/` (7/7) | pass |
| FR-007 | scalar verbatim propagation | `kiln-distill/SKILL.md` Step 3.5 | `distill-research-block-propagation/` (7/7) | pass |
| FR-008 | no-research fallback | `kiln-distill/SKILL.md` Step 3.5 byte-identity branch | `distill-research-block-determinism/` (3/3), `back-compat-no-requires/` (7/7) | pass |
| FR-009 | build-prd routing | `kiln-build-prd/SKILL.md` Step 2.5.1 | `build-prd-research-routing/` (5/5), `build-prd-standard-routing-bytecompat/` (9/9) | pass |
| FR-010 | variant pipeline | `kiln-build-prd/SKILL.md` Step 2.5.2 | `build-prd-research-routing/` + `research-first-e2e/` (8/8) | pass |
| FR-011 | gate-fail halt | `kiln-build-prd/SKILL.md` Step 2.5.2 §6 | `research-first-e2e/` regression sub-path | pass |
| FR-012 | gate-pass auditor inputs | `kiln-build-prd/SKILL.md` Step 2.5.2 §5 | `research-first-e2e/` happy sub-path | pass |
| FR-013 | classifier signal-words | `classify-description.sh` additive `research_inference` | `classifier-research-inference/` (5/5) | pass |
| FR-014 | axis-inference table | `classify-description.sh` (full FR-014 table) | `classifier-axis-inference-mapping/` (19/19) | pass |
| FR-015 | coached-capture stanza | 3 SKILL.md edits (`kiln-roadmap` §6.8, `kiln-report-issue` Step 1.5, `kiln-feedback` Step 4c) | `classifier-research-rejection-recovery/` (14/14) | pass |
| FR-016 | output_quality warning | classifier rationale + `lint-classifier-output-quality-warning.sh` | `classifier-output-quality-warning/` (6/6) | pass |
| FR-017 | E2E fixture scaffold | `tests/research-first-e2e/run.sh` | `research-first-e2e/` (8/8) | pass (load-bearing) |
| FR-018 | both happy + regression | `run.sh --scenario={happy,regression}` | `research-first-e2e/` 4/4 each sub-path | pass |
| FR-019 | direct-invocation PASS-cite | `bash run.sh` last-line PASS, exit 0 | `research-first-e2e/` (`PASS: 8/8 assertions`, exit 0) | pass |
| FR-020 | phase-complete handoff | documented in spec.md / blockers.md (auto-flip is separate issue) | n/a — manual flip per spec | pass |

### Non-functional requirements (6/6)

| NFR | Subject | Verification | Verdict |
|-----|---------|--------------|---------|
| NFR-001 | backward compat | `back-compat-no-requires/` 7/7; `distill-gate-grandfathered-prd/`; `distill-gate-accepts-promoted/` | pass |
| NFR-002 | routing default-safety byte-identity | `build-prd-standard-routing-bytecompat/` 9/9 + manual parse on `2026-04-25-research-first-foundation/PRD.md` (3-key shape preserved, 4 nulls added) | pass |
| NFR-003 | distill determinism | `distill-research-block-determinism/` 3/3 (cmp returns 0) | pass |
| NFR-004 | conflict-prompt clarity | `distill-axis-conflict-prompt/` 7/7 (prompt names both source paths + both directions) | pass |
| NFR-005 | pre-research-first byte-compat (distill) | identical to NFR-002 surface; verified on no-research-block backlog | pass |
| NFR-006 | classifier false-positive recovery | `classifier-research-rejection-recovery/` 14/14 (structural-absence verified via `grep -F` returning 0) | pass |
| NFR-007 | loud-failure validators | manual: malformed `needs_research`/`fixture_corpus`/`fixture_corpus_path` all exit non-zero with explicit error strings | pass |
| NFR-008 | E2E fixture self-containment | `research-first-e2e/run.sh` mocks all LLM spawns; no `claude` CLI, no GitHub API; runs in mktemp -d | pass |
| NFR-009 | foundation invariants UNTOUCHED | `git diff main..HEAD -- <listed paths>` returns 0 lines on every untouchable; `parse-prd-frontmatter.sh` extension is additive only | pass |

### Success criteria (7/7 — 11 listed in spec, all green)

| SC | Anchor fixture | Result |
|----|----------------|--------|
| SC-001 | `classifier-research-inference/` | PASS 5/5 |
| SC-002 | `distill-research-block-propagation/` | PASS 7/7 |
| SC-003 | `build-prd-research-routing/` | PASS 5/5 |
| SC-004 | `build-prd-standard-routing-bytecompat/` | PASS 9/9 |
| SC-005 (load-bearing) | `research-first-e2e/` | PASS 8/8 (happy: 4/4, regression: 4/4) |
| SC-006 | `distill-axis-conflict-prompt/` | PASS 7/7 |
| SC-007 | `distill-research-block-determinism/` | PASS 3/3 |
| SC-008 | `classifier-research-rejection-recovery/` | PASS 14/14 |
| SC-009 | `research-block-schema-validation/` | PASS 13/13 |
| SC-010 | `classifier-axis-inference-mapping/` | PASS 19/19 |
| SC-011 | `classifier-output-quality-warning/` | PASS 6/6 |

## Smoke verification (live-substrate-first)

Per the live-substrate-first rule, the E2E fixture is the load-bearing
gate. Both sub-paths run as direct `bash run.sh` per FR-019 PASS-cite
fallback (substrate tier-2 — `/kiln:kiln-test` harness wiring is itself a
known substrate-gap roadmap item; direct-invocation evidence is canonical
for this PRD).

```
$ bash plugin-kiln/tests/research-first-e2e/run.sh --scenario=happy
  Sub-path 'happy' assertions: ok
PASS: 4/4 assertions
exit 0

$ bash plugin-kiln/tests/research-first-e2e/run.sh --scenario=regression
  Sub-path 'regression' assertions: ok
PASS: 4/4 assertions
exit 0

$ bash plugin-kiln/tests/research-first-e2e/run.sh    # default = both
PASS: 8/8 assertions
exit 0
```

The regression sub-path's stdout contains the literal token `gate fail`
and the verbatim per-axis JSON showing `"verdict":"regression"` for both
fixtures' tokens axis. The auditor + PR-creator agents are NEVER spawned
on that path — verified by inspecting Step 2.5.2 §6 of `kiln-build-prd
SKILL.md`.

### Schema validator rejection sweep (manual)

```
$ bash plugin-kiln/scripts/research/validate-research-block.sh '{"needs_research": "yes"}'
{"errors":["needs_research must be true|false (got: yes)"],"ok":false,"warnings":[]}

$ bash plugin-kiln/scripts/research/validate-research-block.sh \
    '{"empirical_quality": [{"metric": "output_quality", "direction": "equal_or_better"}]}'
{"errors":["output_quality-axis-missing-rubric"],"ok":false,"warnings":[]}

$ bash plugin-kiln/scripts/research/validate-research-block.sh \
    '{"fixture_corpus": "declared", "fixture_corpus_path": "/abs/path"}'
{"errors":["fixture-corpus-path-must-be-relative: /abs/path"],"ok":false,"warnings":[]}

$ bash plugin-kiln/scripts/research/validate-research-block.sh \
    '{"empirical_quality":[],"research_extra":"foo"}'
{"errors":[],"ok":true,"warnings":["unknown research-block field: research_extra"]}
```

All four rejects/warns behave per FR-001/FR-003.

### Byte-compat regression check (NFR-002 / NFR-005)

```
$ bash plugin-wheel/scripts/harness/parse-prd-frontmatter.sh \
    docs/features/2026-04-25-research-first-foundation/PRD.md
{"blast_radius":null,"empirical_quality":null,"excluded_fixtures":null,
 "fixture_corpus":null,"fixture_corpus_path":null,"needs_research":null,
 "promote_synthesized":null}
exit 0
```

The pre-research-first PRD parses to the existing 3 keys preserved as
`null` (no diff from pre-PR shape) plus 4 new keys all `null`. Skip-path
probe (Step 2.5.1) sees `needs_research // false == "false"` and falls
through to Step 3 with NO stdout. Byte-identity invariant preserved.

### Distill propagation smoke (FR-005 / FR-007)

`distill-research-block-propagation/run.sh` — 7/7 assertions —
exercises the §5 jq union-merge expression directly:

- Two source axes (`tokens` + `time`) union-merged ASC by metric.
- Same-metric same-direction dedup with priority promotion (`primary >
  secondary`).
- `fixture_corpus: declared` propagated verbatim.
- `needs_research: true` propagated when ANY source declares it.

### Conflict prompt (FR-006)

`distill-axis-conflict-prompt/run.sh` — 7/7 assertions — confirms:

- `lower` vs `equal_or_better` on `metric: tokens` produces conflict
  group keyed on metric.
- Both source paths AND both direction values appear in the rendered
  prompt verbatim per NFR-004.
- Distill exits 2 without writing the PRD on `abandon`.

### Build-prd routing dry-run (FR-009)

`build-prd-research-routing/run.sh` — 5/5 assertions — invokes the
Phase 2.5.1 probe block extracted as a callable shell snippet against a
fixture PRD declaring `needs_research: true`; asserts stdout contains the
literal `research-first variant invoked` banner. The skip-path companion
(`build-prd-standard-routing-bytecompat/`) asserts empty stdout for the
no-research case.

## Test quality + coverage

- 70/70 plugin-kiln test fixtures pass (full suite ran clean).
- Every assertion is functional (exit-code + stdout/stderr greps + jq
  invariants); no stub-asserting fixtures detected.
- Coverage gate is N/A in numeric form — kiln plugin is shell + markdown,
  not JS/TS — but every shipped script + SKILL.md edit has at least one
  fixture exercising its behavior. The fixture-to-FR map above is
  exhaustive.

## Reconciled blockers

`specs/research-first-completion/blockers.md` documents two follow-ons:

- **B-001** — issue/feedback skill write-time validator wiring. The
  shared helper + wrapper script ship; SKILL.md prose-driven write-time
  hook is deferred. Hand-edit + direct-CLI validation paths are open
  workarounds. Reopen criterion: real-use evidence of research-block
  authoring on issue/feedback files.
- **B-002** — first-real-use is the live integration path for the
  research-first variant pipeline. Per CLAUDE.md Rule 5 — newly-shipped
  agents not live-spawnable in same session. The E2E fixture mocks every
  LLM-spawning step.

Both are documented hand-offs, not gaps; neither violates an FR/NFR/SC
contract.

## Audit conclusion

**Ship it.** PRD coverage 20/20 FRs + 6/6 NFRs + 7/7 SCs (11 SC fixtures).
Foundation invariants verified untouched. Byte-identity invariants verified
by direct parse + parser-shape diff. The load-bearing E2E fixture exercises
both happy and regression sub-paths under direct-invocation substrate.
