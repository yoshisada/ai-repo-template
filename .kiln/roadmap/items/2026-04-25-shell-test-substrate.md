---
id: 2026-04-25-shell-test-substrate
title: "Add harness-type: shell-test substrate — close recurring B-1 from PRs #166, #168"
kind: feature
date: 2026-04-25
status: open
phase: 90-queued
state: planned
blast_radius: isolated
review_cost: moderate
context_cost: "1 session"
addresses:
  - 2026-04-23-wheel-as-plugin-agnostic-infra
depends_on:
  - 2026-04-25-wheel-test-runner-extraction
---

# Add harness-type: shell-test substrate

## Summary

Extend the wheel-test-runner with a new substrate `harness-type: shell-test` that runs `bash <fixture-dir>/run.sh` directly — no `claude --print` subprocess. Existing `harness-type: plugin-skill` fixtures unaffected. Pure additive.

## Why this matters (recurring blocker)

**This is what `.kiln/feedback/issue-#169` PI-2 was actually asking for.** Two consecutive PRDs hit the same B-1 substrate gap:

- **PR #166 (wheel-step-input-output-schema)** — implementer wrote `run.sh`-only fixtures matching the dominant wheel-test pattern; `/kiln:kiln-test plugin-skill` couldn't discover them; auditor used a permissive reading + filed B-1 as a follow-on.
- **PR #168 (wheel-typed-schema-locality)** — same implementer pattern, same auditor decision, same B-1 successor blocker.

The N+1 PRD will hit it again unless this substrate ships. The discipline ("invoke + cite-with-PASS-verdict") was absorbed into both runs — but the substrate physically can't run the prescribed fixture format. PI-2 in issue #169 explicitly asked to promote this to a roadmap item.

## Scope

- New substrate type in `wheel-test-runner.sh`: `harness-type: shell-test`.
- Discovery: scans `plugin-<name>/tests/<test-name>/run.sh` (no test.yaml required) — runs the script with CWD = scratch dir, captures exit code + stdout/stderr.
- Verdict report shape: same as plugin-skill, with `harness-type: shell-test` annotation in the YAML diagnostic block.
- `/kiln:kiln-test plugin-wheel <fixture>` (and `plugin-kiln <fixture>`) discovers shell-test fixtures alongside plugin-skill ones.
- Documented in `kiln-test` SKILL.md alongside the existing `harness-type: plugin-skill` substrate.

## Acceptance

- Authoring a new `plugin-wheel/tests/<name>/run.sh` (no test.yaml) and invoking `/kiln:kiln-test plugin-wheel <name>` produces a verdict report at `.kiln/logs/kiln-test-<uuid>.md` showing PASS.
- Existing test.yaml-based fixtures continue to work unchanged.
- The 17 wheel `run.sh` fixtures from PR #166 + PR #168 (currently only invokable via direct `bash run.sh`) become discoverable by `/kiln:kiln-test`.

## Blast radius rationale

`isolated`: pure additive substrate. No existing fixtures change. No SKILL.md callers change semantics. Discovery is opt-in (a fixture is shell-test only when it has a `run.sh` AND no `test.yaml`).

## Dependencies

`#1 (wheel-test-runner-extraction)` — needs the runner to be in wheel before extending it.

## Knock-on win

Closes the recurring B-1 entry in BOTH `specs/wheel-step-input-output-schema/blockers.md` AND `specs/wheel-typed-schema-locality/blockers.md`. Prevents PR #N+1 from re-discovering the same gap.
