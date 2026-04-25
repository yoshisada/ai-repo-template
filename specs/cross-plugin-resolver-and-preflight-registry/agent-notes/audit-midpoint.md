# audit-midpoint friction note

**Trigger:** 25/37 [impl-*] tasks marked [X] in tasks.md (T010–T056 range), past the ~50% threshold.

**Verdict:** No structural gaps found at midpoint.

## Checks run

| # | Check | Result | Evidence |
|---|---|---|---|
| 1 | `plugin-wheel/lib/registry.sh` defines `build_session_registry` | ✅ | Function declared at line 181; header matches contract §1 prose at line 174. |
| 2 | `plugin-wheel/lib/resolve.sh` defines `resolve_workflow_dependencies` | ✅ | Function declared at line 35; header matches contract §2 at line 17. |
| 3 | `plugin-wheel/lib/preprocess.sh` defines `template_workflow_json` | ✅ | Function declared at line 133; arity matches contract §3 (`<workflow_json> <registry_json> <calling_plugin_dir>`) at line 13. |
| 4 | T031 — engine.sh dispatches registry + resolver BEFORE state mutation | ✅ | engine.sh:50 carries the explicit "T031: MUST run BEFORE state_init" comment; `build_session_registry` at line 61, `resolve_workflow_dependencies` at line 66, `state_write` not called until line 224. Contract I-V-1 ("no side effects on resolver failure") satisfied — both calls are gated by `if !` and exit before any state file is created. |
| 5 | T040 — `workflow_load` accepts `requires_plugins` as OPTIONAL top-level array | ✅ | `workflow_validate_requires_plugins` (workflow.sh:82) returns 0 when `has("requires_plugins")` is false (line 90–93), preserving NFR-F-5 backward-compat for workflows authored pre-PRD. Shape checks (array, non-empty string entries, name regex, duplicates) only fire when the key is present. |
| 6 | T042 — `context.sh::context_build` no longer emits inline "## Runtime Environment" block | ✅ | context.sh:23–38 carries an explicit comment block documenting the removal of the Theme D Option B `runtime_env_block` emission, citing Theme F4 preprocessor as the replacement source of truth. No "## Runtime Environment" header generation remains. |
| 7 | Cross-track — `contracts/interfaces.md` unchanged from 8db12f2 | ✅ | `git diff 8db12f2 -- specs/.../contracts/interfaces.md` returns empty. No mid-flight contract drift from either implementer track. |

## Friction observations

- One-shot midpoint design works well for this PRD: a single sleep+poll cycle (1500s) was enough to land on a 25/37 reading, well past threshold without wasted wake-ups.
- The contracts-unchanged check is a cheap, high-signal canary for "implementers staying in their lane" — recommend adopting it as a stock midpoint item in future pipelines that have a stable interfaces.md from /plan.
- T031 dispatch-order check would benefit from a future tripwire test (e.g., a unit test that mocks `build_session_registry` to fail and asserts no state file appears under `.wheel/state/`); flagging as a follow-on for the auditor or a future PRD, not a midpoint blocker.
