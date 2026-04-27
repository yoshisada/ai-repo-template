#!/usr/bin/env bash
# extract-signal-f.sh — Signal (f): shelf + trim mirrors stay in sync.
#
# Vision signal (f): Obsidian (shelf) and design (trim) mirrors stay in sync
# without hand-reconciliation.
#
# Heuristic (V1): inspect `.shelf-config` (presence + freshness) and `.trim/`
# (presence + last-sync hint). A deterministic shell extractor cannot reach
# Obsidian to count drift items; we emit a presence-based status and tag the
# row `unmeasurable` when the inspectable surfaces are missing.
#
# FR-018: each extractor is invocable in isolation. Read-only.
# Contract: specs/vision-tooling/contracts/interfaces.md §"Theme D — extract-signal-<a..h>.sh".

set -euo pipefail

SIGNAL_ID="(f)"
TARGET=".shelf-config + .trim/ both present + recently touched"

REPO_ROOT="${KILN_REPO_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || true)}"

if [[ -z "$REPO_ROOT" ]]; then
  printf '%s\t-\t-\tunmeasurable\tno repo root\n' "$SIGNAL_ID"
  exit 4
fi

SHELF_CONFIG="$REPO_ROOT/.shelf-config"
TRIM_DIR="$REPO_ROOT/.trim"

SHELF_PRESENT="no"
TRIM_PRESENT="no"
[[ -f "$SHELF_CONFIG" ]] && SHELF_PRESENT="yes"
[[ -d "$TRIM_DIR" ]] && TRIM_PRESENT="yes"

if [[ "$SHELF_PRESENT" == "no" && "$TRIM_PRESENT" == "no" ]]; then
  printf '%s\t-\t-\tunmeasurable\tneither .shelf-config nor .trim/ present\n' "$SIGNAL_ID"
  exit 4
fi

# Drift detection requires reading Obsidian via MCP — outside a shell extractor.
# Emit presence-only and let an operator dig in via the cited paths.
EVIDENCE=".shelf-config=$SHELF_PRESENT .trim/=$TRIM_PRESENT (drift count requires shelf MCP)"
printf '%s\tshelf=%s trim=%s\t%s\tunmeasurable\t%s\n' \
  "$SIGNAL_ID" "$SHELF_PRESENT" "$TRIM_PRESENT" "$TARGET" "$EVIDENCE"
exit 4
