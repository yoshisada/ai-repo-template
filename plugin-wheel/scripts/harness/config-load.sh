#!/usr/bin/env bash
# config-load.sh — Read .kiln/test.config (optional) and emit key=value for eval.
#
# Satisfies: FR-014 (config override contract)
# Contract:  contracts/interfaces.md §7.7
#
# Usage:
#   config-load.sh <repo-root>
#   eval "$(config-load.sh /path/to/repo)"
#
# Args:
#   <repo-root>   absolute path to the repo root (CWD of the harness invocation)
#
# Stdout: key=value lines, one per line, shell-eval-safe (values double-quoted).
#         All known keys are emitted (defaults filled if absent).
#         Unknown keys from the user's file are passed through verbatim.
# Stderr: diagnostics (warnings on parse issues)
# Exit:   0 always (missing file → defaults; malformed line → warning + skip)
#
# Known keys + defaults (contracts §7.7):
#   discovery_path=plugin-<name>/tests    (left as-is; caller resolves <name>)
#   watcher_stall_window_seconds=300
#   watcher_poll_interval_seconds=30
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "config-load.sh: expected 1 arg (repo-root), got $#" >&2
  exit 2
fi

repo_root=$1
config_path="$repo_root/.kiln/test.config"

# Defaults (contracts §7.7).
declare -A defaults=(
  [discovery_path]='plugin-<name>/tests'
  [watcher_stall_window_seconds]='300'
  [watcher_poll_interval_seconds]='30'
)

# Start with all defaults, then let the file override.
declare -A effective
for k in "${!defaults[@]}"; do
  effective[$k]=${defaults[$k]}
done

# Preserve unknown keys in a separate list so we can pass them through last.
declare -a extras=()

if [[ -f $config_path ]]; then
  # Parse key=value lines; skip blanks and comment lines (`#` first char).
  while IFS= read -r raw || [[ -n $raw ]]; do
    # Strip trailing \r (Windows line endings safety).
    raw=${raw%$'\r'}
    # Trim leading whitespace.
    line=${raw#"${raw%%[![:space:]]*}"}
    # Blank or comment?
    if [[ -z $line || ${line:0:1} == '#' ]]; then
      continue
    fi
    # Expect key=value.
    if [[ $line != *=* ]]; then
      echo "config-load.sh: warning — unparseable line in $config_path (no '='): $line" >&2
      continue
    fi
    key=${line%%=*}
    val=${line#*=}
    # Trim trailing whitespace on key.
    key=${key%%[[:space:]]*}
    # Strip surrounding quotes on value.
    if [[ ${#val} -ge 2 && ${val:0:1} == '"' && ${val: -1} == '"' ]]; then
      val=${val:1:${#val}-2}
    elif [[ ${#val} -ge 2 && ${val:0:1} == "'" && ${val: -1} == "'" ]]; then
      val=${val:1:${#val}-2}
    fi
    if [[ -n ${defaults[$key]:-} ]]; then
      effective[$key]=$val
    else
      extras+=("$key=$val")
    fi
  done < "$config_path"
fi

# Emit known keys in a stable order (for determinism / diffability per NFR-003).
for k in discovery_path watcher_stall_window_seconds watcher_poll_interval_seconds; do
  # Double-quote and escape internal double quotes.
  v=${effective[$k]}
  v=${v//\"/\\\"}
  printf '%s="%s"\n' "$k" "$v"
done

# Then emit any extras (unknown forward-compat keys) in original file order.
for kv in "${extras[@]}"; do
  k=${kv%%=*}
  v=${kv#*=}
  v=${v//\"/\\\"}
  printf '%s="%s"\n' "$k" "$v"
done

exit 0
