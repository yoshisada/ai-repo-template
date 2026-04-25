---
derived_from:
  - .kiln/roadmap/items/2026-04-24-research-first-per-axis-gate-and-rigor.md
  - .kiln/roadmap/items/2026-04-24-research-first-time-and-cost-axes.md
distilled_date: 2026-04-25
theme: research-first-axis-enrichment
---
# Feature PRD: Research-First Axis Enrichment — Per-Axis Direction Gate + Time/Cost Axes

**Date**: 2026-04-25
**Status**: Draft
**Parent PRD**: [docs/PRD.md](../../PRD.md)
**Depends on**: [`docs/features/2026-04-25-research-first-foundation/PRD.md`](../2026-04-25-research-first-foundation/PRD.md) — both items in this PRD `depends_on: 2026-04-24-research-first-fixture-format-mvp`. Foundation MUST ship before this PRD's pipeline starts.

## Background

Recently the roadmap surfaced these items in the **09-research-first** phase: `2026-04-24-research-first-per-axis-gate-and-rigor` (feature), `2026-04-24-research-first-time-and-cost-axes` (feature). Both items extend the same surface — the per-fixture metric set the foundation runner captures and the gate logic that turns those metrics into a pass/fail verdict — and both depend exclusively on step 1. Bundling them into one PRD avoids a coordination step where step-2's gate refactor lands days before step-3's metric additions and the gate has to ship a stub `time` / `cost` column it can't fill.

Step 2 replaces the foundation's deliberately-coarse strict gate ("any fixture worse on accuracy or tokens fails") with a declarative per-axis `direction:` enforcement: every PRD declares which axes it wants gated and in which direction (`lower` / `higher` / `equal_or_better`), and the gate enforces only the declared axes. It also introduces blast-radius-dynamic rigor (`min_fixtures` + `tolerance_pct` scaling) so an `isolated`-blast change doesn't have to ship a 20-fixture corpus to qualify, and a `cross-cutting` change can't ship with three. Step 3 adds two new axes — `time` (wall-clock subprocess duration) and `cost` (derived from token counts via a maintained pricing table at `plugin-kiln/lib/pricing.json`) — without which the gate can only enforce accuracy and tokens.

