---
status: open
source: retrospective
prd: cross-plugin-resolver-and-preflight-registry
priority: low
suggested_command: /kiln:kiln-fix
tags: [retro, wheel, engine.sh, cleanup]
---

# `engine.sh` source-guard short-circuits when callers pre-source `workflow.sh`; registry/resolve/preprocess never load

**Date**: 2026-04-24
**Source**: cross-plugin-resolver retrospective; impl-registry-resolver friction note §2

## Description

Pre-existing source-guard in `plugin-wheel/lib/engine.sh`:

```bash
if [[ -z "${WHEEL_LIB_DIR:-}" ]] || ! declare -f workflow_load &>/dev/null; then
  # source state.sh, workflow.sh, dispatch.sh, lock.sh, context.sh, guard.sh
fi
```

When `validate-workflow.sh` (or any other caller) sources `workflow.sh` first (which sets `workflow_load`) and then sources `engine.sh`, the OR short-circuits to false → the source block is skipped → `registry.sh`, `resolve.sh`, and `preprocess.sh` (which were added inside this block) never load. Symptom: `build_session_registry: command not found` at runtime.

impl-registry-resolver worked around this by moving the registry/resolve/preprocess sources OUTSIDE the gate (each lib file has its own re-source guard, so it's safe). Worth a small cleanup later.

## Proposed fix (not a prompt rewrite — a wheel cleanup)

**File**: `plugin-wheel/lib/engine.sh`

**Current**: `if [[ -z "${WHEEL_LIB_DIR:-}" ]] || ! declare -f workflow_load &>/dev/null; then ... fi` wrapping all lib sources.

**Proposed**: Either (a) replace the workflow_load-presence check with a per-lib `declare -F` check (one gate per lib), or (b) just always source everything — every lib file already has its own `WHEEL_<NAME>_SH_LOADED` re-source guard, so unconditional sourcing is idempotent.

**Why**: The current gate was a defensible micro-optimization when there was a single workflow_load function to check. With registry/resolve/preprocess now plugged in (and more libs likely to follow), the OR-short-circuit becomes a footgun every time a new caller pre-sources one of the libs. Removing the gate or making it per-lib eliminates the silent-skip class of bug.

## Forwarding action

- File a small `/kiln:kiln-fix` PR against `plugin-wheel/lib/engine.sh` that switches to per-lib gating or unconditional sourcing.
- Add a unit test under `plugin-wheel/tests/engine-source-idempotency/run.sh` that pre-sources `workflow.sh`, then sources `engine.sh`, then asserts `declare -F build_session_registry` succeeds.
