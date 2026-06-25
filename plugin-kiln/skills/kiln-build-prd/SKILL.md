---
name: kiln-build-prd
description: Run the full spec-first build pipeline via the kiln:kiln-build-prd wheel workflow. Resolves or defaults the PRD slug (full dated directory name, e.g. 2026-06-24-my-feature), writes it to .wheel/inputs/prd-slug.txt, then delegates to the workflow. Supports --resume to report the last-known cursor; actual continuation depends on whether the prior run's wheel state file is still active.
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

If no slug was provided, default to the most recent `docs/features/*` directory. The slug is the FULL directory basename (including the date prefix, e.g. `2026-06-24-my-feature`):

```bash
if [ -z "$PRD_SLUG" ]; then
  LATEST_DIR=$(ls -1d docs/features/*/ 2>/dev/null | sort | tail -1)
  if [ -z "$LATEST_DIR" ]; then
    echo "No PRD found under docs/features/. Run /kiln:kiln-distill first, or pass a slug: /kiln:kiln-build-prd <slug>"
    exit 1
  fi
  PRD_SLUG=$(basename "$LATEST_DIR")
fi
```

Verify the PRD file exists. The slug must be the full directory name (date prefix included):

```bash
PRD_PATH="docs/features/${PRD_SLUG}/PRD.md"
if [ ! -f "$PRD_PATH" ]; then
  MATCH=$(find docs/features -maxdepth 2 -name "PRD.md" -path "*${PRD_SLUG}*" 2>/dev/null | head -1)
  if [ -z "$MATCH" ]; then
    echo "PRD not found for slug '${PRD_SLUG}'. Expected docs/features/${PRD_SLUG}/PRD.md"
    exit 1
  fi
  PRD_SLUG=$(basename "$(dirname "$MATCH")")
fi
```

## Write Input

```bash
mkdir -p .wheel/inputs
echo "$PRD_SLUG" > .wheel/inputs/prd-slug.txt
```

## Resume Logic

If `--resume` was passed, find the most recent run manifest for this slug and report its last-known cursor for orientation.

Actual continuation is driven by wheel's state-file cursor: if the prior run's state file is still active (not yet archived to `.wheel/history/`), the hook system continues from that cursor at the next tool call. If the state file was archived on completion or stop, re-invoking starts a new run from the beginning. Steps are authored to be re-runnable, so a restart is safe — but it is not a true mid-run resume.

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

    echo "Last known run ${RUN_ID} — phase: ${PHASE}, cursor: ${CURSOR}"
    echo "If its state file is still active in .wheel/, wheel will continue from that cursor."
    echo "If it was archived, this invocation starts a fresh run from the beginning."
  fi
fi
```

## Delegate to Wheel

```
/wheel:wheel-run kiln:kiln-build-prd
```
