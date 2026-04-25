# build-prd skill's NFR-001 substrate list omits `/kiln:kiln-test`

**Date**: 2026-04-24
**Source**: wheel-as-runtime retrospective (PR #161, issue #162) + Theme E post-mortem
**Priority**: medium
**Suggested command**: `/kiln:kiln-fix`
**Tags**: [auto:continuance, build-prd, kiln-test, meta-tooling]

## Description

`/kiln:kiln-build-prd`'s NFR-001 guidance names three substrates implementers may use for the mandatory-test-per-FR rule: `plugin-kiln/tests/<feature>/`, `plugin-wheel/workflows/tests/`, and `plugin-wheel/tests/`. All three are pure-shell or workflow-JSON fixtures with no LLM in the loop.

`/kiln:kiln-test` — explicitly designed to invoke real `claude --print --plugin-dir …` subprocesses against `/tmp/kiln-test-<uuid>/` fixtures — is not named, even though it is the correct substrate for any FR whose claim depends on real agent behavior (LLM-tool-call RTT, multi-step skill chaining, session-level side effects).

Observed consequence (wheel-as-runtime Theme E): FR-E's perf claim was measured at the bash-orchestration layer because the implementer defaulted to the substrates the skill named. The LLM-layer measurement SC-004 actually wanted was never run. See `.kiln/issues/2026-04-24-themeE-t092-shipped-without-llm-layer-measurement.md` for the specific incident.

## What should happen

In `/kiln:kiln-build-prd` (skill description text, the "NFR-001 NON-NEGOTIABLE" section of every implementer prompt), extend the substrate list:

```
Substrates: plugin-kiln/tests/<feature>/ skill-test fixtures, plugin-wheel/workflows/tests/,
plugin-wheel/tests/ shell-level unit tests, OR plugin-kiln/tests/<feature>/ + /kiln:kiln-test
harness for claims that depend on real agent-session behavior (LLM round-trip, multi-step
skill chaining, token-usage deltas, end-to-end workflow timing).
```

Additionally, add a decision rule to the skill: **if an FR's success criterion mentions "wall-clock", "latency", "speedup", "token usage", or "end-to-end", the implementer MUST use the kiln-test harness substrate — shell-level measurement is insufficient**.

## Why this matters

The build-prd skill's substrate list is load-bearing for implementer behavior. Implementers optimize for "NFR-001 satisfied" rather than "right test for the claim", and the skill currently lets the wrong substrate satisfy NFR-001 for perf/LLM-layer claims.
