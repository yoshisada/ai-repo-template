# Smoke Test — research-first-completion (PR #184)

**Date**: 2026-04-25
**Scope**: 2 (schema validators + distill propagation + build-prd routing)
**Verdict**: ✅ ALL PASS — 18 tests across 4 surfaces

## Schema validator (`validate-research-block.sh`) — 7 cases

| # | Case | Expected | Actual |
|---|------|----------|--------|
| 1 | No research block (backward compat) | ok=true | ok=true ✅ |
| 2 | Valid research block | ok=true | ok=true ✅ |
| 3 | `output_quality` without `rubric` | FAIL | `output_quality-axis-missing-rubric` ✅ |
| 4 | `output_quality` WITH `rubric` | PASS | ok=true ✅ |
| 5 | `fixture_corpus: declared` without path | FAIL | `fixture-corpus-path-required-when-declared-or-promoted` ✅ |
| 6 | Invalid metric | FAIL | `unknown metric: bogus (allowed: accuracy\|tokens\|time\|cost\|output_quality)` ✅ |
| 7 | Invalid direction | FAIL | `unknown direction: sideways (allowed: lower\|higher\|equal_or_better)` ✅ |

Bonus: validator emits actionable warning when `needs_research:true` is set without `fixture_corpus` (the variant pipeline would bail at corpus-load).

## Distill propagation (`parse-research-block.sh`) — 1 case

Test 8: synthesize a fake item with `needs_research: true` + tokens + cost axes + `fixture_corpus: declared` (inline-flow shape per V1 parser limit), parse to JSON, validate → ok=true.

```
{"empirical_quality":[{"direction":"lower","metric":"tokens","priority":"primary"},{"direction":"lower","metric":"cost","priority":"primary"}],"excluded_fixtures":null,"fixture_corpus":"declared","fixture_corpus_path":"plugin-kiln/fixtures/claude-md-audit/corpus","needs_research":true,"promote_synthesized":null}
```

Parser output is **deterministic alphabetical key order** (NFR-003 byte-identity hook).

**V1 parser limit (documented):** only inline-flow `[...]` shape supported for `empirical_quality:`. Block-sequence form fails loudly with `Bail out! parse error: only inline-flow shape [...] supported in v1`. Captured in implementer's friction note. Worth a follow-on PR but not blocking.

## Build-prd routing (`probe-plan-time-agents.sh`) — 4 cases

| # | PRD declares | Expected | Actual |
|---|-------------|----------|--------|
| Test 9 | `fixture_corpus: synthesized` | `synthesizer` | `synthesizer` ✅ |
| Test 10 | `output_quality` axis | `judge` | `judge` ✅ |
| Test 11 | both synthesized + output_quality | `both` | `both` ✅ |
| Test 12a | `needs_research: true` (parse) | `true` | `true` ✅ |
| Test 12b | no research block (parse) | `null` | `null` ✅ |

## FR-006 conflict detection (jq expression from distill SKILL.md) — 3 cases

| # | Sources | Expected | Actual |
|---|---------|----------|--------|
| Test 13 | 2 sources, same `metric: tokens`, different `direction` (`lower` vs `equal_or_better`) | conflicts detected | both axes returned in conflict array ✅ |
| Test 14 | 2 sources, same metric + same direction | no conflict | `[]` ✅ |
| Test 15 | 2 sources, different metrics | no conflict | `[]` ✅ |

## Lint scripts — 4 cases

| # | Script | Outcome |
|---|--------|---------|
| Test 16 | `lint-judge-prompt.sh` (FR-011 verbatim-rubric) | exit 0 ✅ |
| Test 17 | `lint-synthesizer-prompt.sh` | exit 0 ✅ |
| Test 18 | `lint-classifier-output-quality-warning.sh` (FR-016) — verbatim warning in `rationale` | exit 0 ✅ |
| Test 18b | same, warning ABSENT | exit 2 + Bail-out msg ✅ |
| Test 18c | no output_quality axis (no-op) | exit 0 ✅ |
| Test 19 | `lint-agent-allowlists.sh` (judge MUST be Read-only) | exit 0 ✅ |

## PRD frontmatter validator (`validate-prd-frontmatter.sh`) — 2 cases

| # | PRD shape | Expected | Actual |
|---|-----------|----------|--------|
| Test 20 | Valid PRD with output_quality + rubric | ok=true | ok=true ✅ |
| Test 20b | PRD with output_quality but missing rubric | ok=false + named error | `output_quality-axis-missing-rubric: <path>` ✅ |

## What this validates

- **Schema additions ship cleanly** (FR-001..FR-008): 4 intake surfaces (item / issue / feedback / PRD frontmatter) accept the new optional fields; rejects malformed input loudly with named errors.
- **FR-006 confirm-never-silent conflict prompt is wired** — the jq expression detects same-metric / different-direction across sources, returns the conflict array verbatim. (Actual prompt rendering happens in distill SKILL.md body — verified the detection layer is correct; rendering is interactive.)
- **Build-prd routing is wired** (FR-009..FR-012) — `probe-plan-time-agents.sh` correctly emits `synthesizer | judge | both | skip` based on PRD frontmatter declarations. `parse-research-block.sh` correctly extracts `needs_research` for the upstream routing decision.
- **Lint invariants are wired** — judge-prompt verbatim-rubric (FR-011), synthesizer-prompt diversity, classifier-output-quality-warning (FR-016), agent-allowlists (read-only judge) all green.

## What's NOT validated

- **Live LLM spawn of `kiln:fixture-synthesizer` / `kiln:output-quality-judge`** — per CLAUDE.md Rule 5, agents shipped in the same session aren't spawnable until next session's filesystem rescan. The judge-agent and synthesizer's actual runtime behavior is untested. B-002 in `specs/research-first-completion/blockers.md` documents this; first-real-use is the natural anchor.
- **Distill multi-source merging end-to-end** — tested the conflict-detection jq expression in isolation; the full distill skill's interactive prompt rendering wasn't exercised (would require running `/kiln:kiln-distill` against a corpus of fake sources).
- **Build-prd variant pipeline end-to-end** — would consume real LLM tokens to run baseline → implement → measure → gate. Deferred to first-real-use per B-002.

## Outcome

The new schema + propagation + routing + lint plumbing is correctly wired. The two intentional carve-outs (live-LLM spawn per Rule 5; full variant-pipeline E2E) are documented blockers, not implementation gaps. Scope 2 smoke is **PASS**.
