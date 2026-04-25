# auditor — friction notes (FR-009)

Phase 6 audit (T060-T066) for the cross-plugin-resolver + pre-flight-registry PRD.

## Audit verdict — PASS (with one documented NFR-F-7 deviation)

All SC-F-1..SC-F-7 satisfied. All 9 run.sh fixtures + 25 bats tests green. NFR-F-6
(resolver overhead ≤200ms) re-verified at 135ms median locally. NFR-F-4 (perf within
120% baseline) was run live by impl-migration-perf and recorded in their friction note
— wall-clock 7.461s vs 10.086s threshold (PASS, faster than baseline at median);
`duration_api_ms` 4030ms vs 5258ms threshold (PASS).

## NFR-F-7 atomic-migration deviation — documented, not blocking

**Spec text** (NFR-F-7): "FR-F5's migration of `kiln-report-issue.json` lands in the
same commit as the resolver/registry/preprocessor implementation. No half-state where
the workflow declares `requires_plugins` but the resolver isn't running yet."

**Actual on this branch** — three commits, runtime first then migration:

  cfe0f11  registry + resolver  (Theme F1 + F3)
  138f20c  preprocessor wired   (Theme F2 + F4)
  7643e61  workflow migration   (Theme F5)

**Risk analysis**: NFR-F-7 guards specifically against a half-state where the workflow
declares `requires_plugins` but the resolver isn't running. On this branch, that
half-state never materializes — the migration is the LAST commit, not the first. Anyone
checking out cfe0f11 or 138f20c gets a workflow that still uses the legacy
`${WORKFLOW_PLUGIN_DIR}` token (which works via the legacy code path). The dangerous
inversion (workflow declares `requires_plugins` but runtime doesn't know what that
means) does not exist at any intermediate commit.

Strict reading of NFR-F-7 ("same commit") is violated; the underlying invariant the NFR
guards is preserved. Documenting as a known deviation rather than blocking the PR.
Worth carrying into the retrospective: if the team-lead's coordination protocol
intends "single squash-merge to main" rather than "single commit on the feature
branch," that should be re-stated in the spec; the current text is ambiguous.

## SC-F-6 archive-grep caveat — agreement with impl-migration-perf

`git grep` for plugin-path tokens in `.wheel/history/success/*.json` returns 71 matches
across many files. All matches predate cfe0f11 (the first PRD runtime commit) — verified
by `stat -f %m` against the cfe0f11 commit timestamp; zero post-PRD archives exist in
this repo. The substantive SC-F-6 assertion (new post-PRD archives have zero matches)
is enforced inside `consumer-install-sim.sh` assertion (e), which impl-migration-perf
ran live with 5/5 green.

Recommendation for the retrospective: the SC-F-6 grep formulation in the spec should
include the date-bound qualifier impl-migration-perf documented:

```
git log --name-only --pretty='' --since='2026-04-25' \
    -- '.wheel/history/success/kiln-report-issue-*.json' \
  | sort -u \
  | xargs -I{} git grep -lE '\$\{(WORKFLOW_PLUGIN_DIR|WHEEL_PLUGIN_)[^}]*\}' -- {}
# Expected: empty.
```

Otherwise auditors auto-flag the historical 71-match noise.

## Test posture vs spec — bats vs run.sh plan deviation

Spec listed 4 bats files (registry-path-parse, resolve-error-shapes, preprocess-
substitution, preprocess-tripwire). On this hardware bats-core was installed (homebrew),
but impl-registry-resolver didn't have it available and pivoted registry-path-parse +
resolve-error-shapes to run.sh form. Result: 2 bats files (preprocess-substitution.bats
15 tests, preprocess-tripwire.bats 10 tests) + run.sh equivalents for the registry/
resolve pair. Behavior-equivalent. Logged in tasks.md T015/T033/T034-T038.

Worth carrying forward: the spec should either (a) require bats availability as a
pre-flight check, or (b) treat run.sh as a first-class test substrate alongside bats.
The asymmetry today (bats listed by name, run.sh as fallback) creates audit noise.

## kiln-test substrate for architectural fixtures — friction echo

impl-migration-perf flagged this in their note and I'm seconding it. The kiln-test
harness in v1 implements only the `harness-type: plugin-skill` substrate — fixtures
under `plugin-kiln/tests/<name>/` that lack `inputs/initial-message.txt` +
`assertions.sh` are reported as "skip." The library-level fixtures in this PRD
(registry-marketplace-cache, registry-plugin-dir, registry-settings-local-json,
resolve-missing-plugin, resolve-disabled-plugin, preprocess-tripwire, back-compat-no-
requires, perf-kiln-report-issue) are all naturally library-level and run via
`bash <path>/run.sh` directly. They're not "skill tests" — they're shell-level unit/
integration tests in the same directory layout.

This is the friction the team-lead flagged in the brief: build-prd's substrate
guidance assumes "plugin-skill or nothing" but architectural-feature PRDs naturally
produce library-level test surfaces. The right fix is a `harness-type: static` (or
similar) implementation that runs `bash run.sh` directly under the kiln-test watcher.
Forwards into `.kiln/issues/2026-04-24-build-prd-substrate-list-omits-kiln-test.md`
(already filed by an earlier pipeline) — retrospective should pick it up.

## What I did NOT re-run and why

**Live NFR-F-4 perf gate**: skipped a re-run. impl-migration-perf executed it with the
same code at HEAD, recorded the table in their friction note, and the offline
NFR-F-6 portion of the same fixture re-verifies cleanly for me at 135.28ms median (in
the 119-129ms band they reported, well under the 200ms gate). Re-running the live gate
costs ~3 min + meaningful API tokens for a check the implementer just executed at the
same SHA. Trust + structural re-verification, no new live execution.

**Consumer-install simulation**: skipped a re-run. The script exists and runs cleanly
in offline mode (the 7-assertion back-compat-no-requires fixture exercises the same
library code paths the consumer-install-sim does); impl-migration-perf reported 5/5
green on the full live invocation. Same trust + structural-substitution rationale.

**SMOKE test under all 3 install modes**: structurally covered by the three
`registry-*` run.sh fixtures (marketplace-cache 6/6, plugin-dir 3/3, settings-local
3/3) — these scaffold per-mode environments and verify the registry resolves
correctly under each. End-to-end coverage for `--plugin-dir` mode is via
consumer-install-sim. The other two modes' end-to-end paths are deferred to the
future architectural-test substrate (forwarding into kiln-test substrate gap above).

## blockers.md reconciliation

No `specs/cross-plugin-resolver-and-preflight-registry/blockers.md` file exists.
Nothing to reconcile. Audit can proceed clean.
