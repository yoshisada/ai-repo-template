---
id: 2026-04-25-wheel-test-runner-extraction
title: "Extract kiln-test runner substrate to wheel — wheel:wheel-test-runner"
kind: feature
date: 2026-04-25
status: open
phase: 90-queued
state: planned
blast_radius: isolated
review_cost: trivial
context_cost: "1 session"
addresses:
  - 2026-04-23-wheel-as-plugin-agnostic-infra
---

# Extract kiln-test runner substrate to wheel

## Summary

Move the executable test-harness core (currently `plugin-kiln/scripts/harness/kiln-test.sh`) out of kiln and into wheel as `plugin-wheel/scripts/harness/wheel-test-runner.sh`. `/kiln:kiln-test` becomes a thin façade that delegates to the wheel-side runner.

## Why first (lowest blast)

Validates the "extract to wheel" pattern at minimum scope. If this hurts — e.g. the substrate is more entangled with kiln-specific assumptions than expected, or the façade adds friction — we know the parent goal is wrong before any higher-blast extraction begins. Also de-risks child #2 (`shell-test-substrate`), which extends this same runner.

## Scope

- Move `plugin-kiln/scripts/harness/kiln-test.sh` core to `plugin-wheel/scripts/harness/wheel-test-runner.sh`.
- Move sibling helpers (`watcher-runner.sh` etc.) alongside.
- `/kiln:kiln-test` SKILL.md updates its `bash <path>` invocation to point at the wheel-side script.
- All existing `plugin-kiln/tests/<fixture>/` and `plugin-wheel/tests/<fixture>/` fixtures invoke unchanged.
- All existing verdict report paths (`.kiln/logs/kiln-test-<uuid>.md`) unchanged.

## Acceptance

- Running `/kiln:kiln-test plugin-kiln <existing-fixture>` produces byte-identical verdict report (modulo timestamps + UUIDs) to pre-PRD.
- All 75 existing kiln-test fixtures + the seeded plugin-skill fixtures pass.
- A wheel-side test exercises `wheel-test-runner.sh` directly (independent of `/kiln:kiln-test`).

## Why this is plugin-agnostic

The substrate (`claude --print --plugin-dir <path>`, scratch-dir per UUID, watcher classifier) makes no assumptions about which plugin's skills are being tested. It's a generic Claude-subprocess harness. The kiln-specific bits are: the `/kiln:kiln-test` skill prose, the `harness-type: plugin-skill` schema, and the verdict-report format. The skill prose stays in kiln (kiln invokes the runner); the runner moves.

## Blast radius rationale

`isolated`: the runner has exactly one caller (`/kiln:kiln-test` SKILL.md). The façade pattern means zero user-facing change. CI doesn't reference the runner directly. No other plugin currently consumes it (that's the point of moving it — to make consumption possible).

## Dependencies

None. This is the foundation extraction; #2-#4 layer on top.
