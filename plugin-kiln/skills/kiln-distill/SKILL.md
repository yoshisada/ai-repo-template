---
name: kiln-distill
description: Bundle open backlog items, feedback, and roadmap entries into a feature PRD by delegating to the kiln:kiln-distill wheel workflow. Takes no filter arguments — the workflow reads all open captures automatically. Supports --resume to report the last-known cursor; actual continuation depends on whether the prior run's wheel state file is still active.
---

# Kiln Distill — Thin Wrapper

```text
$ARGUMENTS
```

## Parse Arguments

Parse `$ARGUMENTS` for a `--resume` flag only. The kiln-distill workflow reads all open captures automatically and does not consume filter arguments.

```bash
RESUME=false

for token in $ARGUMENTS; do
  case "$token" in
    --resume) RESUME=true ;;
    *)        ;;  # ignore — workflow takes no filter args
  esac
done
```

## Resume Logic

If `--resume` was passed, find the most recent distill run manifest and report its last-known cursor for orientation.

Actual continuation is driven by wheel's state-file cursor: if the prior run's state file is still active (not yet archived to `.wheel/history/`), the hook system continues from that cursor at the next tool call. If the state file was archived on completion or stop, re-invoking starts a new run from the beginning. Steps are authored to be re-runnable, so a restart is safe — but it is not a true mid-run resume.

```bash
if [ "$RESUME" = "true" ]; then
  MANIFEST=$(find .kiln/runs -name "manifest.json" 2>/dev/null \
    | xargs grep -l '"phase":"distill\|"prd":"distill/' 2>/dev/null \
    | sort | tail -1)

  if [ -z "$MANIFEST" ]; then
    MANIFEST=$(find .kiln/runs -name "manifest.json" 2>/dev/null | sort | tail -1)
  fi

  if [ -n "$MANIFEST" ]; then
    PHASE=$(jq -r '.phase // "unknown"' "$MANIFEST")
    CURSOR=$(jq -r '.cursor // "unknown"' "$MANIFEST")
    RUN_ID=$(jq -r '.run_id // "unknown"' "$MANIFEST")

    if [ "$PHASE" = "done" ]; then
      echo "Run ${RUN_ID} is already complete (phase: done). Nothing to resume."
      exit 0
    fi

    echo "Last known run ${RUN_ID} — phase: ${PHASE}, cursor: ${CURSOR}"
    echo "If its state file is still active in .wheel/, wheel will continue from that cursor."
    echo "If it was archived, this invocation starts a fresh run from the beginning."
  fi
fi
```

## Delegate to Wheel

```
/wheel:wheel-run kiln:kiln-distill
```
