---
name: kiln-fix
description: Fix a bug without ceremony by writing the issue text to .wheel/inputs/issue.txt, then delegating to the kiln:kiln-fix wheel workflow. Accepts a text description, a GitHub issue number, or a URL. Supports --resume to report the last-known cursor; actual continuation depends on whether the prior run's wheel state file is still active.
---

# Kiln Fix — Thin Wrapper

```text
$ARGUMENTS
```

## Parse Arguments

Parse `$ARGUMENTS` for a `--resume` flag and the issue description / reference.

```bash
RESUME=false
ISSUE_ARG=""

for token in $ARGUMENTS; do
  case "$token" in
    --resume) RESUME=true ;;
    *)        ISSUE_ARG="${ISSUE_ARG} ${token}" ;;
  esac
done
ISSUE_ARG="${ISSUE_ARG# }"  # strip leading space
```

## Resolve Issue Text

If the argument is a GitHub issue number or URL, fetch the issue body:

```bash
mkdir -p .wheel/inputs

if echo "$ISSUE_ARG" | grep -qE '^#?[0-9]+$'; then
  ISSUE_NUM=$(echo "$ISSUE_ARG" | tr -d '#')
  gh issue view "$ISSUE_NUM" --json title,body,labels,comments \
    > .wheel/inputs/issue.txt 2>/dev/null \
    || echo "Issue #${ISSUE_NUM}" > .wheel/inputs/issue.txt
elif echo "$ISSUE_ARG" | grep -qE '^https?://github\.com/'; then
  gh issue view "$ISSUE_ARG" --json title,body,labels,comments \
    > .wheel/inputs/issue.txt 2>/dev/null \
    || echo "$ISSUE_ARG" > .wheel/inputs/issue.txt
elif [ -n "$ISSUE_ARG" ]; then
  echo "$ISSUE_ARG" > .wheel/inputs/issue.txt
else
  # No argument — ask the user
  echo "What's the bug? Include the error message, what you expected, and what happened."
  echo "Then re-run: /kiln:kiln-fix <description>"
  exit 0
fi
```

## Resume Logic

If `--resume` was passed, find the most recent fix run manifest and report its last-known cursor for orientation.

Actual continuation is driven by wheel's state-file cursor: if the prior run's state file is still active (not yet archived to `.wheel/history/`), the hook system continues from that cursor at the next tool call. If the state file was archived on completion or stop, re-invoking starts a new run from the beginning. Steps are authored to be re-runnable, so a restart is safe — but it is not a true mid-run resume.

```bash
if [ "$RESUME" = "true" ]; then
  MANIFEST=$(find .kiln/runs -name "manifest.json" 2>/dev/null \
    | xargs grep -l '"prd":"fix/' 2>/dev/null \
    | sort | tail -1)

  # Also accept any recent manifest without a prd key (fix runs may not set prd)
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
/wheel:wheel-run kiln:kiln-fix
```
