---
name: kiln-distill
description: Bundle open backlog items, feedback, and roadmap entries into a feature PRD by delegating to the kiln:kiln-distill wheel workflow. Accepts optional filter flags (--phase, --addresses, --kind) and a free-text category. Supports --resume to continue an interrupted distill run.
---

# Kiln Distill — Thin Wrapper

```text
$ARGUMENTS
```

## Parse Arguments

Parse `$ARGUMENTS` for a `--resume` flag and any pass-through filter flags. Write the full argument string (minus `--resume`) to `.wheel/inputs/distill-args.txt` so the workflow can read it.

```bash
RESUME=false
PASSTHROUGH=""

for token in $ARGUMENTS; do
  case "$token" in
    --resume) RESUME=true ;;
    *)        PASSTHROUGH="${PASSTHROUGH} ${token}" ;;
  esac
done
PASSTHROUGH="${PASSTHROUGH# }"

mkdir -p .wheel/inputs
echo "$PASSTHROUGH" > .wheel/inputs/distill-args.txt
```

## Resume Logic

If `--resume` was passed, find the most recent distill run manifest and report its state. Wheel's step-skipping handles the actual resume.

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

    echo "Resuming run ${RUN_ID} — phase: ${PHASE}, last completed step: ${CURSOR}"
  fi
fi
```

## Delegate to Wheel

```
/wheel:wheel-run kiln:kiln-distill
```
