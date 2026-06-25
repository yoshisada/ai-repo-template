---
name: kiln-build-prd
description: Run the full spec-first build pipeline via the kiln:kiln-build-prd wheel workflow. Resolves or defaults the PRD slug, writes it to .wheel/inputs/prd-slug.txt, then delegates to the workflow. Supports --resume to continue from the last completed step.
---

# Kiln Build-PRD — Thin Wrapper

```text
$ARGUMENTS
```

## Parse Arguments

Parse `$ARGUMENTS` for a `--resume` flag and an optional PRD slug.

```bash
RESUME=false
PRD_SLUG=""

for token in $ARGUMENTS; do
  case "$token" in
    --resume) RESUME=true ;;
    --*)      ;;  # ignore unknown flags
    *)        PRD_SLUG="$token" ;;
  esac
done
```

## Resolve PRD Slug

If no slug was provided, default to the most recent `docs/features/*` directory (strip the leading date prefix to get the slug):

```bash
if [ -z "$PRD_SLUG" ]; then
  LATEST_DIR=$(ls -1d docs/features/*/ 2>/dev/null | sort | tail -1)
  if [ -z "$LATEST_DIR" ]; then
    echo "No PRD found under docs/features/. Run /kiln:kiln-distill first, or pass a slug: /kiln:kiln-build-prd <slug>"
    exit 1
  fi
  DIR_NAME=$(basename "$LATEST_DIR")
  PRD_SLUG=$(echo "$DIR_NAME" | sed 's/^[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}-//')
fi
```

Verify the PRD file exists, allowing for date-prefixed directories:

```bash
PRD_PATH="docs/features/${PRD_SLUG}/PRD.md"
if [ ! -f "$PRD_PATH" ]; then
  MATCH=$(find docs/features -maxdepth 2 -name "PRD.md" -path "*${PRD_SLUG}*" 2>/dev/null | head -1)
  if [ -z "$MATCH" ]; then
    echo "PRD not found for slug '${PRD_SLUG}'. Expected docs/features/<date>-${PRD_SLUG}/PRD.md"
    exit 1
  fi
  PRD_SLUG=$(basename "$(dirname "$MATCH")" | sed 's/^[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}-//')
fi
```

## Write Input

```bash
mkdir -p .wheel/inputs
echo "$PRD_SLUG" > .wheel/inputs/prd-slug.txt
```

## Resume Logic

If `--resume` was passed, find the most recent run manifest for this slug and report its state. Wheel's step-skipping handles the actual resume — steps whose outputs already exist in `.wheel/outputs/` are skipped automatically.

```bash
if [ "$RESUME" = "true" ]; then
  MANIFEST=$(find .kiln/runs -name "manifest.json" 2>/dev/null \
    | xargs grep -l "\"prd\":\"docs/features/.*${PRD_SLUG}" 2>/dev/null \
    | sort | tail -1)

  if [ -z "$MANIFEST" ]; then
    echo "No previous run found for slug '${PRD_SLUG}'. Starting fresh."
  else
    PHASE=$(jq -r '.phase // "unknown"' "$MANIFEST")
    CURSOR=$(jq -r '.cursor // "unknown"' "$MANIFEST")
    RUN_ID=$(jq -r '.run_id // "unknown"' "$MANIFEST")

    if [ "$PHASE" = "done" ]; then
      echo "Run ${RUN_ID} is already complete (phase: done). Nothing to resume."
      echo "To rebuild from scratch, omit --resume."
      exit 0
    fi

    echo "Resuming run ${RUN_ID} — phase: ${PHASE}, last completed step: ${CURSOR}"
    echo "Wheel will skip already-completed steps and continue from the cursor."
  fi
fi
```

## Delegate to Wheel

```
/wheel:wheel-run kiln:kiln-build-prd
```
