# Audit-pr friction note — wheel-typed-schema-locality

**Agent**: audit-pr
**Pipeline**: `kiln-typed-schema-locality`
**Branch**: `build/wheel-typed-schema-locality-20260425`
**Date**: 2026-04-25
**PR**: #168

## Summary

Task #4 executed: smoke test (3 cases) + Step 4b lifecycle archival + PR #168 created with `build-prd` label. Single squash-merge atomic shipment per NFR-H-6 / Path-B precedent.

## Smoke test results (inline, mapped to prompt's verification matrix)

Per prompt: "Either spawn the `kiln:smoke-tester` agent OR run an inline smoke yourself." Chose inline — the relevant fixtures are bash unit tests against the post-PRD code paths, which the audit-compliance teammate already re-ran in foreground (80/80 PASS). Re-running them here in audit-pr's cleaner isolation context is the deterministic verification step the prompt asked for; spawning a separate `kiln:smoke-tester` agent for a 3-fixture re-invocation would add coordination cost without information gain.

| Prompt verification check | Fixture | Result | Notes |
|---|---|---|---|
| Agent step with `inputs:`+`output_schema:` Stop-hook feedback contains `## Resolved Inputs` block + post-`{{VAR}}` instruction text + `## Required Output Schema` heading | `plugin-wheel/tests/contract-block-shape/run.sh` | **11/11 PASS** | T1–T11 cover all 3 heading presences, section order (T4), per-input bullet shape (T5/T6), `{{VAR}}` substitution (T7/T8), schema verbatim match (T9/T10), composer byte-match (T11) |
| Deliberately wrong output write triggers structured diff diagnostic in SAME turn (no extra Stop tick) | `plugin-wheel/tests/output-schema-validation-violation/run.sh` | **16/16 PASS** | T1: exit 1 on mismatch; T2–T6: Expected/Actual/Missing/Unexpected diagnostic body; T10/T13: omission-when-empty rule; T15/T16: NFR-H-2 mutation tripwire confirms test is meaningful |
| Workflow step with NEITHER `inputs:` NOR `output_schema:` produces byte-identical feedback to today (back-compat) | `plugin-wheel/tests/contract-block-back-compat/run.sh` | **7/7 PASS** | T2: `==` string compare; T3: `od -c` hexdump compare against captured pre-PRD baseline; T6: NFR-H-2 mutation tripwire |
| (Bonus — sister NFR-G-3 lock for legacy-step byte-identity in the broader corpus) | `plugin-wheel/tests/back-compat-no-inputs/run.sh` | **9/9 PASS** | T5: shipped `shelf-sync.json` (51 unmigrated `context_from:` uses) loads under post-PRD validator; T6: every shipped workflow without `inputs:`/`output_schema:` still loads |

**Aggregate audit-pr smoke**: 43/43 assertions PASS across the three prompt-mandated cases + the sister corpus lock. No regressions, no surprises. Smoke does NOT block PR creation.

## Step 4b lifecycle archival

PRD `derived_from:` lists one entry: `.kiln/issues/2026-04-25-typed-inputs-outputs-live-smoke-verified.md`.

Action taken:
- Frontmatter rewritten: `status: verified` → `status: completed`, added `completed_date: 2026-04-25`, added `pr: "#168"`.
- `git mv` to `.kiln/issues/completed/2026-04-25-typed-inputs-outputs-live-smoke-verified.md`.
- Diagnostic line emitted to stdout AND appended to `.kiln/logs/build-prd-step4b-2026-04-25.md` per the existing pipe-prefixed format used by the same-day cross-plugin-resolver and step-input-output-schema pipelines:

```
step4b: scanned_issues=1 scanned_feedback=0 matched=1 archived=1 skipped=0 prd_path=docs/features/2026-04-25-wheel-typed-schema-locality/PRD.md pr=#168 derived_from_source=frontmatter missing_entries=[]
```

## PR creation

- Title: `wheel: typed-schema locality — fail-fast validation + Stop-hook surfaces contract`
- Label: `build-prd` (verified via `gh pr view 168 --json labels`)
- Body: full template per audit-pr prompt — Summary / Headline metric (SC-H-1, SC-H-2, SC-H-5) / Compliance / kiln-test verdict reports / Smoke test / Test plan
- URL: <https://github.com/yoshisada/ai-repo-template/pull/168>

PR description cites:
- audit-compliance's live-smoke numbers verbatim (N=5, post-PRD `num_turns=2` across all samples; SC-H-2 −1 turn / −30% wall-clock / −55% output_tokens / −43% api_ms / −16% cost_usd medians).
- All 8 implementer fixture PASS counts + the sister NFR-G-3 lock (9/9).
- The `/kiln:kiln-test plugin-kiln perf-kiln-report-issue` resolver-phase 2/2 PASS for live-smoke substrate non-regression.
- Three accepted deviations from blockers.md.
- audit-pr's three smoke-test results (the prompt-mandated verification matrix, this run).

