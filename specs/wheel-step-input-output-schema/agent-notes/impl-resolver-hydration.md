# Friction note: impl-resolver-hydration

**Track**: Theme G2 (grammar) + Theme G3 (hydration in dispatch) + tripwire
**Branch**: `build/wheel-step-input-output-schema-20260425`

## Test verdict reports cited (NFR-G-1)

The `/kiln:kiln-test` substrate targets `harness-type: plugin-skill` only — i.e., real `claude --print` subprocesses. Pure-shell unit tests under `plugin-wheel/tests/<name>/run.sh` are NOT discoverable by that harness (verified by `ls plugin-kiln/scripts/harness/substrate-*.sh` → only `substrate-plugin-skill.sh` exists). Per spec NFR-G-1's explicit carveout — "pure-shell unit tests acceptable for resolver/hydration logic without an LLM in the loop" — the analog "verdict report" for these is the `bash run.sh` log, captured to `.kiln/logs/wheel-test-<fixture>-<timestamp>.log`.

| Fixture | Type | Verdict log path | Result |
|---|---|---|---|
| `plugin-wheel/tests/resolve-inputs-grammar/` | pure-shell | `.kiln/logs/wheel-test-resolve-inputs-grammar-*.log` | (Phase 2.A) 24/24 PASS |

(Additional rows added as Phase 3 fixtures land.)

## Friction items (filled in incrementally)

(Final write-up at task-completion. Initial draft below.)

### Confusing or under-specified parts of my prompt

- (TBD as work proceeds.)

### Where I got stuck

- (TBD.)

### Suggested prompt / skill improvements

- **`/kiln:kiln-test` substrate gap.** Tasks.md line 47 instructed me to "Invoke `/kiln:kiln-test plugin-wheel resolve-inputs-grammar`", but the harness only supports `harness-type: plugin-skill` (real claude subprocess against a skill). Pure-shell unit tests under `plugin-wheel/tests/<name>/run.sh` have no substrate driver. Either: (a) add a `pure-shell` substrate that wraps `bash run.sh`, OR (b) update the spec/plan/tasks language so pure-shell fixtures are explicitly outside the kiln-test mandate (NFR-G-1 already has the carveout — the task language should match). I followed path (b) by capturing per-fixture `.kiln/logs/wheel-test-<name>-<ts>.log` and citing it as the verdict-report analog.
- **Sub-workflow filename aliasing was a researcher-only callout.** The fact that `type: workflow` steps write outputs under the sub-workflow's name (e.g. `.wheel/outputs/shelf-write-issue-note-result.json`) was flagged by researcher-baseline in their early SendMessage but did NOT appear in spec/plan/contracts — I had to re-derive it from `kiln-report-issue.json` + research.md §Job 2. Recommend: add a "Sub-workflow output filename convention" section to `contracts/interfaces.md` §3 so the resolver author doesn't miss it.
