#!/usr/bin/env bash
# vision-tooling FR-005 — argv validator for /kiln:kiln-roadmap --vision.
#
# Asserts at MOST one supported simple-params flag is present (and exactly
# one, when any are present). Refuses unknown `--add-*` / `--update-*` flags
# and refuses empty values. Must complete with NO file I/O so a refusal can
# never partially mutate vision.md.
#
# Per contracts/interfaces.md §"Theme A — vision-flag-validator.sh":
#   stdout: on success, single line "<flag>\t<value>" (canonical flag
#           includes leading --; empty stdout means "no simple-params flag,
#           caller dispatches the coached interview").
#   stderr: on validation failure, one line `vision: <reason>`.
#   exit 0: success (one flag with non-empty value) OR no simple-params flag.
#   exit 2: two-or-more flags / empty value / unknown --add-*/--update-* flag.
#
# Invocation: `vision-flag-validator.sh -- "$@"` where "$@" is the argv
# remainder AFTER the leading `--vision` flag (kiln-roadmap consumes that).

set -euo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=plugin-kiln/scripts/roadmap/vision-section-flag-map.sh
source "$SELF_DIR/vision-section-flag-map.sh"

err() { printf 'vision: %s\n' "$*" >&2; }

# Strip the leading `--` separator argv-marker if the caller passed it.
if [ "${1:-}" = "--" ]; then
  shift
fi

found_flag=""
found_value=""

while [ $# -gt 0 ]; do
  arg="$1"
  case "$arg" in
    --add-*|--update-*)
      # Strip leading `--`
      key="${arg#--}"
      # `--flag=value` form
      if [[ "$key" == *"="* ]]; then
        value="${key#*=}"
        key="${key%%=*}"
      else
        # `--flag value` form — consume next argv as value
        if [ $# -lt 2 ]; then
          err "${arg} requires a value"
          exit 2
        fi
        shift
        value="$1"
      fi
      # Look up canonical flag in the mapping table.
      if [ -z "${VISION_FLAG_TO_SECTION[$key]+x}" ]; then
        err "unknown flag: --${key}"
        exit 2
      fi
      if [ -z "${value}" ]; then
        err "--${key} requires a non-empty value"
        exit 2
      fi
      if [ -n "${found_flag}" ]; then
        err "--${found_flag} and --${key} are mutually exclusive"
        exit 2
      fi
      found_flag="$key"
      found_value="$value"
      ;;
    --vision)
      # Tolerated — kiln-roadmap may forward it through.
      ;;
    *)
      # Unknown / unrelated arg — pass-through (the caller may have other
      # legitimate flags). Validator's job is to validate the simple-params
      # surface, not police every arg.
      ;;
  esac
  shift
done

if [ -n "$found_flag" ]; then
  printf -- '--%s\t%s\n' "$found_flag" "$found_value"
fi
exit 0
