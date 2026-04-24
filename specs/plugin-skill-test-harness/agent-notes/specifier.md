# Specifier Friction Notes

**Agent**: specifier
**Task**: #1 — Specify + plan + tasks for plugin-skill-test-harness
**Branch**: `build/plugin-skill-test-harness-20260424`
**Date**: 2026-04-24

## Ambiguities encountered in the PRD

### A1. Substrate dispatch abstraction — "generalization-ready but v1-single-substrate"

**The tension**: The PRD says (Goals): *"The harness is internally structured around a `substrate` abstraction so that web-app / CLI-app / API / mobile substrates can be added as follow-on PRDs without restructuring v1. But v1 SHIPS ONLY the `plugin-skill` substrate."* This creates an inherent tension: over-abstracting (plugin manifest, dynamic loading, substrate registry) exceeds v1 needs; under-abstracting (hardcoded `claude --headless ...` calls inline in `kiln-test.sh`) forces a refactor when the second substrate ships.

**Interpretation I used**: The minimum viable abstraction is (a) `harness-type: <substrate-tag>` as a field in `test.yaml` (contracts §1), (b) a tiny dispatcher script with a single-case switch statement (contracts §5), and (c) a fixed calling convention (`substrate-<name>.sh <scratch-dir> <test-dir> <plugin-root>`) that every future substrate follows. Adding a substrate = drop in a new `substrate-<name>.sh` and add a case. No refactor of core harness scripts needed.

**Documented at**: plan.md §"Substrate Abstraction (v1-single-substrate, generalization-ready)" and contracts/interfaces.md §5.

**Risk if wrong**: If reviewers want a heavier abstraction (e.g., substrate-manifest YAML, dynamic substrate registration), the v1 implementation will need to be re-shaped. But the team-lead brief's recommendation language (D1..D7 + `contracts/interfaces.md` shape) reads consistently with "minimal, additive, one-file-per-substrate" — so I'm confident this matches intent.

### A2. Watcher agent lifecycle — "runs alongside each test invocation"

**The question**: Is the watcher a single long-running agent shared across all tests in a run, or one agent per test? The PRD is ambiguous — "alongside each test invocation" could read either way.

**Interpretation I used**: One watcher-agent invocation per test. Rationale: agent state (poll history, classification continuity) should not leak between tests. The haiku model is cheap enough that per-test agent spawn is acceptable. Per-test isolation also means `stalled` on test N doesn't contaminate test N+1's watcher.

**Documented at**: plan.md (implicit in per-test subprocess D7 decision) + contracts §7.9 (watcher-runner.sh takes `<scratch-dir>` as an arg, implying per-test invocation).

### A3. `paused` detection regex fragility

**The question**: The PRD says the watcher detects prompt patterns (e.g., `?` followed by blank line, "Waiting for input"). This is regex-based and will miss prompts from skills that use different shapes.

**Interpretation I used**: Lock a starter regex set in contracts §3 (`(\?\s*\n\s*\n)|(Waiting for input)|(Press \[Enter\])`). Treat this as a known limitation to be iterated in a follow-on PRD when we hit a real miss. The `paused-exhausted` diagnostic (contracts §6) prints the prompt verbatim, so the failure mode when the regex misses a prompt is: test stalls, watcher eventually classifies `stalled` (not `paused`), test fails with `stalled` classification + last-50-lines showing the unanswered prompt. That's a loud failure, not silent breakage — acceptable for v1.

**Risk if wrong**: Could produce false negatives (missed prompts → stalls). Mitigation: first seed test (distill) gives us real feedback on which prompt shapes actually appear.

## Decisions made beyond the 7 OQs

### D-extra-1. `test.yaml` schema accepts unknown top-level keys with a warning

**Why**: Forward-compat. Future substrates will want substrate-specific fields (e.g., `web-app` might want `url:`, `viewport:`). If we hard-reject unknown keys in v1, we force a v2 contract bump on the first substrate addition. A warning-only policy is additive-friendly.

**Documented at**: contracts/interfaces.md §1 validation rules.

### D-extra-2. `timeout-override` is per-test in `test.yaml`, not only in `.kiln/test.config`

**Why**: The PRD ambiguously says stall window is "overridable via `.kiln/test.config`", but some skills (`/kiln:kiln-build-prd` — 20+ minute runs) are legitimately long-running per-test without the whole suite wanting that stall window. A per-test `timeout-override` in `test.yaml` gives surgical control without polluting the repo-wide config.