Per audit-compliance's hand-off note: I did NOT run a separate `/kiln:kiln-report-issue` end-to-end to produce a literal `.wheel/history/success/kiln-report-issue-*.json` archive. Reasoning: the perf-driver substrate's TSV + post-PRD median data are the strict-equivalent evidence for SC-H-1 / SC-H-2 (real `claude --print` subprocesses against post-PRD code; PR-#166 precedent). Running an inner `/kiln:kiln-report-issue` would risk wheel state-file collision with the active orchestrated team session. The PR description cites the perf-driver data directly per audit-compliance's recommendation.

## What was confusing in the prompt

### 1. The smoke-test instruction was already substantially satisfied by audit-compliance

The prompt says: "Either spawn the `kiln:smoke-tester` agent OR run an inline smoke yourself." But audit-compliance had already run all 9 fixtures in foreground (80/80 PASS), executed the live-smoke substrate (N=5 with real `claude --print`), and explicitly hand-off-noted the substrate gap. My re-run was deterministic but somewhat redundant. **Suggestion**: when the previous teammate has already verified the same gates, the audit-pr prompt could say "re-verify the prompt's three specific checks inline (no need to re-run everything audit-compliance already covered) and cite both runs in the PR body". I did this anyway, but the prompt didn't explicitly authorize the redundancy.

### 2. Step 4b log format wasn't documented

The audit-pr prompt says: "Emit diagnostic line to stdout AND `.kiln/logs/build-prd-step4b-2026-04-25.md` per the spec format." There's no spec linked. The format was inferable from the existing same-day file (the cross-plugin-resolver and step-input-output-schema pipelines wrote there earlier). I matched their pipe-delimited shape (`step4b: key=value key=value ... notes="..."`). **Suggestion**: link the format spec, or include a one-line example in the audit-pr prompt template.

### 3. Friction note write before vs after task #4 completion

Prompt says: "Write `specs/wheel-typed-schema-locality/agent-notes/audit-pr.md` before marking task #4 completed." OK — but does the friction-note commit go in the same commit as the Step 4b archival, or a separate one? Implementer + audit-compliance both did separate commits for friction notes (see commit graph: `848335d` for audit-compliance friction note alone, `8735e94` includes implementer's). I'll bundle Step 4b archival + this note + PR-creation tail in a single commit titled `wheel-typed-schema-locality: step4b archival + audit-pr friction note`, then push.

### 4. PR convention: literal `.wheel/history/success/kiln-report-issue-*.json` archive

audit-compliance explicitly flagged this in their hand-off — the perf-driver substrate doesn't produce that exact archive shape; producing one literally would require running `/kiln:kiln-report-issue` end-to-end. The audit-pr prompt's headline-metric template language ("count output_schema-mismatch retries in the dispatch-background-sync step's `command_log` array") was authored against that literal-archive expectation. I followed audit-compliance's recommendation and cited the perf-driver TSV + median data directly in the PR body (SC-H-1 / SC-H-2 PASS). **Suggestion**: the audit-pr prompt template should be updated to match what the substrate actually produces — either drop the literal-archive language or document the perf-driver substrate as the canonical evidence.

## Where I got stuck

Two minor friction points, both quickly recovered:

- **Edit tool requires Read first.** Tried `Edit` on the seed-issue frontmatter without first reading it; got `File has not been read yet`. Read first, then Edit. Standard tool quirk. Worth a one-liner reminder in the build-prd flow if not already there.
- **Write tool refuses overwrite without Read.** Tried to `Write` to `.kiln/logs/build-prd-step4b-2026-04-25.md` not realizing it already existed (other same-day pipelines had appended to it). Read it, saw the established pipe-prefixed format, then `Edit`-appended my line. Cleaner outcome — preserved the existing log format and the prior pipelines' entries.

## Cross-reference: issue #167 PI-1/PI-2

PI-1/PI-2 framed the fixture-existence-vs-invocation discipline. By the time the workload reached audit-pr, both prior teammates (implementer + audit-compliance) had absorbed and enforced that discipline — implementer cited 71/71 PASS counts in their friction note; audit-compliance re-ran all 9 fixtures + cited 80/80; I re-ran 3 + cited 43/43. The discipline is now clearly in the prompt template's DNA.

The remaining open item is **PI-3 candidate** (already proposed by both implementer and audit-compliance): extend `plugin-kiln/scripts/harness/kiln-test.sh` with a `harness-type: shell-test` substrate that runs `run.sh` directly, OR relax NFR-H-1 spec language to "invoke `/kiln:kiln-test` OR direct bash-run with PASS-cite — substrate-appropriate." This is the second consecutive PRD with this exact deviation (PR #166 + this PR #168). Worth promoting to a real backlog item via `/kiln:kiln-roadmap --promote` once this PR merges.

## Suggestions

### For the audit-pr prompt template

1. **Replace the literal-archive language** in the SC-H-1 / SC-H-2 framing with substrate-appropriate evidence guidance — perf-driver TSV is fine evidence for `num_turns` deltas (it's what audit-compliance produced and what this PR cites).
2. **Acknowledge prior teammate verification** — when audit-compliance has already run the gates audit-pr is asked to re-verify, the prompt could say "re-verify the prompt-listed checks inline; cite both runs in PR body." Avoids redundancy ambiguity.
3. **Link the Step 4b log format** — the pipe-delimited shape is inferable from existing files but there's no canonical reference. A one-line example in the prompt template would prevent format drift across pipelines.
4. **Friction-note commit timing** — clarify whether to commit friction note bundled with Step 4b archival (this run's choice) or as a separate post-PR follow-up commit (audit-compliance's choice). Either is fine; just pick one and document it.

### For the build-prd skill itself

- The same-day Step 4b log file is now accumulating entries from multiple pipelines (3 entries today: cross-plugin-resolver, step-input-output-schema, typed-schema-locality). This is good — the file is a daily archive log. Worth promoting the pipe-delimited format to a canonical contract documented under `plugin-kiln/scripts/build-prd/` (or wherever Step 4b lives), so future audit-pr teammates don't have to infer it.

## Mark-completion

Smoke 43/43 PASS (3 prompt-mandated cases + 1 sister NFR-G-3 lock). Step 4b archival complete (1 entry, clean). PR #168 created with `build-prd` label. Friction note written. Ready to commit + push + mark task #4 completed + SendMessage team-lead.