The pairing is structural, not editorial: every gate-rule change in step 2 needs to be tested against fixtures that exercise the new axes from step 3 (otherwise reviewers can't tell whether the gate refactor broke time/cost handling vs. just never exercised it), and every new axis in step 3 needs a gate that knows how to enforce direction on it (otherwise the axis is collected but not load-bearing). One PRD, one pipeline pass, one PR.

### Source Issues

| # | Source Entry | Source | Type | GitHub Issue | Severity / Area |
|---|--------------|--------|------|--------------|------------------|
| 1 | [Research-first step 2 — per-axis direction gate + blast-radius-dynamic rigor](../../../.kiln/roadmap/items/2026-04-24-research-first-per-axis-gate-and-rigor.md) | .kiln/roadmap/ | item | — | feature / phase:09-research-first |
| 2 | [Research-first step 3 — time and cost axes with maintained pricing table](../../../.kiln/roadmap/items/2026-04-24-research-first-time-and-cost-axes.md) | .kiln/roadmap/ | item | — | feature / phase:09-research-first |

## Implementation Hints

Replace step 1's hardcoded strict gate with per-axis `direction:` enforcement:

  - Each PRD declares `empirical_quality: [{metric, direction, priority}, ...]`.
  - Gate rule: for every declared axis, every fixture's candidate value must satisfy `direction:`
    relative to baseline. direction=lower → candidate <= baseline. direction=equal_or_better →
    candidate >= baseline (or equal within tolerance). Accuracy is always implicit primary
    with direction=equal_or_better.
  - No axis needs to improve — they just must not regress past their declared direction.
    (Per 2026-04-24 conversation: "if it improves time but not tokens as long as tokens didn't increase then its fine.")

Rigor scaling by blast_radius (config lives at `plugin-kiln/lib/research-rigor.json`):

  { "isolated":      { "min_fixtures": 3,  "tolerance_pct": 5 },
    "feature":       { "min_fixtures": 10, "tolerance_pct": 2 },
    "cross-cutting": { "min_fixtures": 20, "tolerance_pct": 1 },
    "infra":         { "min_fixtures": 20, "tolerance_pct": 0 } }

Tolerance is a per-axis-per-fixture wobble budget for measurement noise (same input, different
run, slightly different token count due to non-determinism). Set to 0 for infra changes where
any regression is suspect.

Excluded-fixtures escape hatch: PRD may declare `excluded_fixtures: [{path, reason}]` to skip
specific known-noisy fixtures. Auditor flags if excluded-fixture count is >30% of corpus.

*(from: `2026-04-24-research-first-per-axis-gate-and-rigor`)*

Add two new axes to the runner's per-fixture metrics:

  - time: wall-clock duration of the subprocess invocation, in seconds (monotonic clock).
          Measured per fixture, per version. High variance → needs tolerance tuning more than
          the mechanical tokens axis.

  - cost: derived metric. cost_usd = f(input_tokens, output_tokens, cached_input_tokens, model_id).
          Pricing table lives at `plugin-kiln/lib/pricing.json`:

            { "claude-opus-4-7":        { "input_per_mtok": 15.00, "output_per_mtok": 75.00, "cached_input_per_mtok": 1.50 },
              "claude-sonnet-4-6":      { "input_per_mtok": 3.00,  "output_per_mtok": 15.00, "cached_input_per_mtok": 0.30 },
              "claude-haiku-4-5-20251001": { "input_per_mtok": 0.80, "output_per_mtok": 4.00, "cached_input_per_mtok": 0.08 } }

Note: these are example numbers — confirm with current Anthropic pricing during implementation.
The pricing table is manually maintained; an auditor subcheck should flag it as stale if the
file's mtime is >180 days old. Model IDs come from the fixture's kiln-test stream-json output.

Cost axis is a pure derivation of token axes — no new measurement. Time is a genuinely new
measurement and may require multi-run averaging to be stable (deferred to a later item if
noise proves unmanageable).

The axes are opt-in per PRD (the research block declares which metrics gate). Most changes
will only declare 1-2 axes (per 2026-04-24 conversation); don't default-declare all four.

*(from: `2026-04-24-research-first-time-and-cost-axes`)*

## Problem Statement

The foundation runner ships with a deliberately-coarse strict gate: any fixture worse on accuracy or tokens fails the run. That gate is good enough to prove the substrate works, but it can't express the actual shape of most research-driven changes. A change that "improves latency but holds tokens flat" is a strict-gate failure (it didn't reduce tokens) even though that's exactly the intended outcome. A change to a 5-line helper that affects three plausible inputs is forced to ship the same 20-fixture corpus as a refactor of the entire `/implement` skill, because the gate has no way to scale rigor to blast radius. And the foundation can't gate on time or cost at all — it only collects accuracy + tokens.

