---
name: "kiln-resume"
description: "Scan .kiln/runs/*/manifest.json for incomplete runs and print the exact resume command for each. Read-only — reports and recommends, does not auto-run anything."
---

# Kiln Resume — Incomplete-Run Scanner

```text
$ARGUMENTS
```

Scan all run manifests under `.kiln/runs/` and surface any run whose `phase` is not `"done"`. For each, print the resume command derived from the manifest's `prd` and `phase`.

## Scan Manifests

```bash
MANIFESTS=$(find .kiln/runs -name "manifest.json" 2>/dev/null | sort)

if [ -z "$MANIFESTS" ]; then
  echo "No run manifests found under .kiln/runs/. Nothing to resume."
  exit 0
fi

INCOMPLETE=0

for MANIFEST in $MANIFESTS; do
  PHASE=$(jq -r '.phase // "unknown"' "$MANIFEST" 2>/dev/null)
  [ "$PHASE" = "done" ] && continue

  RUN_ID=$(jq -r  '.run_id  // "unknown"' "$MANIFEST")
  PRD=$(jq -r     '.prd     // ""'        "$MANIFEST")
  BRANCH=$(jq -r  '.branch  // ""'        "$MANIFEST")
  PR=$(jq -r      '.pr      // "null"'    "$MANIFEST")
  CURSOR=$(jq -r  '.cursor  // "unknown"' "$MANIFEST")

  # Derive workflow type from the prd field shape or directory cues.
  # build-prd manifests: prd = "docs/features/<slug>/PRD.md"
  # fix manifests:       prd = "fix/<slug>" or phase contains "fix"
  # distill manifests:   prd = "" or phase contains "distill"
  if echo "$PRD" | grep -q "^docs/features/"; then
    PRD_SLUG=$(echo "$PRD" | sed 's|docs/features/||; s|/PRD\.md||; s|^[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}-||')
    RESUME_CMD="/kiln:kiln-build-prd ${PRD_SLUG} --resume"
    WORKFLOW="build-prd"
  elif echo "$PHASE" | grep -qi "fix\|diagnose"; then
    ISSUE_SLUG=$(echo "$PRD" | sed 's|fix/||')
    RESUME_CMD="/kiln:kiln-fix ${ISSUE_SLUG} --resume"
    WORKFLOW="fix"
  elif echo "$PHASE" | grep -qi "distill\|theme"; then
    RESUME_CMD="/kiln:kiln-distill --resume"
    WORKFLOW="distill"
  else
    # Unknown workflow type — show build-prd as best guess when prd is set
    if [ -n "$PRD" ] && [ "$PRD" != "null" ]; then
      PRD_SLUG=$(echo "$PRD" | sed 's|docs/features/||; s|/PRD\.md||; s|^[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}-||')
      RESUME_CMD="/kiln:kiln-build-prd ${PRD_SLUG} --resume"
      WORKFLOW="build-prd (inferred)"
    else
      RESUME_CMD="# unknown — inspect ${MANIFEST} manually"
      WORKFLOW="unknown"
    fi
  fi

  INCOMPLETE=$((INCOMPLETE + 1))

  echo ""
  echo "## Incomplete Run: ${RUN_ID}"
  echo "  Workflow : ${WORKFLOW}"
  echo "  Phase    : ${PHASE}"
  echo "  Cursor   : ${CURSOR}"
  [ -n "$PRD"    ] && echo "  PRD      : ${PRD}"
  [ -n "$BRANCH" ] && echo "  Branch   : ${BRANCH}"
  [ "$PR" != "null" ] && [ -n "$PR" ] && echo "  PR       : ${PR}"
  echo "  Manifest : ${MANIFEST}"
  echo ""
  echo "  Resume with:"
  echo "    ${RESUME_CMD}"
done

if [ "$INCOMPLETE" -eq 0 ]; then
  echo "All runs are complete. Nothing to resume."
fi
```

## Notes

- This skill is **read-only** — it does not modify any file or start any workflow.
- Resume commands call the relevant thin-wrapper skill with `--resume`, which passes the slug to wheel and lets wheel's native step-skipping handle continuation.
- If wheel-run does not yet support cursor-based start-step resumption, re-running the wrapper still works: wheel skips steps whose `.wheel/outputs/<step-id>` files already exist from the prior run.
- To resume manually, copy the printed command and run it.
