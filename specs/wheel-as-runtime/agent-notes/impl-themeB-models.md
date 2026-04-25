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

(filled during work)

## Recommendations for next pipeline

(filled at wrap-up)