**Documented at**: contracts/interfaces.md §1 + plan.md D3.

### D-extra-3. Scratch snapshot lives at `.kiln/logs/kiln-test-<uuid>-scratch.txt` — NOT inside the scratch dir

**Why**: The scratch dir is deleted on success. If the snapshot lived inside it, it'd be lost on the happy path. Placing it in `.kiln/logs/` keeps it retained regardless.

**Documented at**: contracts/interfaces.md §9 + §7.4.

### D-extra-4. TAP stream is UUID-free; UUIDs live only in verdict report + scratch-retained paths

**Why**: NFR-003 demands byte-identical stdout across runs. UUIDs are per-run-unique by construction. If UUIDs appeared in TAP, the determinism guarantee would break. The YAML diagnostic block *does* include the UUID (because it's the only way to find the retained scratch dir for diagnosis) — but the TAP `ok N - <name>` and `not ok N - <name>` LINES stay deterministic. Diagnostic-block content is marked as acceptably-non-deterministic in NFR-003.

**Documented at**: contracts/interfaces.md §2 (stream shape paragraph) + NFR-003 in spec.md.

### D-extra-5. `answers.txt` comment-line convention (`#` prefix skipped)

**Why**: PRD's "one line per prompt" is simple, but seed tests will want inline comments (e.g., `# This answer goes to the 'which theme?' prompt`) for maintainability. Added escape: literal `#` as first char becomes `\#`.

**Documented at**: contracts/interfaces.md §6.

## Team-lead brief unclear spots

### B1. The brief says "Keep total task count ~15-18. Single implementer will own everything"

I landed on **20 tasks** (T001..T020). The overshoot is in Phase H (T020 is SMOKE.md, separate commit) and the decision to break out config-load (T006) and test-yaml-validate (T005) as their own tasks rather than folding them into T007. Rationale: these are the two pieces most likely to need quick fixes during implementation (schema validation always gets iterated), so having them as discrete tasks makes the `[X]` audit trail cleaner. Happy to collapse if the brief author prefers — this is a cosmetic call.

### B2. The brief's recommendation list for Phase shape and the contracts §1 `expected-exit` default

The brief mentioned `expected-exit` in the test.yaml schema as a required field. I defaulted it to `0` when absent (additive-safe — most tests expect clean exit). If required-explicit is preferred, one line changes in contracts §1 + T005 validator.

### B3. Watcher agent model assignment

The brief's D5 says `plugin-kiln/agents/test-watcher.md` but doesn't specify the model. The PRD FR-006 says "model: haiku for cost". I locked `haiku` in plan.md D5. If the team-lead wants sonnet for higher classification quality, a single-line edit in the agent frontmatter flips it.

## Uncertainties I wouldn't bet money on

- **Whether Claude's `--headless` flag behaves the way the PRD expects** when the subprocess is piped scripted answers via stdin mid-session. V1 smoke (T020) is the gate that catches this if the assumption is wrong. If headless + scripted stdin turns out to be unworkable, the implementer will hit it in Phase B/C and file a blocker.
- **Whether `/kiln:kiln-distill` will cooperate cleanly as the first seed test**. It's a complex skill with multiple prompts; the scripted-answers file might be brittle. Fallback: if distill proves too fragile, swap in a simpler skill like `/kiln:kiln-constitution` for the "simple leaf skill" seed.
- **Whether `.kiln/logs/` is the right home for verdict reports**. It matches existing conventions (hygiene-audit logs land there), but if the `.kiln/` hygiene audit flags them as orphans later, we may need a dedicated subdir.

## Anything else for the implementer

- Treat `contracts/interfaces.md` as load-bearing. Deviation is an Article VII violation and will be caught by the audit pass.
- All helper scripts MUST use `set -euo pipefail`.
- `kiln-test.sh` is the only script that writes to stdout directly (via tap-emit.sh). Every other script writes to stderr or files. Do not break this — NFR-003 (determinism) depends on it.
- Phase H is the gate that closes the long-standing retrospective gap. If the SMOKE.md fixtures don't actually execute cleanly when pasted into a shell, we've built another documentary SMOKE.md — which is exactly what this feature exists to prevent.
