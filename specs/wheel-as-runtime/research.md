# Research: Wheel as Runtime

**Purpose**: Resolve Open Questions and Risks from `spec.md` / PRD before implementer tracks dispatch.

## OQ-1 — Resolver location (script-only vs. wheel skill)

- **Decision**: Script-only — `plugin-wheel/scripts/agents/resolve.sh`.
- **Rationale**: Every current caller (wheel dispatch, kiln skills, ad-hoc shell) is a script or can shell out. Exposing `/wheel:wheel-resolve-agent` adds ceremony without a concrete consumer. Adding the skill later is non-breaking.
- **Alternatives considered**: `/wheel:wheel-resolve-agent` skill form — rejected for v1; revisit if a user-facing workflow needs agent resolution.

## OQ-2 — `model:` fallback list

- **Decision**: Strictly one model per step for v1.
- **Rationale**: Additive field + smallest surface. A fallback list (`model: haiku,sonnet`) would introduce ambiguity around FR-B2's loud-fail invariant (do we fail if ANY member is unavailable, or walk the list silently?). Defer to a follow-on PRD if usage motivates it.
- **Alternatives considered**: Comma-separated list with silent walk — rejected; conflicts with FR-B2. Comma-separated with loud first-fail only — defer, no current need.

## R-001 — `WORKFLOW_PLUGIN_DIR` inheritance for background sub-agents

- **Hypothesis**: Option A (wheel exports into workflow-lifetime env scope) is achievable because the Agent tool inherits the spawning process's env. If the harness baselines its own env for `run_in_background: true`, Option A fails and we fall back to Option B.
- **Plan**: `impl-wheel-fixes` track runs a ~1hr Phase 1 spike — export the var in `workflow-env.sh`, spawn a background sub-agent via `Agent(run_in_background: true)` in a toy workflow, assert the var is visible. If yes, commit Option A. If no, pivot to Option B (template `WORKFLOW_PLUGIN_DIR=...` into the sub-agent's prompt) and update CLAUDE.md FR-D3 note. Either way, the FR-D2 smoke test is the invariant.
- **Why this matters**: The original bug shipped because the happy-path env in the source repo masked the absence of the export. Any fix MUST be validated under the consumer-install simulation, not the source-repo layout.

## R-003 — `model:` override billing/quota interaction

- **Decision**: Out of scope for this PRD.
- **Rationale**: If the harness rejects a `model:` value (quota, allow-list, unavailable), the dispatch surfaces the harness's error string loudly via FR-B2. A project-level config knob (`.wheel/model-policy.json` or similar) is a follow-on concern — file a new issue if real usage motivates it.
- **Alternatives considered**: Ship a project-level allow-list in v1 — rejected; no concrete demand, adds config surface.

## R-004 — Hook regex blast radius (pre-flatten removal)

- **Task**: Before FR-C1 lands, `impl-wheel-fixes` greps every regex in `plugin-wheel/hooks/` and `plugin-wheel/scripts/` that reads `tool_input.command` or its flattened form. Any regex that assumed single-line input is a sibling fix.
- **Known candidates** (to re-verify during implementation — these may have moved or been removed):
  - `plugin-wheel/hooks/post-tool-use.sh` — the primary fix (FR-C1).
  - `plugin-wheel/scripts/activate.sh` activation-detection regex — likely benefits from FR-C2 automatically, but confirm.
  - Any other hook that logs `tool_input.command` and assumed single-line format (logging is allowed to sanitize for display but MUST NOT flatten the regex-evaluation copy).
- **Output**: The grep results + per-site decision (fix in-PRD / leave as-is / defer) are recorded in `tasks.md` as an explicit Phase 0 audit task owned by `impl-wheel-fixes`.

## R-005 — Negative perf result on batched step

- **Decision**: Acceptable. If FR-E3 finds no speedup, ship the audit with the honest negative result and narrow FR-E's shipped scope to the audit + convention doc (no forced prototype win).
- **Rationale**: The round-trip latency claim is a hypothesis in the source issue, not a measured fact. Forcing a positive result corrupts the audit.
- **Pre-commitment**: `tasks.md` carries an explicit "negative-result fallback" task so the retrospective doesn't flag the narrowed scope as a failure.

## Other notes from planning

- **No new runtime dependencies** — everything rides on Bash 5.x + `jq` + POSIX utilities + optional `python3 -c "..."` for the hook JSON fallback.
- **Test substrates already exist** — `plugin-kiln/tests/` (skill-test harness, see `plugin-kiln/tests/kiln-distill-basic/` for the current reference pattern) and `plugin-wheel/workflows/tests/` (workflow tests via `/wheel:wheel-test`). No new harness needed.
- **CI** — `/wheel:wheel-test` is the existing entrypoint; NFR-4 wires the FR-D2 smoke test into CI via the same entrypoint or a sibling target. If the budget blows, it earns its own CI job.
