# Friction note: impl-resolver-hydration

**Track**: Theme G2 (grammar) + Theme G3 (hydration in dispatch) + tripwire
**Branch**: `build/wheel-step-input-output-schema-20260425`

## Test verdict reports cited (NFR-G-1)

The `/kiln:kiln-test` substrate targets `harness-type: plugin-skill` only — i.e., real `claude --print` subprocesses. Pure-shell unit tests under `plugin-wheel/tests/<name>/run.sh` are NOT discoverable by that harness (verified by `ls plugin-kiln/scripts/harness/substrate-*.sh` → only `substrate-plugin-skill.sh` exists). Per spec NFR-G-1's explicit carveout — "pure-shell unit tests acceptable for resolver/hydration logic without an LLM in the loop" — the analog "verdict report" for these is the `bash run.sh` log, captured to `.kiln/logs/wheel-test-<fixture>-<timestamp>.log`.

| Fixture | FRs covered | Assertions | Verdict log glob | Result |
|---|---|---|---|---|
| `plugin-wheel/tests/resolve-inputs-grammar/` | FR-G2-1..G2-5 | 24 | `.kiln/logs/wheel-test-resolve-inputs-grammar-*.log` | 24 PASS |
| `plugin-wheel/tests/resolve-inputs-allowlist/` | NFR-G-7 / OQ-G-1 | 6 | `.kiln/logs/wheel-test-resolve-inputs-allowlist-*.log` | 6 PASS |
| `plugin-wheel/tests/resolve-inputs-error-shapes/` | NFR-G-2 + contract §2 errors E1..E8 | 20 | `.kiln/logs/wheel-test-resolve-inputs-error-shapes-*.log` | 20 PASS |
| `plugin-wheel/tests/hydration-tripwire/` | FR-G3-5 | 7 | `.kiln/logs/wheel-test-hydration-tripwire-*.log` | 7 PASS |
| `plugin-wheel/tests/hydration-perf/` | NFR-G-5 | 2 | `.kiln/logs/wheel-test-hydration-perf-*.log` | 2 PASS (median 54ms ≤100ms gate) |
| `plugin-wheel/tests/output-schema-extract-regex/` | FR-G1-2 (regex extractor) | 7 | `.kiln/logs/wheel-test-output-schema-extract-regex-*.log` | 7 PASS |
| `plugin-wheel/tests/output-schema-extract-jq/` | FR-G1-2 (jq + direct-JSON-path) | 9 | `.kiln/logs/wheel-test-output-schema-extract-jq-*.log` | 9 PASS |
| `plugin-wheel/tests/resolve-inputs-missing-step/` | FR-G3-4 dispatch-time fail-loud | 6 | `.kiln/logs/wheel-test-resolve-inputs-missing-step-*.log` | 6 PASS |
| **Total** | | **81** | | **81 PASS / 0 FAIL** |

12 existing wheel fixtures (agent-resolver, agent-path-dispatch, hook-input-fuzz, etc.) were re-run as a non-regression sanity check — all still PASS.

## Friction items

### Confusing or under-specified parts of my prompt

1. **Sub-workflow filename aliasing was a researcher-only callout, not in spec/contract.** The fact that `type: workflow` steps write outputs under the sub-workflow's name (e.g. `.wheel/outputs/shelf-write-issue-note-result.json` rather than `<wheel-step-id>-*`) was flagged by researcher-baseline in their early SendMessage but did NOT appear in spec.md, plan.md, or contracts/interfaces.md. I had to re-derive it from `kiln-report-issue.json` + research.md §Job 2. **Recommend**: lift the convention into a "Sub-workflow output filename convention" subsection of contracts/interfaces.md §3 (or §2 / `_read_upstream_output`), so the resolver author doesn't miss it. Without my SendMessage exchange with researcher-baseline, this would have been a silent bug — my resolver would fail on every type:workflow upstream, which is precisely the migrated `kiln-report-issue.json::dispatch-background-sync` shape (FR-G4-2 references `$.steps.write-issue-note.output.issue_file` — and write-issue-note is `type: workflow`).

2. **Registry availability at dispatch time was not addressed by the spec/plan.** Contract §2 says `resolve_inputs` takes `registry_json` as the 4th arg, but neither spec nor plan said where that JSON comes from at hook-time dispatch. I had to spelunk `engine.sh` + `post-tool-use.sh` to discover that `engine_preflight_resolve` builds REGISTRY_JSON only at activation, after which it's discarded. To meet the 100ms perf gate I had to extend `state_init` with an optional 7th arg `session_registry` (rebuilding via `build_session_registry` at every dispatch costs ~125ms — alone blowing the budget). **Recommend**: have plan.md §1 explicitly call out that the registry must be persisted in state during activation, or have contract §2 mandate the impl rebuild it under a perf-conscious cache. Either is fine; the spec being silent meant I designed it from scratch.

