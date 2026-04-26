#!/usr/bin/env bash
# resolve-monotonic-clock.sh — Probe environment for a sub-second monotonic
# clock and emit the invocation string used to read it.
#
# Satisfies: FR-AE-009 (monotonic-clock startup probe),
#            NFR-AE-006 (probe ladder, deterministic, abort-on-fail).
# Contract:  specs/research-first-axis-enrichment/contracts/interfaces.md §6.
#
# Usage:
#   resolve-monotonic-clock.sh
#
# Stdout (on success): a SINGLE LINE — the resolved invocation string. One of:
#   python3 -c 'import time; print(time.monotonic())'
#   gdate +%s.%N
#   /bin/date +%s.%N
# The caller captures this string and uses it via `eval` for per-fixture timing.
#
# Exit: 0 success; 2 if all ladder rungs fail. Stderr emits the documented
# `Bail out!` diagnostic.
#
# Determinism: same host → same resolution string both times. NEVER falls back
# to integer-second `date +%s` (that would silently miss 800ms→1.2s
# regressions per NFR-AE-007).
set -euo pipefail
LC_ALL=C
export LC_ALL

bail() {
  printf 'Bail out! %s\n' "$1" >&2
  exit 2
}

# Rung 1: python3 -c 'import time; print(time.monotonic())' — preferred.
# Genuinely monotonic, immune to NTP slew, portable across Linux + macOS.
if command -v python3 >/dev/null 2>&1; then
  out=$(python3 -c 'import time; print(time.monotonic())' 2>/dev/null || true)
  if [[ -n $out && $out =~ ^[0-9]+\.[0-9]+$ ]]; then
    printf "python3 -c 'import time; print(time.monotonic())'\n"
    exit 0
  fi
fi

# Rung 2: gdate +%s.%N (Linux GNU date OR macOS+coreutils).
if command -v gdate >/dev/null 2>&1; then
  out=$(gdate +%s.%N 2>/dev/null || true)
  if [[ $out =~ ^[0-9]+\.[0-9]{6,}$ ]]; then
    printf 'gdate +%%s.%%N\n'
    exit 0
  fi
fi

# Rung 3: /bin/date +%s.%N (works on some macOS Darwin builds; non-portable).
if [[ -x /bin/date ]]; then
  out=$(/bin/date +%s.%N 2>/dev/null || true)
  # The regex requires ≥6 fractional digits — rejects BSD-date implementations
  # that emit a literal `%N` token (which would slip through `[0-9]+\.\d+`).
  if [[ $out =~ ^[0-9]+\.[0-9]{6,}$ ]]; then
    printf '/bin/date +%%s.%%N\n'
    exit 0
  fi
fi

bail "no monotonic %N-precision clock available; install python3 (preferred) or coreutils (gdate)"
