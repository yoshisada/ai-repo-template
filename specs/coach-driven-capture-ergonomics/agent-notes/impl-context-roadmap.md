# Friction Notes — impl-context-roadmap

**Agent**: impl-context-roadmap
**Task**: #2 — shared project-context reader + roadmap interview coaching
**Date**: 2026-04-24
**Branch**: `build/coach-driven-capture-ergonomics-20260424`
**Completed tasks**: T001–T017 (Phase 1 foundation + Phase 2 interview coaching)

## What went well

- **Contract discipline paid off.** `specs/.../contracts/interfaces.md` had the
  JSON schema + sort guarantees + call-site examples locked before I touched
  code. I never had to guess a field name or sort key; I just implemented
  exactly what the contract specified. That also meant no coordination churn
  with impl-vision-audit or impl-distill-multi — they consume the same
  contract, and I never had to change it.
- **Optimization was local.** First naive reader implementation clocked 1.67 s
  on the 50-PRD + 100-item synthetic fixture (close to the 2 s budget). One
  hot-path rewrite — collapse per-item jq spawns into a single awk → TSV →
  `jq -R -s` fold — dropped it to 72 ms. Worth the hour; the budget is no
  longer fragile.
- **Tests-first kept me honest.** Writing the determinism + empty + perf tests
  before the implementation made the edge cases concrete: the empty fixture
  test immediately caught "empty string vs null" ambiguity on first-draft code.

## Friction points

1. **macOS BWK awk vs GNU gawk gotcha.** My first reader draft used
   `match($0, /.../, arr)` for array-capture, which is gawk-only. On macOS it
   silently failed (awk aborted that rule without an error code I could
   observe — it just emitted empty fields). Cost me one debug cycle. The fix
   is portable: `if ($0 ~ /<regex>/) { key=$0; sub(/:.*$/,"",key); val=$0;
   sub(/^[^:]*:[[:space:]]*/,"",val); ... }`. Worth adding to a
   plugin-kiln/CLAUDE.md "Portable awk patterns" note if this recurs.

2. **Bash arithmetic + `seq -w` gotcha.** In the performance-test fixture
   synthesizer I had `theme: t-$((i % 5))` where `i` was `08` — bash treated
   `08` as octal and choked on "value too great for base". Fix:
   `$((10#$i % 5))` to force base-10. Not a new issue, but I'd forgotten
   about it. Consider a lint rule (shellcheck SC2004/SC2219 adjacent) in the
   plugin-kiln pre-commit if this class of bug keeps costing debug cycles.

3. **Parallel-commit bycatch.** My Phase 2 commit (`216169c`) accidentally
   pulled in 6 files from impl-distill-multi (`plugin-kiln/scripts/distill/*`
   + related tests) because those files got staged by some background process
   between my `git add` and my `git commit`. The commit message only
   describes MY work, but the tree delta includes theirs. Not wrong exactly —
   parallel implementers inevitably step on each other — but a cleaner
   workflow would be: (a) a pre-commit `git stash --keep-index` reflex, or
   (b) a team-lead-coordinated commit window.

4. **`bats` not installed.** Tasks specified "Create `bats` test ..." but
   macOS default shell tooling didn't include bats. Switched to plain-bash
   `run.sh` scripts that exit 0/non-zero — functionally equivalent for this
   use case and matches the existing `plugin-kiln/tests/` convention
   (kiln-distill-basic uses `assertions.sh`, not `.bats` files). If the team
   wants real bats, add it as a pre-req or document the fallback.

5. **Phase 2 tests are structural, not behavioral.** The coached-interview
   tests grep SKILL.md for required markers (orientation block, `Proposed:`,
   `accept-all`, collaborative framing) — they're tripwires against
   accidental coupling. A real behavioral check requires streaming stdin to a
   `claude --print` subprocess, and the plugin-skill harness doesn't yet
   support interactive-input. Noted in each test's `test.yaml` as a follow-on.

## Handoff signals

- Phase 1 (reader) contract is **locked** and committed at `e490085`. Tracks
  B and C can consume it via `bash plugin-kiln/scripts/context/read-project-context.sh`.
- Phase 2 (coached interview) is committed at `216169c`. The `--vision` path
  (owned by impl-vision-audit) is untouched by my changes; they committed
  their own changes at `ca252ee` without conflict.
- No signature-change protocol invocations needed. Contract held.

## Suggestions for next time

- **Add a "Portable awk patterns" section to plugin-kiln/CLAUDE.md** so future
  implementers don't hit the gawk-vs-awk issue.
- **Consider a thin `kiln-test-static` harness** for SKILL.md tripwire tests.
  Right now each test re-implements the grep-against-SKILL.md pattern.
- **Coordination protocol in wider pipelines**: a formal "phase commit window"
  (no other implementer's files land in your phase's commit) would reduce
  bycatch and make audit-stage review cleaner.
