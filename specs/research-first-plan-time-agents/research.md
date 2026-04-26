# Research — research-first-plan-time-agents

## §baseline (current-main measurements, captured 2026-04-25)

### NFR-006 baseline reconciliation — `/plan` skip-path latency

**Premise**: PRD NFR-006 + SC-006 require the `/plan` skip-path (PRDs that declare neither `fixture_corpus: synthesized` nor an `output_quality` axis) to add `< 50 ms` of overhead. Per the team-lead's Step 1.5 directive, this threshold MUST be reconciled against an actual baseline before tasks.md is finalized — if the floor is set by irreducible python3 / jq cold-start forks (the PR #168 NFR-H-5 pattern), the threshold MUST be rewritten with a documented tolerance band before implementer starts.

**Measurement environment**: macOS (developer machine), Bash 5.x, no concurrent load. Five-run median per probe.

**Probes** (each measures a single canonical operation that the skip-path detector might use):

| probe | what it measures | median (ms) | notes |
|-------|------------------|-------------|-------|
| 1. in-process scan (already-running python3) | `re.search` on a 7-line YAML frontmatter file already loaded in memory | **0.12 ms** | sub-millisecond; the cost is dominated by Python regex compilation, not file I/O |
| 2. shell `grep -E` single-pass | one-shot `grep -E "^(fixture_corpus:.*synthesized\|metric:.*output_quality)"` against the file | **~5 ms** | within macOS shell-fork noise; reported as `real 0.00` by `/usr/bin/time -p` (sub-10ms granularity) |
| 3. python3 cold-start fork | `python3 -c 'pass'` — pure interpreter startup, no work | **~10 ms** | the irreducible macOS python3 floor per PR #168 NFR-H-5 |
| 4. jq cold-start fork | `jq -n '0'` — pure jq startup, no work | **~5 ms** | the irreducible macOS jq floor |

**Verdict**: the skip-path can be implemented with **sub-millisecond marginal cost** if it shares the frontmatter parse `/plan` already does for other reasons (e.g., reading `blast_radius:` for the existing rigor lookup, reading `excluded_fixtures:`, etc.). If it requires a dedicated fresh-fork python3 / jq probe, the cost is ~10 ms — comfortably under 50 ms but eats 20 % of the budget for a single probe.

**NFR-006 / SC-006 reconciliation directive (accepted)**: rewrite the threshold as **`≤ baseline + 50 ms`** with a measurement guard at `plugin-kiln/tests/plan-time-agents-skip-perf/`. The "no probe, no spawn" framing in the PRD body is preserved as the *structural* invariant — the skip-path MUST NOT spawn either agent and MUST NOT invoke any net-new subprocess that's not strictly required to make the spawn-or-skip decision. The `≤ baseline + 50 ms` framing is the *measurement* invariant — the test harness records `t_baseline` (a `/plan` invocation against a PRD that pre-existed this PR — e.g., `docs/features/2026-04-25-research-first-foundation/PRD.md` — re-run on the new SKILL.md surface in skip-mode) and `t_skip` (a `/plan` invocation against a fresh fixture PRD declaring neither feature on the new SKILL.md surface) and asserts `t_skip - t_baseline ≤ 50 ms` over 5 runs (median).

**Implementation hint for implementer**: the skip-path detector SHOULD be a single `grep -E` (~5 ms) or — better — a key-lookup on already-parsed JSON if `/plan` is already invoking `parse-prd-frontmatter.sh` from `specs/research-first-axis-enrichment/contracts/interfaces.md §3` (sub-millisecond). DO NOT add a fresh python3 fork solely for the skip-path probe — that wastes 10 ms of the 50 ms budget on a no-op decision.

### Composer-integration sanity (CLAUDE.md "Composer integration recipe")

