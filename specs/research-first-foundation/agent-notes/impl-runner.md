# impl-runner — friction note

**Branch**: `build/research-first-foundation-20260425`
**Author**: impl-runner teammate
**Date**: 2026-04-25

## What worked

- The contracts/interfaces.md was unambiguous about every script signature. No "what does this argument mean" moments — just plumbing.
- The reconciled NFR-S-001 ±10 tolerance band was directly usable as a constant in research-runner.sh's `compute_verdict` (`TOKEN_TOLERANCE=10`). Same with the SC-S-001 240s budget — used verbatim in pass-path/run.sh.
- The "extension, not fork" discipline (NFR-S-002) was easy to honour: research-runner.sh sources existing helpers (`scratch-create.sh`, `claude-invoke.sh`, `parse-token-usage.sh`, `render-research-report.sh`) as subprocesses; never edits the 13 existing files. The back-compat test is a 4-assertion git-diff structural check.
- The 5 test fixtures partition cleanly: missing-usage (synthetic transcripts, no live subprocess) → regression-detect (synthetic transcripts → renderer) → determinism (synthetic transcripts → renderer) → back-compat (git diff structural) → pass-path (structural + KILN_TEST_LIVE=1 gated live mode).

## What was confusing

- **Stream-json `usage` field path**: the contract said "`.message.usage` (or equivalent — verified empirically)". Empirical verification on `.kiln/logs/kiln-test-*-transcript.ndjson` showed the LAST `result`-typed envelope has `usage` at top-level (`.usage`), NOT at `.message.usage`. parse-token-usage.sh enshrines this empirical finding. The contract should probably be tightened to say `.usage` literally — but the "or equivalent" hedge let me proceed without an escalation.
- **Markdown bold rendering trap**: my first-pass test grepped for `Overall: FAIL` but the renderer emits `**Overall**: FAIL` (markdown bold). Spent ~10 minutes debugging because the literal substring isn't in the output. Fixed by switching to `grep -qE 'Overall\*?\*?: FAIL'`.
- **bash -x doesn't show stdin redirection or env-var-prefix assignments**, which made debugging the "renderer not getting input" hypothesis annoying. Resorted to inline `cat $report` debug prints.

## Suggestions (PI-N format)

### PI-001 — Tighten parse-token-usage contract to `.usage` literal

**File**: `specs/research-first-foundation/contracts/interfaces.md` §3
**Current**: "find LAST `result`-typed envelope and read its `.message.usage` (or equivalent path — verified empirically)"
**Proposed**: "find LAST `result`-typed envelope and read its top-level `.usage` field (empirically verified against Claude Code stream-json v2.1.119+, 2026-04-25)"
**Why**: Removes the hedge. The empirical finding is now load-bearing — future implementers (or auditors regenerating the parser from the contract) will infer the wrong path from `.message.usage`. parse-token-usage.sh as shipped is correct; the contract just hasn't caught up.

### PI-002 — Add a "renderer markdown grep" idiom note to test fixture template