The result without this PRD: the gate is either too strict (genuine improvements get rejected because they didn't move the wrong axis) or maintainers stop using it (the ergonomics of authoring a 20-fixture corpus for an isolated change is a non-starter). The research-first phase needs declarative direction enforcement, blast-radius-scaled rigor, and the two cheapest additional axes (time + cost) before it can be more than a proof-of-concept.

## Goals

- Replace the foundation's strict gate with per-axis `direction:` enforcement keyed off `empirical_quality:` declarations in PRD frontmatter.
- Allow PRDs to declare which axes gate the run; un-declared axes are collected and reported but not enforced (so a tokens-only PRD doesn't fail because time was noisy).
- Scale fixture-count + tolerance requirements to PRD blast radius so isolated changes don't pay 20-fixture overhead and infra changes can't skate by with three.
- Add `time` (wall-clock subprocess duration, monotonic clock) as a measured axis.
- Add `cost` (derived from token counts × model pricing) as a derived axis with a maintained pricing table at `plugin-kiln/lib/pricing.json`.
- Provide an `excluded_fixtures:` escape hatch so a known-noisy fixture can be skipped by name with a written reason — but flag-via-auditor if exclusions exceed 30% of the corpus.
- Preserve the foundation's NFR-003 backward compatibility: PRDs that don't declare `empirical_quality:` continue to fall through to the foundation's strict gate (token + accuracy only).

## Non-Goals

- **No fixture synthesizer** — step 4 (`research-first-fixture-synthesizer`) generates fixtures at plan-time. This PRD assumes declared corpora.
- **No output-quality judge** — step 5 (`research-first-output-quality-judge`) introduces the rubric-driven judge. This PRD only handles mechanical axes (accuracy, tokens, time, cost).
- **No build-prd integration** — step 6 wires `needs_research:` into the pipeline. The substrate stays manually-invokable.
- **No multi-run time averaging** — single-run wall-clock is what v1 of the time axis measures. If the noise floor proves unmanageable, multi-run averaging becomes a follow-on item, explicitly out of scope per source-item hints.
- **No pricing-table auto-refresh** — the table is hand-maintained; the auditor subcheck only flags staleness, it does not fetch.
- **No retroactive gate on existing PRDs** — only PRDs that opt in via `empirical_quality:` get the per-axis gate. Existing PRDs see no behavior change.

## Requirements

### Functional Requirements

#### Gate refactor (step 2)

- **FR-001** *(from: `2026-04-24-research-first-per-axis-gate-and-rigor`)* — A PRD MAY declare `empirical_quality:` as a list of `{metric, direction, priority}` objects in its frontmatter. `metric` is one of `accuracy | tokens | time | cost | output_quality` (output_quality is reserved for step 5; this PRD ignores it if declared). `direction` is one of `lower | higher | equal_or_better`. `priority` is `primary | secondary` (used for surfacing in the report; both are gate-enforced).
- **FR-002** *(from: `2026-04-24-research-first-per-axis-gate-and-rigor`)* — When `empirical_quality:` is declared, the gate MUST enforce `direction:` per declared axis: `direction=lower` → candidate ≤ baseline + tolerance; `direction=equal_or_better` → candidate ≥ baseline − tolerance; `direction=higher` → candidate > baseline. `accuracy` is always implicitly enforced with `direction=equal_or_better` even if not declared (a regression in pass/fail count always fails).
- **FR-003** *(from: `2026-04-24-research-first-per-axis-gate-and-rigor`)* — A change that improves one declared axis and holds another flat (within tolerance) MUST pass the gate. A change that holds all declared axes flat MUST pass. The gate enforces non-regression, not improvement.
- **FR-004** *(from: `2026-04-24-research-first-per-axis-gate-and-rigor`)* — A rigor configuration file MUST live at `plugin-kiln/lib/research-rigor.json` with the shape `{<blast_radius>: {min_fixtures: int, tolerance_pct: int}}` for the four blast-radius values (`isolated`, `feature`, `cross-cutting`, `infra`). The runner reads the calling PRD's `blast_radius:` (from item or PRD frontmatter), looks up the rigor row, and enforces both `min_fixtures` (corpus must contain at least this many fixtures or the run fails fast) and `tolerance_pct` (per-axis wobble budget applied per-fixture).
- **FR-005** *(from: `2026-04-24-research-first-per-axis-gate-and-rigor`)* — `tolerance_pct` MUST be applied per-axis-per-fixture: a fixture's candidate value is a regression on axis X if `(candidate - baseline) / max(baseline, 1) > tolerance_pct/100` for `direction=lower`-style axes (mirrored for the other directions). Set to 0 for `infra` blast — no wobble allowed.
- **FR-006** *(from: `2026-04-24-research-first-per-axis-gate-and-rigor`)* — A PRD MAY declare `excluded_fixtures: [{path, reason}, ...]` to skip specific known-noisy fixtures. The runner skips them at fixture-load time, records each exclusion in the report's "excluded" section with the reason verbatim, and counts them against the `min_fixtures` total (excluded fixtures do NOT satisfy the minimum).
- **FR-007** *(from: `2026-04-24-research-first-per-axis-gate-and-rigor`)* — If excluded-fixture count exceeds 30% of the declared corpus size, the runner MUST emit a "excluded-fraction-high" warning in the report. The auditor MUST surface this as a finding when reviewing PRDs with research runs.
- **FR-008** *(from: `2026-04-24-research-first-per-axis-gate-and-rigor`)* — When `empirical_quality:` is NOT declared in PRD frontmatter, the runner MUST fall back to the foundation's strict gate (NFR-003 of foundation PRD). This preserves backward compatibility.

#### Time and cost axes (step 3)

- **FR-009** *(from: `2026-04-24-research-first-time-and-cost-axes`)* — The runner MUST capture, per fixture per plugin-dir, a `time_seconds` measurement: wall-clock duration of the subprocess invocation using a monotonic clock (e.g. `gdate +%s.%N` on macOS via coreutils, `date +%s.%N` on Linux; Bash `SECONDS` is too coarse).
- **FR-010** *(from: `2026-04-24-research-first-time-and-cost-axes`)* — A pricing table MUST live at `plugin-kiln/lib/pricing.json` keyed by exact model ID. Each entry contains three numeric fields: `input_per_mtok`, `output_per_mtok`, `cached_input_per_mtok` (USD per million tokens). v1 ships entries for `claude-opus-4-7`, `claude-sonnet-4-6`, `claude-haiku-4-5-20251001` — values MUST be confirmed against current Anthropic pricing during implementation.
- **FR-011** *(from: `2026-04-24-research-first-time-and-cost-axes`)* — The runner MUST derive `cost_usd` per fixture per plugin-dir as `(input_tokens × input_per_mtok + output_tokens × output_per_mtok + cached_input_tokens × cached_input_per_mtok) / 1_000_000`. Model ID comes from the fixture's stream-json output (`message.model` field in the assistant turn).
- **FR-012** *(from: `2026-04-24-research-first-time-and-cost-axes`)* — If a fixture's resolved model ID is missing from `pricing.json`, the runner MUST emit `cost_usd: null` for that fixture and a "pricing-table-miss: <model-id>" warning in the report. The fixture is still gate-evaluated on other axes; it does not fail solely due to missing pricing.
- **FR-013** *(from: `2026-04-24-research-first-time-and-cost-axes`)* — An auditor subcheck MUST flag `plugin-kiln/lib/pricing.json` as stale if the file's mtime is more than 180 days old. (This is an audit-time signal, not a gate — research runs do not fail on stale pricing.)
- **FR-014** *(from: `2026-04-24-research-first-time-and-cost-axes`)* — All four axes (accuracy, tokens, time, cost) MUST be opt-in via `empirical_quality:`. Un-declared axes are still measured and reported (so the maintainer sees the full picture) but are NOT gate-enforced. Default behavior is no axis declared (foundation strict-gate fallback per FR-008).

#### Report extensions

- **FR-015** *(from: both items)* — The comparative report at `.kiln/logs/research-<uuid>.md` MUST include, per-fixture: baseline + candidate values for accuracy, tokens, time_seconds, cost_usd; the delta on each axis; and the per-axis verdict (pass / regression / not-enforced). The aggregate summary MUST list the declared axes, the rigor row used (blast_radius + min_fixtures + tolerance_pct), and the overall verdict.

### Non-Functional Requirements

- **NFR-001 — Determinism on declared axes**: re-running the runner on identical inputs MUST produce identical pass/fail verdicts on accuracy, tokens, and cost (cost being a pure function of tokens). Time may vary; tolerance_pct absorbs the variance.
- **NFR-002 — No new runtime dependency**: time measurement uses platform-native monotonic clock (POSIX `date +%s.%N` / coreutils `gdate`). Pricing is hand-maintained JSON parsed by `jq`. No new binaries.
- **NFR-003 — Backward compatibility with foundation**: PRDs without `empirical_quality:` see no behavior change. PRDs with `empirical_quality:` get the per-axis gate; the foundation's strict gate is still callable as a fallback codepath (FR-008).
- **NFR-004 — Pricing-table portability**: the table is checked into the repo and shipped with the plugin, so consumer projects get the same pricing the substrate authors validated. No environment variable or external lookup.
- **NFR-005 — Atomic axis pairing**: step 2's gate-refactor and step 3's metric additions land in the same PR. No partial-ship state where the gate knows about a `time` axis but the runner doesn't measure it (or vice versa).

## User Stories

- **As a kiln maintainer planning a "make this faster without spending more tokens" change**, I want to declare `empirical_quality: [{metric: time, direction: lower}, {metric: tokens, direction: equal_or_better}]` in the PRD, so the gate enforces what I actually intend instead of demanding token reductions I never claimed.
- **As a kiln maintainer working on a 5-line helper**, I want the gate to accept a 3-fixture corpus (because the change is `blast_radius: isolated`), so I'm not paying 20-fixture authoring tax for a tiny change.
- **As a kiln maintainer working on cross-cutting infrastructure**, I want the gate to *require* a 20-fixture corpus and reject 0% tolerance regressions, so a token-count drift on infra can't sneak through under the same rigor as an isolated change.
- **As a kiln maintainer reviewing a research run**, I want a per-fixture cost figure in dollars so I can immediately see whether the candidate is more or less expensive than baseline, without manually multiplying tokens × rates.
- **As an auditor**, I want a stale-pricing warning when `pricing.json` hasn't been touched in 180+ days, so research-run cost figures stay credible over time.

## Success Criteria

- **SC-001** — A PRD declaring `empirical_quality: [{metric: time, direction: lower}, {metric: tokens, direction: equal_or_better}]` and a candidate that improves time but holds tokens flat (within tolerance) MUST pass the gate. The same candidate without the `equal_or_better` declaration on tokens MUST still pass (un-declared axes don't gate).
- **SC-002** — A PRD declaring `blast_radius: cross-cutting` whose corpus has only 5 fixtures MUST fail the run with a "min-fixtures-not-met: 5 < 20" error before any subprocess invocations run.
- **SC-003** — A PRD declaring `blast_radius: infra` with `tolerance_pct: 0` whose candidate produces 1 extra token on a single fixture MUST fail the gate (no wobble allowed for infra).
- **SC-004** — A research run on a corpus mixing fixtures from `claude-opus-4-7` and `claude-haiku-4-5-20251001` model assignments MUST produce per-fixture `cost_usd` values that match a hand-computed `(in × $/in + out × $/out) / 1_000_000` to within 4 decimal places.
- **SC-005** — A PRD with no `empirical_quality:` declared MUST fall through to the foundation's strict gate identically to the foundation PRD's SC-002 / SC-003 (NFR-003 backward-compat anchor).
- **SC-006** — `excluded_fixtures: [{path: <name>, reason: <text>}]` MUST cause the named fixture to be skipped, recorded in the report's "excluded" section with the reason verbatim, and counted toward (not against) the `min_fixtures` floor when checking SC-002.
- **SC-007** — `pricing.json` modified more than 180 days ago MUST trigger an auditor finding labeled `pricing-table-stale: <days>d since mtime`. The research run itself does NOT fail on this signal.

## Tech Stack

Inherited from foundation PRD: Bash 5.x, `jq`, `python3` (stdlib `json`), the existing kiln-test verdict logic. Two new files: `plugin-kiln/lib/research-rigor.json` (rigor table) and `plugin-kiln/lib/pricing.json` (pricing table) — both hand-maintained checked-in JSON. Time measurement uses POSIX `date +%s.%N` (Linux) or `gdate +%s.%N` from coreutils (macOS) — flag a runtime check at runner startup if neither resolves.

## Risks & Open Questions

- **Time-axis noise floor**: wall-clock subprocess duration includes Anthropic API latency, which has high variance independent of the candidate change. v1 of the time axis is single-run with `tolerance_pct` applied; if reviewers report nondeterministic gate failures driven solely by time-axis noise, the response is multi-run averaging (deferred per source-item hints) — NOT lowering the tolerance silently.
- **Pricing-table staleness in practice**: the 180-day mtime heuristic catches obviously-old tables but won't catch a table that was touched (whitespace edit, reformatting) without rate updates. Acceptable v1 — tighter validation needs an Anthropic-published pricing endpoint that doesn't exist.
- **Model-ID extraction from stream-json**: the `message.model` field in the assistant turn's envelope is the canonical source. If a fixture's stream-json output omits this field (e.g., harness-generated fixtures), `cost_usd` resolves to `null`. FR-012 handles the case; risk is invisible-to-author "all my fixtures have null cost" outcomes. Mitigated by surfacing the warning prominently in the report aggregate summary.
- **Excluded-fraction threshold (30%)**: arbitrary. If maintainers regularly need to exclude >30% of a corpus, the corpus is broken, not the threshold — the warning is a smell signal, not a hard rule. Open to adjustment after first real use.
- **Tolerance_pct on cost axis**: cost is a pure derivation of tokens. If the tokens axis passes within tolerance but cost doesn't (e.g., a tokens-flat candidate that shifts 100% of input from cached → fresh), should cost be enforced independently? v1 says yes — declared axes are enforced independently. If this proves over-strict, follow-on item.
- **Blast-radius source of truth**: `blast_radius:` lives on roadmap items and on PRDs. When both conflict, the PRD value wins (the PRD is the gate's input). Item-PRD drift is a roadmap-management concern, not a runner concern.
- **Open question — should rigor table be overrideable per PRD?**: a PRD might want `min_fixtures: 5` for a `feature`-blast change because the surface is genuinely narrow. v1 says no (table is the rule); if real authoring friction emerges, a `rigor_override:` field is a follow-on item.
