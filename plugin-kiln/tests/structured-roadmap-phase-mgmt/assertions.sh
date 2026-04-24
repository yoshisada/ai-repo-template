#!/usr/bin/env bash
# US7 — FR-020 single-in-progress + FR-021 cascade.
set -euo pipefail

if [ ! -f phase-conflict.json ]; then
  echo "FAIL: phase-conflict.json missing" >&2
  exit 1
fi
if ! grep -q '"ok":false' phase-conflict.json; then
  echo "FAIL: phase-conflict.json should show ok:false (FR-020)" >&2
  cat phase-conflict.json >&2
  exit 1
fi
if ! grep -qi 'in-progress' phase-conflict.json; then
  echo "FAIL: phase-conflict.json should name the conflicting phase (FR-020)" >&2
  cat phase-conflict.json >&2
  exit 1
fi

if [ ! -f phase-cascade.json ]; then
  echo "FAIL: phase-cascade.json missing" >&2
  exit 1
fi
if ! grep -q '"ok":true' phase-cascade.json; then
  echo "FAIL: phase-cascade.json should show ok:true (FR-021)" >&2
  cat phase-cascade.json >&2
  exit 1
fi
if ! grep -qE '"items_transitioned":[1-9]' phase-cascade.json; then
  echo "FAIL: --cascade-items should report items_transitioned >= 1 (FR-021)" >&2
  cat phase-cascade.json >&2
  exit 1
fi

# Verify item state actually changed
if ! grep -qE '^state:[[:space:]]*in-phase$' .kiln/roadmap/items/2026-04-24-existing.md; then
  echo "FAIL: cascade did not flip item state planned → in-phase" >&2
  grep -E '^state:' .kiln/roadmap/items/2026-04-24-existing.md >&2 || true
  exit 1
fi

echo "PASS: FR-020 single-in-progress refusal + FR-021 cascade both work" >&2
exit 0
