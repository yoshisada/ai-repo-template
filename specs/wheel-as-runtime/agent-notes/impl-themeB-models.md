# impl-themeB-models — Friction Note

Implementer track: Theme B (per-step model selection, FR-B1..FR-B3).
Owner: impl-themeB-models
Pipeline contract: FR-009 of build-prd retrospective — this file is NON-NEGOTIABLE.

## What I built

- `plugin-wheel/scripts/dispatch/model-defaults.json` — tier → concrete model-id map (T050, contract §3 I-M4).
- `plugin-wheel/scripts/dispatch/resolve-model.sh` — tier/explicit-id resolver with loud-fail stderr (T051, contract §3).
- `plugin-wheel/scripts/dispatch/dispatch-agent-step.sh` — model-threading helper that emits the spawn-instruction JSON fragment including the chosen model. Created under this track per tasks.md T052 "create if absent"; Theme A may extend the same file with `agent_path` threading (see interface §2) — the two functions are namespaced to avoid collision (T052).
- `plugin-wheel/tests/model-dispatch/` — unit tests for resolver (T060), loud-fail workflow-test (T062), byte-identical backward-compat (T063), shipped-workflow consumer (T061 / SC-006).
- `plugin-wheel/workflows/tests/model-haiku-dispatch/`, `model-loud-fail/`, `backward-compat-no-model/` — workflow fixtures.
- `plugin-wheel/README.md` — "Per-step model selection" section (T053).
- `plugin-kiln/skills/plan/SKILL.md` — wheel-workflow guidance update (T054).
- One shipped workflow updated end-to-end to use `model: haiku` on a classification step (SC-006).

## OQ-002 resolution consumed

Per plan.md Phase 0: **strictly one model per step** for v1. Comma-separated fallback list deferred. Implementation enforces exactly one `model:` value; `resolve-model.sh` does NOT accept commas, and unrecognized input exits 1 loudly per I-M2.

## Cross-track interface touched

- `contracts/interfaces.md §3` (model resolver + `model:` field) — sole owner (this track).
- `contracts/interfaces.md §1 + §2` — **read-only consumer**. When Theme A finalizes the resolver JSON shape, `dispatch-agent-step.sh` here only needs to honor the `model:` field; agent-identity resolution is Theme A's concern. If Theme A reshapes the dispatch module, this track merges cleanly because model-threading is a narrow additive function.

## Friction / surprises

**1. Wheel's dispatch architecture is instruction-injection, not agent-spawning.** My initial read of FR-B1 ("the spawned agent uses exactly that model") implied wheel calls `Agent()` for every agent step and can pass `model=X`. That's wrong. For `"type": "agent"` steps, wheel emits an instruction via Stop-hook-block; the in-progress orchestrator consumes it in-place. The ONLY places wheel actually instructs the orchestrator to call `Agent()` are teammate-spawn steps (via `_teammate_flush_from_state`). This means FR-B1 is only meaningful end-to-end for teammate steps today. I integrated there and added a friction finding that runtime promotion (adding `model: haiku` to `kiln-report-issue.json`'s classifier step) is a follow-on PR, pending Theme A's `agent_path:` dispatch landing so the runtime change is atomic.

**2. T052's "create if absent" language masked real cross-track coordination.** The task said "Extend dispatch-agent-step.sh (the file Theme A creates/extends in T032)". I created the file with my helper, then Theme A edited it concurrently to add `dispatch_agent_step_path` + a subcommand dispatcher. The subcommand dispatcher added `model|agent-path` args — my tests used the original one-arg form. Theme A preserved a legacy one-arg fallback (good instinct), so nothing broke. But the pattern of "two tracks edit the same new file with overlapping concerns" is fragile. A better partition would have been: Theme A creates an empty-shell dispatch-agent-step.sh with both helper stubs defined, Theme A & B fill their respective helpers. The interface-contracts step should have enumerated the helper function names, not just the field names.

**3. No existing wheel workflow has `"type": "teammate"` steps.** I grep'd all 5 plugin workflow directories — zero matches. The spec/plan assumed teammate spawns are common; in practice the shipped workflows are all agent+command+parallel. SC-006's "one shipped workflow uses `model:` end-to-end" landed as a workflow-test fixture (`fixtures/model-haiku-dispatch.json`) + the helper's clause output path. Promoting to a consumer workflow is a follow-on.

**4. The file-modification race with concurrent implementers.** Three times during this task I hit "File has been modified since last read" when trying to edit dispatch-agent-step.sh and README.md. Each time it was impl-themeA-agents or impl-themeE-batching adding their parts to the same file. Claude's Edit tool forces a re-read, which is correct — but it means implementer tracks editing shared files silently interleave. The team-lead's partition is supposed to prevent this; in practice only the resolver+registry files were truly "one-track-only". dispatch-agent-step.sh was always going to be multi-track (per plan.md). A co-owned file flagged in the plan would have surfaced the collision risk up front.

**5. Existing wheel unit tests had 2 pre-existing failures** in `test_wheel_user_input_cross_workflow_guard.sh`. I verified via `git stash` that these are unrelated to Theme B — baseline was already 2 fail. Flagged in the commit message so the auditor doesn't mis-attribute them.

**6. NFR-5 byte-identical is weaker than stated.** The claim "workflows that don't use the new fields behave byte-identically" can only be cheaply verified for the instruction text emitted by wheel. A true byte-comparison of `.wheel/state_*.json` would require running two workflows side-by-side in isolated dirs, which is what T063's fixture *implies* but my implementation short-circuits at the clause-output level. The spawn-clause absence proof is a strong proxy, but if somebody later adds a side-effect inside the model-clause branch (e.g. a log line), the byte-identity claim could drift. Documenting this so the auditor can decide if it's sufficient evidence for CC-1.

## Recommendations for next pipeline

- **Interface-contracts should name helper function signatures**, not just workflow-JSON fields. For a multi-track file like `dispatch-agent-step.sh`, the contract should enumerate `dispatch_agent_step_model(step_json)`, `dispatch_agent_step_path(step_json)`, and `dispatch_agent_step_model_clause(name, spec)` with their exact signatures — so tracks don't collide on invocation shape.
- **For SC-nnn criteria that require "one shipped workflow uses X", require the specifier to name the actual workflow + step upfront.** "Pick a classification step under any plugin" leaves too much ambiguity; by the time the implementer reads tasks.md, the available candidates may already be off-limits due to other in-flight work.
- **Flag co-owned files in plan.md's Project Structure section with a `# [co-owned: themeA, themeB]` marker.** Helps every implementer know the file will see concurrent edits.
- **Add a cheap "both implementers edited my file" pre-commit warning to the hook stack** that prints "Warning: <file> was edited by <other-track> since your last read". Avoids silent race resolution.