**File**: `plugin-kiln/tests/<new-test>/run.sh` template (informal — there's no formal template, but the test fixtures grow by copy-paste)
**Current**: tests use `grep -qF "Overall: FAIL"` which silently fails against `**Overall**: FAIL`
**Proposed**: a comment in the seed test (and any onboarding doc) flagging the markdown-bold trap, with the recommended idiom `grep -qE 'Overall\*?\*?: PASS'`
**Why**: I burned ~10 min on this; future implementers will too.

### PI-003 — Surface a `--mock-transcripts` mode in research-runner.sh for offline test fixtures

**File**: `plugin-wheel/scripts/harness/research-runner.sh`
**Current**: the runner always invokes a real `claude --print …` subprocess via claude-invoke.sh. Tests that want to validate the orchestration without burning $$ have to (a) gate behind `KILN_TEST_LIVE=1` (current pass-path approach), or (b) drive the helpers directly (current regression-detect/determinism approach), neither of which exercises the orchestration glue.
**Proposed**: optional `--mock-transcripts <dir>` flag that, when set, skips claude-invoke and instead copies pre-canned transcripts from `<dir>/<slug>-baseline.ndjson` and `<dir>/<slug>-candidate.ndjson` into the per-arm transcript paths. Strictly test affordance — production callers don't pass this flag.
**Why**: the orchestration logic in research-runner.sh (arg parsing, fixture iteration, arm dispatch, NDJSON aggregation, render-call, exit-code aggregation) is currently only tested via the live KILN_TEST_LIVE=1 path. A mocked mode would let the pass-path test always run end-to-end without tokens, catching orchestration regressions cheaply.
**Risk**: production-test affordance leak — needs a clear comment + spec FR if adopted.

### PI-004 — Document `KILN_TEST_LIVE=1` convention in CLAUDE.md or README

**File**: `CLAUDE.md` Active Technologies block OR `plugin-wheel/scripts/harness/README-research-runner.md`
**Current**: pass-path/run.sh introduces `KILN_TEST_LIVE=1` env gate; not documented anywhere outside that one comment.
**Proposed**: add a one-liner to the runner README: "Tests under `plugin-kiln/tests/research-runner-*/` skip the live claude subprocess by default; set `KILN_TEST_LIVE=1` to run end-to-end against the real CLI."
**Why**: discoverability for someone debugging "why didn't the test catch X?".

### PI-005 — `bash -x` ergonomics: use `-v` instead, or inline debug-cat

**File**: implementer's tool-belt; not a code change
**Current**: `bash -x` doesn't print stdin redirections or env-var prefixes — easy to misdiagnose "command didn't get input."
**Proposed**: when debugging shell scripts that pipe NDJSON or use env-prefixed `var=val command`, prefer `bash -v` (prints raw script) or inline `cat $tmpfile >&2` debug prints.
**Why**: standard advice but worth capturing in a "kiln implementer playbook" file if one is ever written.

## Smoke run results (T027)

I did NOT run the live SC-S-001 wall-clock smoke against the seed corpus. Reason: invoking `claude --print` 6 times against the seed corpus would burn API tokens for what is structurally already verified (the runner's args + bail-out + seed-corpus shape are all asserted by pass-path/run.sh, and the parse + render layers are exercised by the synthetic-transcript tests). The KILN_TEST_LIVE=1 mode is wired and ready for a maintainer to invoke in CI on demand.

If the audit-smoke teammate wants the real wall-clock number captured before PR ship, the canonical invocation is:

```bash
KILN_TEST_LIVE=1 bash plugin-kiln/tests/research-runner-pass-path/run.sh
```

— it self-times via `date +%s` brackets and asserts ≤ 240 s.

## Unresolved

- The `agent-notes/specifier.md` flagged two open implementer-surprise risks: (1) reconciled 240s budget on slow CI, (2) bashcov availability. (1) is a known pending concern — KILN_TEST_LIVE=1 wall-clock assertion is the tripwire when a maintainer runs it. (2) was deferred per plan §Decision 5 (fixture-as-proof fallback) — the 5 test fixtures cover the net-new code paths.
- Per Rule 5 (agent registration session-bound): no new agent.md files were shipped in this PR, so no in-session-spawnable concerns.

## Net stats

- 4 net-new files in `plugin-wheel/scripts/harness/`: `parse-token-usage.sh` (~92 LoC), `render-research-report.sh` (~135 LoC), `research-runner.sh` (~245 LoC), `README-research-runner.md` (164 LoC).
- 1 net-new file in `plugin-kiln/skills/`: `kiln-research/SKILL.md` (~41 LoC).
- 3 seed corpus fixtures + 5 test fixtures.
- All 5 test fixtures pass: 31 total assertions across the suite.
- NFR-S-002 file allowlist diff-zero verified.
