#!/usr/bin/env bash
# resolve-project-name.sh
# FR-013
#
# FR-013 fallback chain:
#   1. If ./.shelf-config has a non-empty `project_name=<slug>` line, emit <slug>.
#   2. Else if `git rev-parse --show-toplevel` succeeds, emit basename.
#   3. Else emit empty stdout, exit 0 (caller branches on stdout, not exit code).
#
# Invocation: bash resolve-project-name.sh
# stdin: unused.
# stdout: non-empty slug on cases 1 or 2; empty on case 3.
# stderr: silent in cases 1 and 2; one line in case 3:
#   "resolve-project-name: falling through to null"
# exit:
#   0 — always on controlled fall-through.
#   1 — programmer error (e.g., stdin fed when it should not be).

set -u
LC_ALL=C
export LC_ALL

# Case 1: .shelf-config has a `project_name=<slug>` line.
if [ -f .shelf-config ]; then
  slug=$(grep -E '^[[:space:]]*project_name[[:space:]]*=' .shelf-config \
    | head -1 \
    | sed 's/^[[:space:]]*project_name[[:space:]]*=[[:space:]]*//; s/[[:space:]]*$//' \
    || true)
  if [ -n "${slug:-}" ]; then
    printf '%s\n' "$slug"
    exit 0
  fi
fi

# Case 2: git repo root basename.
if toplevel=$(git rev-parse --show-toplevel 2>/dev/null); then
  if [ -n "$toplevel" ]; then
    base=$(basename "$toplevel")
    if [ -n "$base" ]; then
      printf '%s\n' "$base"
      exit 0
    fi
  fi
fi

# Case 3: controlled fall-through.
printf 'resolve-project-name: falling through to null\n' >&2
exit 0
