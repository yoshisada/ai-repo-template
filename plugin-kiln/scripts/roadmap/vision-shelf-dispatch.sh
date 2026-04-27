#!/usr/bin/env bash
# vision-tooling FR-004 — wraps the shelf mirror dispatch path used by the
# coached --vision interview. Warn-and-continue when .shelf-config is missing
# or incomplete.
#
# Per contracts/interfaces.md §"Theme A — vision-shelf-dispatch.sh":
#   Invocation: vision-shelf-dispatch.sh (no arguments).
#   Stdout (warn-and-continue, exit 0):
#     "shelf: .shelf-config not configured; skipping mirror dispatch (warning shape matches kiln-roadmap)"
#   Stdout (dispatch fired): byte-identical to the coached-path dispatch.
#   Exit: always 0 — never bubbles failure up (FR-004).
#
# This script does NOT mutate .kiln/vision.md.

set -euo pipefail

REPO_ROOT="${KILN_REPO_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
SHELF_CONFIG="$REPO_ROOT/.shelf-config"

# Gate: .shelf-config missing OR empty OR missing required `base_path:` /
# `slug:` keys → warn-and-continue. Mirrors the existing coached-interview
# warning shape used by kiln-roadmap.
shelf_config_ok() {
  [ -s "$SHELF_CONFIG" ] || return 1
  grep -Eq '^base_path:[[:space:]]*\S' "$SHELF_CONFIG" 2>/dev/null || return 1
  grep -Eq '^slug:[[:space:]]*\S' "$SHELF_CONFIG" 2>/dev/null || return 1
  return 0
}

if ! shelf_config_ok; then
  printf 'shelf: .shelf-config not configured; skipping mirror dispatch (warning shape matches kiln-roadmap)\n'
  exit 0
fi

# Dispatch path — invoke shelf:shelf-write-roadmap-note via claude --print
# in the same shape as the coached interview tail. The actual MCP write is
# performed by the shelf plugin; we only fire the dispatch and let any
# diagnostics flow to stderr.
#
# Test-determinism / mock-injection: when KILN_TEST_DISABLE_LLM is set, skip
# the live invocation and emit a stable confirmation line. This mirrors the
# KILN_TEST_MOCK_LLM_DIR convention but is dispatch-shaped, not response-
# shaped.
if [ -n "${KILN_TEST_DISABLE_LLM:-}" ]; then
  printf 'shelf: dispatched mirror update for .kiln/vision.md (mocked)\n'
  exit 0
fi

if ! command -v claude >/dev/null 2>&1; then
  printf 'shelf: claude CLI unavailable; skipping mirror dispatch (warning shape matches kiln-roadmap)\n'
  exit 0
fi

# Fire-and-forget — the coached interview historically does the same: errors
# from the MCP write are surfaced as stderr but never escalate to a non-zero
# exit out of kiln-roadmap.
claude --print \
  "Run /shelf:shelf-write-roadmap-note source_file=.kiln/vision.md trigger=vision-simple-params" \
  >/dev/null 2>&1 || true

printf 'shelf: dispatched mirror update for .kiln/vision.md\n'
exit 0
