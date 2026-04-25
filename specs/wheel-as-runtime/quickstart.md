# Quickstart: Exercise Wheel as Runtime End-to-End

This document walks a reviewer (or the PRD auditor) through verifying the feature post-implementation.

## Prerequisites

- Repo at branch `build/wheel-as-runtime-20260424` with all four implementer tracks merged.
- `jq`, `bash 5.x`, `python3` available.
- Clean working tree (so the byte-identical-state diff in step 6 is meaningful).

## 1. Agent resolver (Theme A)

```bash
# Short name
plugin-wheel/scripts/agents/resolve.sh debugger
# → Expect JSON with canonical_path=plugin-wheel/agents/debugger.md

# Repo-relative path
plugin-wheel/scripts/agents/resolve.sh plugin-wheel/agents/qa-engineer.md
# → Same JSON shape

# Unknown passthrough
plugin-wheel/scripts/agents/resolve.sh bogus-name
# → Exit 0, JSON with source=unknown

# Missing WORKFLOW_PLUGIN_DIR + relative input under consumer-install layout
env -u WORKFLOW_PLUGIN_DIR plugin-wheel/scripts/agents/resolve.sh debugger
# → Exit 1 with identifiable stderr (loud failure, not silent)
```

Reference walker (SC-008):
```bash
plugin-wheel/tests/agent-reference-walker/run.sh
# → Every agent reference in every workflow JSON + every kiln skill resolves without exit 1.
```

## 2. Multi-line activation (Theme C)

```bash
# Fire a multi-line Bash tool call that contains activate.sh in a non-last line.
plugin-wheel/tests/activate-multiline/run.sh
# → Assert: .wheel/state_<id>.json exists; wheel.log contains path=activate + result=activate.

# Fuzz test (NFR-3)
plugin-wheel/tests/hook-input-fuzz/run.sh
# → No silent drops of tool_input.command characters across all fuzz shapes.

# Single-line regression (NFR-2)
plugin-wheel/workflows/tests/single-line-activation/run.sh
# → Existing fixture still green (strict superset).
```

## 3. Consumer-install `WORKFLOW_PLUGIN_DIR` smoke test (Theme D)

```bash
plugin-wheel/tests/workflow-plugin-dir-bg/run.sh
# → Assert in a staging dir with source-repo plugin dirs moved aside:
#      - Background sub-agent resolves scripts via ${WORKFLOW_PLUGIN_DIR}.
#      - .kiln/logs/report-issue-bg-<date>.md line with counter_before/after.
#      - grep -F "WORKFLOW_PLUGIN_DIR was unset" returns zero matches.
```

CI verification (NFR-4): open a PR touching `plugin-wheel/` and confirm CI runs the smoke test (exit non-zero on regression).

## 4. Per-step model selection (Theme B)

```bash
# Tier resolution
plugin-wheel/scripts/dispatch/resolve-model.sh haiku
# → Concrete model id matching ^claude-haiku-.

# Loud failure
plugin-wheel/scripts/dispatch/resolve-model.sh bogus
# → Exit 1, identifiable stderr.

# Shipped workflow using model:
/wheel:wheel-run <workflow-with-model-haiku-step>
# → Spawned agent runs on haiku (SC-006).
```

## 5. Kiln skill spawning via resolver (Theme A integration)

```bash
# SC-005 — /kiln:kiln-fix spawns debugger via the resolver, not via general-purpose
plugin-kiln/tests/kiln-fix-resolver-spawn/run.sh
# → The spawned sub-agent's system prompt is plugin-wheel/agents/debugger.md,
#   NOT the generic Agent(subagent_type: general-purpose) spec.
```

## 6. Backward compatibility (NFR-5)

```bash
# Pick a workflow that does NOT use agent_path: or model:.
# Run it pre-PRD (from a stashed baseline) and post-PRD.
diff <(cat <baseline>.wheel/state_<id>.json) <(cat .wheel/state_<id>.json)
# → Byte-identical.
```

## 7. Batched step prototype (Theme E)

```bash
# Run the consolidated wrapper
plugin-shelf/scripts/step-dispatch-background-sync.sh
# → Per-action log lines, final JSON on stdout: {"step": "...", "status": "ok", "actions": [...]}.

# Review the audit
cat .kiln/research/wheel-step-batching-audit-2026-04-24.md
# → Full enumeration table, raw before/after numbers, environment block.
```

If the audit reports a negative result, FR-E scope is narrowed to "audit + convention doc shipped, prototype showed no speedup, reasoning documented" — acceptable per FR-E3.

## 8. Regression fingerprint (SC-007)

```bash
git grep -F 'WORKFLOW_PLUGIN_DIR was unset' .kiln/logs/report-issue-bg-*.md
# → Zero matches for lines written post-PRD. (Use date-stamped grep if needed.)
```

## Done

All eight checks green → SC-001..SC-009 satisfied. The PRD auditor agent validates this same path programmatically.
