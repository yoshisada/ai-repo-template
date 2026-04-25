# kiln-report-issue T092 wrapper reference may break under consumer install (cross-plugin ${WORKFLOW_PLUGIN_DIR})

**Date**: 2026-04-24
**Source**: impl-themeE-batching commit message a36fba1 + Theme D Option B behavior
**Priority**: high
**Suggested command**: `/kiln:kiln-fix`
**Tags**: [auto:continuance, wheel-as-runtime, theme-D, theme-E, portability, silent-failure]

## Description

The T092 switchover in `plugin-kiln/workflows/kiln-report-issue.json` instructs the background sub-agent to invoke:

```bash
OUT=$(bash "${WORKFLOW_PLUGIN_DIR}/scripts/step-dispatch-background-sync.sh")
```

But the wrapper lives in `plugin-shelf/scripts/`, not `plugin-kiln/scripts/`. Theme D's Option B templates `WORKFLOW_PLUGIN_DIR` to the *currently-executing workflow's plugin's install path* — which is `plugin-kiln` here, not `plugin-shelf`. The T092 commit message (a36fba1) explicitly acknowledges this as a pre-existing flaw:

> "The instruction also surfaces a cross-plugin resolution gap: ${WORKFLOW_PLUGIN_DIR}/scripts/... in a plugin-kiln workflow resolves to plugin-kiln/scripts/ under Theme D's Option B, but the actual scripts live in plugin-shelf/scripts/."

In the source repo this "works" because `plugin-kiln/scripts/` and `plugin-shelf/scripts/` both exist side-by-side from CWD — the script resolves via filesystem proximity, not via `${WORKFLOW_PLUGIN_DIR}`. Under a real consumer install where `plugin-kiln` is at `~/.claude/plugins/cache/<org>-<mp>/kiln/<v>/scripts/` and `plugin-shelf` is at `~/.claude/plugins/cache/<org>-<mp>/shelf/<v>/scripts/`, the path does not resolve → the wrapper fails → the background sub-agent no-ops → the counter never increments → full-sync never fires.

This is exactly the "works locally, breaks in consumer install" silent-failure shape that the PRD-level Theme D was intended to eliminate.

## What should happen

Option 1 (minimal): move `plugin-shelf/scripts/step-dispatch-background-sync.sh` into `plugin-kiln/scripts/` with its two helper calls shelled out to the shelf-plugin-cache-installed `shelf-counter.sh` and `append-bg-log.sh` via a plugin-discovery helper. Update the workflow to reference the plugin-kiln path.

Option 2 (right): implement the cross-plugin resolution follow-on named in `specs/wheel-as-runtime/blockers.md` (follow-on #2) — a wheel-level helper that emits a sibling plugin's install path given the plugin name. Workflow instructions gain `${PLUGIN_DIR:shelf}` or equivalent syntax.

Option 3 (safe revert): revert T092 entirely; keep the 3-call chain that used to work. Ship wrapper + audit + convention without the live runtime switchover until Option 2 lands.

Either Option 1 or Option 3 is viable as a hotfix before the consumer-install impact surfaces. Option 2 is the right long-term fix.

## Why this matters

`/kiln:kiln-report-issue` is a daily-use workflow. Silent failure there means counter never increments → `/shelf:shelf-sync` + `/shelf:shelf-propose-manifest-improvement` never fire on cadence → manifest proposals stop arriving in `@inbox/open/` — a quiet regression that could go undetected for weeks.

The FR-D4 regression fingerprint check (`git grep -F 'WORKFLOW_PLUGIN_DIR was unset'`) doesn't catch this case because the variable *is* set — it's just set to the wrong plugin's path.
