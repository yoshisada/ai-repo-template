#!/usr/bin/env bash
# config-check.sh — run the version-keyed config health checks from doctor-manifest.json.
#
# WHY: kiln-doctor's existing checks key off templates/kiln-manifest.json (directories,
# migrations, retention). The Phase 0 config foundation (.kiln/config.json, standards.md,
# test-strategy.json) is health-checked from a SEPARATE version-keyed manifest,
# scaffold/doctor-manifest.json, so new system components ship as new version entries
# without touching kiln-doctor's code. This script merges every manifest entry from 1.0.0
# through the project's config_version, runs each check, and emits diagnosis-table rows.
#
# Usage: config-check.sh [manifest_path]
#   manifest_path  optional; defaults to a resolved scaffold/doctor-manifest.json
# Output: markdown table rows `| <check> | <STATUS> | <fix> |` on stdout.
# Exit: non-zero if any REQUIRED or version check fails (doctor surfaces this); 0 otherwise.
# Optional checks never affect exit code (warnings only).

set -u

# ---- Resolve the doctor manifest (mirror kiln-doctor's plugin-path resolution) ----
MANIFEST="${1:-}"
if [ -z "$MANIFEST" ]; then
  for c in \
    "${CLAUDE_PLUGIN_ROOT:-}/scaffold/doctor-manifest.json" \
    "${WORKFLOW_PLUGIN_DIR:-}/scaffold/doctor-manifest.json" \
    "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../scaffold" 2>/dev/null && pwd)/doctor-manifest.json" \
    "plugin-kiln/scaffold/doctor-manifest.json"; do
    [ -n "$c" ] && [ -f "$c" ] && { MANIFEST="$c"; break; }
  done
  if [ -z "$MANIFEST" ]; then
    # Bounded walk — kiln installs at shallow depth; avoid scanning a huge consumer tree.
    MANIFEST="$(find . -maxdepth 8 -path '*/kiln/scaffold/doctor-manifest.json' 2>/dev/null | head -1)"
  fi
fi

if [ -z "$MANIFEST" ] || [ ! -f "$MANIFEST" ]; then
  echo "| Config foundation | N/A | doctor-manifest.json not found — skipped |"
  exit 0
fi

CONFIG=".kiln/config.json"
CONFIG_VERSION="$(jq -r '.config_version // "1.0.0"' "$CONFIG" 2>/dev/null || echo "1.0.0")"

# semver-ish compare: returns 0 if $1 <= $2 (treats x.y.z numerically).
_le() {
  [ "$1" = "$2" ] && return 0
  local lo; lo="$(printf '%s\n%s\n' "$1" "$2" | sort -t. -k1,1n -k2,2n -k3,3n | head -1)"
  [ "$lo" = "$1" ]
}

# Manifest version keys (numeric-looking top-level keys) up to CONFIG_VERSION, ascending.
VERSIONS="$(jq -r 'keys[]' "$MANIFEST" 2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | sort -t. -k1,1n -k2,2n -k3,3n)"

FAIL=0

_emit() { printf '| %s | %s | %s |\n' "$1" "$2" "$3"; }

# value of a config key (for if_config_key gating)
_config_has_key() { jq -e --arg k "$1" 'has($k)' "$CONFIG" >/dev/null 2>&1; }

for v in $VERSIONS; do
  _le "$v" "$CONFIG_VERSION" || continue

  # ---- required ----
  while IFS= read -r entry; do
    [ -z "$entry" ] && continue
    path="$(jq -r '.path // empty' <<<"$entry")"
    check="$(jq -r '.check // empty' <<<"$entry")"
    fix="$(jq -r '.fix // ""' <<<"$entry")"
    gate="$(jq -r '.if_config_key // empty' <<<"$entry")"
    if [ -n "$gate" ] && ! _config_has_key "$gate"; then
      continue   # gated check whose config key is absent — skip silently
    fi
    case "$check" in
      valid-json)
        if [ -f "$path" ] && jq empty "$path" >/dev/null 2>&1; then
          _emit "$path" "OK" "valid json"
        else
          _emit "$path" "FAIL" "$fix"; FAIL=1
        fi ;;
      exists|dir-exists)
        if { [ "$check" = "dir-exists" ] && [ -d "$path" ]; } || { [ "$check" = "exists" ] && [ -e "$path" ]; }; then
          _emit "$path" "OK" "present"
        else
          _emit "$path" "FAIL" "$fix"; FAIL=1
        fi ;;
      *) _emit "$path" "N/A" "unknown check '$check'" ;;
    esac
  done < <(jq -c --arg v "$v" '.[$v].required // [] | .[]' "$MANIFEST" 2>/dev/null)

  # ---- version_checks ----
  while IFS= read -r entry; do
    [ -z "$entry" ] && continue
    path="$(jq -r '.path // empty' <<<"$entry")"
    field="$(jq -r '.field // empty' <<<"$entry")"
    fix="$(jq -r '.fix // ""' <<<"$entry")"
    if [ -f "$path" ] && jq -e --arg f "$field" 'has($f)' "$path" >/dev/null 2>&1; then
      _emit "$path:$field" "OK" "set ($(jq -r --arg f "$field" '.[$f]' "$path" 2>/dev/null))"
    else
      _emit "$path:$field" "FAIL" "$fix"; FAIL=1
    fi
  done < <(jq -c --arg v "$v" '.[$v].version_checks // [] | .[]' "$MANIFEST" 2>/dev/null)

  # ---- optional (warnings only — never affect exit code) ----
  while IFS= read -r entry; do
    [ -z "$entry" ] && continue
    check="$(jq -r '.check // empty' <<<"$entry")"
    fix="$(jq -r '.fix // ""' <<<"$entry")"
    case "$check" in
      stale-worktrees)
        # grep -c prints a count AND exits 1 when zero — so capture without `|| echo`
        # (which would double-emit). Normalize to a single integer.
        n="$(git worktree list 2>/dev/null | grep -c 'prunable')"
        n="$(printf '%s' "$n" | tr -dc '0-9')"; n="${n:-0}"
        if [ "$n" -gt 0 ]; then _emit "stale-worktrees" "WARN" "$fix"; else _emit "stale-worktrees" "OK" "none"; fi ;;
      obsidian-reachable)
        _emit "obsidian-reachable" "N/A" "$fix (not probed offline)" ;;
      *) _emit "$check" "N/A" "$fix" ;;
    esac
  done < <(jq -c --arg v "$v" '.[$v].optional // [] | .[]' "$MANIFEST" 2>/dev/null)
done

exit "$FAIL"
