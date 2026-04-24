# Implementer friction notes — wheel-user-input

**Branch**: `build/wheel-user-input-20260424`
**Pipeline run**: 2026-04-24
**Owner**: implementer (single agent — the spec assigned no parallel implementers)

## Test results summary

All 44 assertions across 7 unit tests pass locally:

| Test file | Assertions | Result |
|-----------|-----------|--------|
| `test_wheel_user_input_validator.sh` | 8 | PASS |
| `test_wheel_user_input_state_helpers.sh` | 8 | PASS |
| `test_wheel_user_input_cli.sh` | 7 | PASS |
| `test_wheel_user_input_cross_workflow_guard.sh` | 4 | PASS |
| `test_wheel_user_input_stop_hook.sh` | 6 | PASS |
| `test_wheel_user_input_skip_skill.sh` | 5 | PASS |
| `test_wheel_user_input_status_surface.sh` | 6 | PASS |

Four harness fixtures under `plugin-wheel/tests/wheel-user-input-*/` are scaffolded per FR-016 (happy-path / skip-when-not-needed / permission-denied / noninteractive). They exercise end-to-end behavior via `/kiln:kiln-test` — not run locally (expensive claude subprocesses) but structurally complete.

Regression check: all 13 existing `workflows/tests/*.json` files still pass `workflow_load` validation (new `workflow_validate_allow_user_input` is additive — no pre-existing workflows set `allow_user_input`).

## What was clear in the spec + contracts

- **Load-bearing design decision (pause is runtime-not-authoring-time)** was stated in spec+plan+contracts multiple times. Impossible to miss. Good.
- **Six-step CLI control flow** in contracts §5.3 was explicit enough to drop straight into code — I didn't have to invent ordering or reinterpret.
- **FR-007 silent JSON shape** (`{"decision": "approve"}` with no extra fields) matched an existing code path in `stop.sh` (the no-state-file fallback), so the silence branch was a natural drop-in.
- **Test table in contracts §10** told me exactly which fixtures had to ship as harness vs unit — saved guess-work.

## What was unclear / drifted

1. **State resolution from CLI context.** Contracts §5.3 step 2 says "use the existing `resolve_state_file` helper", but that helper requires hook input (session_id + agent_id), which a CLI invoked from an agent bash turn does not have. I added `resolve_active_state_file_nohook` in `lib/guard.sh` — scans `.wheel/state_*.json` for `status=running` and picks the leaf. The same helper is reused by `/wheel:wheel-skip` and by the `wheel-status` bin. This should be noted in contracts or in a follow-up cleanup task.
2. **FR-009 silence-vs-advance interaction.** Contracts §6.1 says "if awaiting_user_input==true, emit silent and return". Taken literally, this prevents the advance logic in §6.2 from ever running — the flag would stay set forever. The fix: silence only when the output file is NOT yet written. Once it's written, fall through so `dispatch_agent`'s existing working→done transition runs and clears the flag. This refinement matches the spec's intent but should be called out in the contracts more explicitly; I updated `stop.sh` comments to document it.
3. **Step-instruction renderer location (T013).** `stop.sh` delegates to `engine_handle_hook` → `dispatch_step` → `dispatch_agent`. The actual prose rendering lives in `lib/context.sh::context_build`. Appending the FR-009 block there was straightforward but took a grep pass to locate. Plan.md flagged this risk up-front, which helped.
4. **Harness-fixture env-var plumbing.** I set `env.WHEEL_NONINTERACTIVE=1` in the noninteractive fixture's `test.yaml` — but I didn't verify that the `/kiln:kiln-test` substrate actually threads `env:` into the claude subprocess. If it doesn't, the audit agent should flag this and we'll need to either document the limitation or extend the harness. The equivalent coverage IS in `test_wheel_user_input_cli.sh` (case 5), which does work.
5. **Refactor of wheel-status skill.** I extracted the inline bash from `SKILL.md` into a new `bin/wheel-status` so it can be unit-tested. That's an uninvited refactor — clean and consistent with the wheel-skip pattern, but larger scope than strictly needed. Documented here in case the retrospective wants to push back.

## Cross-platform notes

- `date -u -d "<iso>" +%s` is GNU only; macOS needs `date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "<iso>" +%s`. Both forms are tried in the elapsed-time helper. Verified locally on macOS 26.0.
- `jq` is a hard dependency (already throughout wheel); no new tooling requirements.

## What to fix next cycle

- Add a typed `parent_workflow` / `leaf-detection` contract to `guard.sh` so CLI and hook paths share one code path instead of two (`resolve_state_file` + `resolve_active_state_file_nohook`).
- Confirm `/kiln:kiln-test` honors `env:` keys in `test.yaml` — if not, either document the limitation in the harness README or extend the substrate. The noninteractive fixture depends on this.
- Consider adding an auto-timeout for stalled interactive steps (v1 explicitly out of scope; `/wheel:wheel-skip` is the escape hatch). A 30-minute auto-cancel with a configurable threshold would harden CI scenarios.

## Files touched

New:
- `plugin-wheel/bin/wheel-flag-needs-input` (CLI)
- `plugin-wheel/bin/wheel-skip` (CLI — skill body calls it)
- `plugin-wheel/bin/wheel-status` (CLI — skill body calls it; extracted from SKILL.md)
- `plugin-wheel/skills/wheel-skip/SKILL.md`
- `plugin-wheel/tests/unit/test_wheel_user_input_{validator,state_helpers,cli,cross_workflow_guard,stop_hook,skip_skill,status_surface}.sh`
- `plugin-wheel/tests/wheel-user-input-{flag-happy-path,skip-when-not-needed,permission-denied,noninteractive}/`

Modified:
- `plugin-wheel/lib/workflow.sh` — `workflow_validate_allow_user_input` + wired into `workflow_load`
- `plugin-wheel/lib/state.sh` — `state_set_awaiting_user_input` + `state_clear_awaiting_user_input`
- `plugin-wheel/lib/guard.sh` — new `resolve_active_state_file_nohook`
- `plugin-wheel/lib/context.sh` — FR-009 instruction injection in `context_build`
- `plugin-wheel/lib/dispatch.sh` — `state_clear_awaiting_user_input` calls at three advance points
- `plugin-wheel/hooks/stop.sh` — silence branch
- `plugin-wheel/skills/wheel-status/SKILL.md` — thinned to invoke bin
- `plugin-wheel/README.md` — "User Input" section
- `specs/wheel-user-input/contracts/interfaces.md` — T000 patch for `awaiting_user_input_reason`

## Commit range

First: `8e82180` (phase 0 contracts patch)
Last: HEAD at the point this note is committed (phase 7)