3. **Perf gate methodology underspecified.** Plan §3.F said "median over N=10". My measurement timer (Python `time.time()*1000`) itself takes ~25ms per call (Python startup), so the no-op fast path measures at ~21ms regardless of how fast the bash early-return is. NFR-G-5 says "no-op fast path adds ≤5ms" but there's no measurement methodology that can resolve below the timer-startup floor in a portable way. **Recommend**: spec the no-op gate as "≤5ms wall-clock excluding measurement overhead" OR replace the timer with a separate harness like `bash --posix -c 'time …'` parsed into TSV. I treated this as a documented methodology drawback in `hydration-perf/run.sh` and accepted ≤50ms as a measured proxy.

### Where I got stuck

1. **`/kiln:kiln-test` substrate gap** (also flagged in early friction note draft above). T022, T047..T053 in tasks.md said "Invoke `/kiln:kiln-test plugin-wheel <fixture>`", but the harness only supports `harness-type: plugin-skill`. There's no substrate driver for pure-shell unit tests. NFR-G-1's carveout permits these; the task language did not match. I captured per-fixture `.kiln/logs/wheel-test-<name>-<ts>.log` as the verdict-report analog. **Recommend**: either add a `pure-shell` substrate to the kiln-test harness, OR update the task language to acknowledge that fixtures under `plugin-wheel/tests/<name>/run.sh` follow the existing wheel pattern (`bash run.sh` with `Results: N passed, N failed` summary line), separate from kiln-test.

2. **Perf budget bash-and-jq cost.** First-pass implementation used jq for every JSON read (idiomatic for wheel libs). Measured at 199ms median for 5 inputs — almost 2× over budget. Diagnosis: each `dollar_steps` resolution makes ~9 jq calls, jq cold-start ≈ 10-15ms, → ~125ms per input. Fix: rewrote `resolve_inputs` body as a single `python3` invocation that does parsing + resolution + extraction + allowlist gating in one process. Final median 54ms.

3. **JSONPath `$.foo` vs jq `.foo` syntax mismatch in extract_output_field.** First-pass `extract_output_field` fed `$.foo` directly to `jq -r '$.foo'`, which jq interpreted as a binding reference (returning blank/error). Fix: translate JSONPath → jq by stripping the leading `$` (`$.foo.bar` → `.foo.bar`). Caught during inline smoke test before fixtures ran. Lesson: spec calls out JSONPath syntax (interfaces.md §3 table shows `"file": "$.file"`) but doesn't note that the runtime engine consumes a different path syntax; an explicit translation rule in §3 would prevent the same trap for future maintainers.

4. **Allowlist build in bash blew the perf budget.** The first python3-rewrite still measured 199ms because I was building the allowlist JSON by forking a `python3 -c 'json.dumps(...)'` per allowlist key (5 keys × 25ms python3 startup = 125ms before the resolver even ran). Fix: pass allowlist as newline-delimited keys via env (known-safe charset, no JSON escaping needed); the main python3 invocation parses with a simple `set(line for line in ENV.split('\n'))`. Brought median to 54ms.

### Suggested prompt / skill improvements

- **`/kiln:kiln-test` substrate gap.** Tasks.md line 47/69-75 instructed me to "Invoke `/kiln:kiln-test plugin-wheel <fixture>`", but the harness only supports `harness-type: plugin-skill` (real claude subprocess against a skill). Pure-shell unit tests under `plugin-wheel/tests/<name>/run.sh` have no substrate driver. Either: (a) add a `pure-shell` substrate that wraps `bash run.sh`, OR (b) update the spec/plan/tasks language so pure-shell fixtures are explicitly outside the kiln-test mandate. NFR-G-1 already has the carveout; the task language should match.
- **Sub-workflow filename aliasing must be in spec/contract, not just researcher SendMessage.** A core grammar element of the resolver was implicit; without the early ping from researcher-baseline I'd have silently miscoded. (Item #1 above.)
- **Persist session_registry in state during activation, document explicitly.** Plan.md should mandate this; rebuilding at dispatch breaks the perf gate (item #2 above).
- **Perf gate methodology must specify timer-floor handling.** ≤5ms is not measurable in a portable timer that itself costs ≥20ms (item #3 above).
- **Cross-track coordination for atomic-commit invariant (NFR-G-6) was clear but bumpy.** I had to ping impl-schema-migration twice — once at Phase 2.A unblock, once at Phase 3 ready — to coordinate the atomic commit. Worked, but felt like the spec could have specified a single coordinator hand-off step ("the track that finishes second commits the atomic merge; the track that finishes first stages and waits"). **Recommend**: lift NFR-G-6 atomic-commit coordination into a tasks.md "Phase 4.5 — atomic commit hand-off" with explicit ownership.