The CLAUDE.md "Composer integration recipe" stanza is the canonical spawn pattern for both new agents. Verified the runtime composer at `plugin-wheel/scripts/agents/compose-context.sh` exists (per "Active Technologies" entry for `build/agent-prompt-composition-20260425`) and emits `{subagent_type, prompt_prefix, model_default}` JSON given role-instance variables. The new agents' agent.md files at `plugin-kiln/agents/fixture-synthesizer.md` + `plugin-kiln/agents/output-quality-judge.md` ALREADY EXIST as stub coordination-only definitions (committed in the agent-prompt-composition foundation PR #178). This PRD's job is to:
  1. Wire the spawn into `/plan` SKILL.md.
  2. Extend the agent.md files with the role-specific operating instructions (diversity prompt, verbatim rubric handling, anti-drift protocol).
  3. Ship the per-skill `fixture-schema.md` convention.
  4. Ship `judge-config.yaml` + `lint-judge-prompt.sh`.
  5. Ship the orchestrator-side blind-randomization + identical-input control.

NO new agent registration is required — the stubs are already plugin-prefixed (`kiln:fixture-synthesizer`, `kiln:output-quality-judge`) and conform to CLAUDE.md Architectural Rules 1, 2, 3, 4, 6.

### `empirical_quality[]` schema extension (`output_quality` axis)

The PRD references `2026-04-24-research-first-build-prd-wiring`'s `empirical_quality[]` schema. That PRD has not yet shipped (it is step 6 of the `09-research-first` phase per `.kiln/roadmap/items/`). This PRD MUST therefore define the `{metric: output_quality, direction: equal_or_better, rubric: <free-text>}` shape as an additive extension of the schema validator already shipped in `specs/research-first-axis-enrichment/contracts/interfaces.md §3` (which validates `metric ∈ {accuracy, tokens, time, cost, output_quality}` — `output_quality` is already in the validator's enum, deferred for a downstream PRD to wire). All this PRD adds is the `rubric:` required-when-`metric: output_quality` validation rule. Encoded as **FR-010** in spec.md.

### Pinned-judge-model availability

Per FR-014, the judge MUST be invoked with a pinned model ID. The current Anthropic recommendation per `specs/research-first-axis-enrichment/research.md §FR-010` (resolved 2026-04-25) is `claude-opus-4-7`. The pinned model is configured at `.kiln/research/judge-config.yaml` (per-repo, gitignored — see Risks below). Default seeded by `judge-config.yaml.example` committed at the same path. If the pinned model is unavailable at runtime (API returns `model_not_found`), the orchestrator MUST halt with `Bail out! pinned-model-unavailable: <model-id>`. **Fallback model list** is supported per PRD Risks mitigation (`pinned_model_fallbacks: [...]` array), walked top-to-bottom; the model actually used is recorded in each verdict envelope.

### Anti-drift orchestrator-side controls (FR-015 + FR-016) — ownership clarification

The PRD assigns the blind-to-version randomization (FR-015) and the identical-input sanity check (FR-016) to "the orchestrator". The judge agent itself MUST NOT know which output is baseline vs candidate (that's the whole point of FR-015). The orchestrator is therefore the calling skill — `/plan` for the synthesis phase, but the eventual gate-evaluation orchestrator is the per-axis evaluator from `specs/research-first-axis-enrichment` (`evaluate-direction.sh` for mechanical axes; a new `evaluate-output-quality.sh` for this PRD). This PRD ships `evaluate-output-quality.sh` as a sibling helper at `plugin-wheel/scripts/harness/` that wraps the judge-spawn + de-anonymization + identical-input-control plumbing. Encoded in plan.md §3 + contracts/interfaces.md §4.

### Risks surfaced by baseline measurement

1. **judge-config.yaml location**: PRD says `.kiln/research/judge-config.yaml`. `.kiln/research/` is gitignored per the foundation PRD precedent. That means the pinned-model config is per-developer-machine, not per-repo. Opinionated decision (see plan.md Decision 4): commit a `judge-config.yaml.example` at `plugin-kiln/lib/judge-config.yaml.example` AND have the orchestrator read from `.kiln/research/judge-config.yaml` first, falling back to `plugin-kiln/lib/judge-config.yaml.example` if the local file is absent. This makes the default pinned model consistent across machines while allowing per-developer override.
2. **Reject-then-regenerate token spend (FR-006)**: max-regenerations default 3 per fixture. With a 10-fixture corpus and worst-case 3 regenerations per fixture, that's 40 synthesizer spawns. At ~5k tokens per spawn that's 200k tokens — non-trivial but acceptable for a one-time per-PRD cost. Encoded as A-001 (acknowledgment) in spec.md.

## End §baseline
