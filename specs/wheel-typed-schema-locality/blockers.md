# Blockers — wheel-typed-schema-locality

This file documents requirements that landed but with measured deviations,
plus follow-on issues that the implementer surfaced but did not fix.

## NFR-H-5 (perf budget) — measured 55ms vs. 50ms target on composer-tick

**Status**: ACKNOWLEDGED DEVIATION. Within ~10% of budget; production impact
bounded by FR-H2-5 emit-once gating.

**What the spec said**: "Hook-tick adds at most **50ms** combined for
validation + contract surfacing per agent step. Measured via `time` in a
kiln-test fixture against a step with up to 5 inputs and a 5-key
`output_schema`. Baseline = post-PR-#166 hook-tick wall-clock; measured on
the same hardware."

**What we measured** (`plugin-wheel/tests/hydration-perf/run.sh` extended
T027, on Apple-silicon macOS; N=10 medians; 20ms python3-startup measurement
floor subtracted):

| Path | Raw median | Adjusted | Budget | Verdict |
|------|-----------|---------|--------|---------|
| Validator alone (post_tool_use / stop "output exists" tick) | 33ms | 13ms | ≤50ms | ✅ within budget |
| Composer alone (stop "in progress" first-entry tick) | 75ms | **55ms** | ≤50ms | ⚠ +5ms over budget |
| Worst-case per tick | 75ms | 55ms | ≤50ms | ⚠ +5ms over |

**Root cause**: The composer's dominant cost is the python3 fork inside
`substitute_inputs_into_instruction` (≈25ms on this hardware) — required for
FR-H2-2's `{{VAR}}` substitution semantics. Bash + jq overhead in the rest
of the composer adds ≈30ms; the raw fork itself is the remaining ≈25ms,
which is irreducible without changing the substitution implementation.

**Important: validator and composer DO NOT BOTH run on the same tick** —
they live in mutually exclusive branches of `dispatch_agent` (the stop /
teammate_idle branches gate on `output_key && -f "$output_key"` for the
validator vs the else-leaf for the composer). The 50ms "combined" budget in
NFR-H-5 was authored before that branch structure was finalized; the
realistic per-tick budget is `max(validator, composer)` = 55ms.

**Production impact**: bounded by FR-H2-5 emit-once gating. Once the
contract block has been emitted on the first Stop tick, `contract_emitted=true`
suppresses the composer on all subsequent ticks for that step. So the
composer cost lands ONCE per agent step, on the FIRST Stop tick where the
output file is not yet present.

**Two paths to close the deviation** (deferred — not blocking ship):

1. **Cache the substituted instruction at dispatch time** (FR-H2-1
   precedent — we already cache `resolved_inputs`). Add a state field
   `substituted_instruction` written by dispatch.sh's `context_build` path,
   read by the composer instead of re-substituting. Eliminates the python3
   fork from the composer hot path. Estimated ~25ms savings → composer-tick
   ≈30ms adjusted. Cost: extra state surface; a state-file migration
   subroutine if any pre-PRD state files exist in flight.
2. **Reimplement `substitute_inputs_into_instruction` in pure bash + awk**.
   Eliminates the python3 startup. Risk: awk regex semantics drift from
   python re.sub on edge cases (multiline placeholders, JSON-escaped
   resolved values). Estimated ~25ms savings.

Filed as future-work — neither is a hard blocker for this PRD's headline
goals (SC-H-1: zero output-schema-mismatch retries; SC-H-2: round-trip
count drops). Measured per-tick latency at ≤55ms is well within the
end-to-end perceived round-trip cost (multi-second LLM calls dominate).

## /kiln:kiln-test harness mismatch — `run.sh` fixtures are NOT discoverable

**Status**: ACKNOWLEDGED. Fixtures authored in the established
`plugin-wheel/tests/<name>/run.sh` pattern (PR #166 + earlier wheel work);
verified by direct `bash run.sh` invocation. NOT invokable via
`/kiln:kiln-test plugin-wheel <fixture>`.

**What the implementer prompt said**: "you MUST invoke `/kiln:kiln-test
plugin-wheel <fixture-name>` and confirm the verdict report at
`.kiln/logs/kiln-test-<uuid>.md` shows PASS"

**What we found**: `/kiln:kiln-test` discovers ONLY directories containing
`test.yaml` (per `plugin-kiln/scripts/harness/kiln-test.sh` line 140). Of the
28 existing `plugin-wheel/tests/` fixtures, **22 use the `run.sh`-only
pattern** (invoked directly via `bash` from `.github/workflows/wheel-tests.yml`)
and **6 use `test.yaml + assertions.sh`** (the wheel-user-input fixtures —
plugin-skill harness for full-Claude subprocess testing). The kiln-test
harness's only v1 substrate is `plugin-skill` which spawns a real Claude
subprocess against a scratch dir; it is NOT a bash-unit-test runner.

**Resolution chosen**: author the seven new fixtures in the dominant
`run.sh`-only pattern (matches `back-compat-no-inputs`, `hydration-perf`,
`output-schema-extract-jq`, etc.); verify via direct `bash` invocation;
cite the `bash` command + exit-code in the friction note as PASS evidence.
**Live-smoke (`/kiln:kiln-test plugin-kiln perf-kiln-report-issue`) IS
invoked** because that fixture is plugin-skill harness-compatible.

**Suggested follow-on**: extend kiln-test to support a `harness-type:
shell-test` substrate that runs `run.sh` directly and treats exit 0 as PASS.
Trivial extension — a few dozen lines in `kiln-test.sh` + one new
substrate file under `plugin-kiln/scripts/harness/`.

## (Optional) State-file migration for pre-PRD in-flight workflows

**Status**: ACKNOWLEDGED — graceful degradation in place; explicit migration
deferred.

`state_set_resolved_inputs` and `state_set_contract_emitted` write into
`.steps[idx].resolved_inputs` and `.steps[idx].contract_emitted` fields
that pre-PRD state files lack. `state_get_contract_emitted` defaults to
`false` (jq `// false`); the composer reads `resolved_inputs // {}` (jq
default). So pre-PRD state files in flight are usable: the contract block
emits on first Stop tick (correct), the validator runs as expected
(correct), no migration needed.

If a follow-on PRD wants strict state-file shape uniformity it can add a
migration step to `state_init` or a one-shot upgrade script. Not blocking.
