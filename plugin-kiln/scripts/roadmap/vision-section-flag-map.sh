#!/usr/bin/env bash
# vision-tooling FR-021 — single source of truth for the
# `--add-* / --update-*` simple-params flag → vision.md section mapping.
#
# Sourceable as a library (exports two associative arrays); also runnable in
# CLI mode (`--list`) which prints the table on stdout in
# `<flag>\t<section>\t<operation>` form, sorted alphabetically by flag.
#
# Per contracts/interfaces.md §"Theme A — vision-section-flag-map.sh":
#   VISION_FLAG_TO_SECTION  flag (no leading --) -> literal section header line
#   VISION_FLAG_OP          flag (no leading --) -> {append-bullet, append-paragraph, replace-body}
#
# Exit codes: 0 always.

set -euo pipefail

# Bash 4+ associative arrays. macOS default ships /bin/bash 3.2 — callers MUST
# invoke this script under `bash` (the `#!/usr/bin/env bash` shebang resolves
# to whichever bash is on PATH; the team-default Homebrew `bash` >=4 is the
# tested substrate).
declare -gA VISION_FLAG_TO_SECTION
declare -gA VISION_FLAG_OP

# --- "What we are building" --------------------------------------------------
VISION_FLAG_TO_SECTION["update-what"]="## What we are building"
VISION_FLAG_OP["update-what"]="replace-body"

# --- "What it is not" --------------------------------------------------------
VISION_FLAG_TO_SECTION["add-non-goal"]="## What it is not"
VISION_FLAG_OP["add-non-goal"]="append-bullet"

VISION_FLAG_TO_SECTION["update-not"]="## What it is not"
VISION_FLAG_OP["update-not"]="replace-body"

# --- "How we'll know we're winning" ------------------------------------------
VISION_FLAG_TO_SECTION["add-signal"]="## How we'll know we're winning"
VISION_FLAG_OP["add-signal"]="append-bullet"

VISION_FLAG_TO_SECTION["update-signals"]="## How we'll know we're winning"
VISION_FLAG_OP["update-signals"]="replace-body"

# --- "Guiding constraints" ---------------------------------------------------
VISION_FLAG_TO_SECTION["add-constraint"]="## Guiding constraints"
VISION_FLAG_OP["add-constraint"]="append-bullet"

VISION_FLAG_TO_SECTION["update-constraints"]="## Guiding constraints"
VISION_FLAG_OP["update-constraints"]="replace-body"

# CLI mode — print the table on stdout when `--list` is passed (or no args at
# all; library-mode callers that source this file pass no args BUT also do not
# execute the script, so this branch never runs for them).
_vision_section_flag_map_list() {
  local f
  # Sorted ASC for determinism (NFR-001).
  for f in $(printf '%s\n' "${!VISION_FLAG_TO_SECTION[@]}" | LC_ALL=C sort); do
    printf '%s\t%s\t%s\n' "$f" "${VISION_FLAG_TO_SECTION[$f]}" "${VISION_FLAG_OP[$f]}"
  done
}

# Detect whether we're being sourced. ${BASH_SOURCE[0]} == ${0} only when
# executed directly (not sourced). The `|| true` keeps `set -e` happy when the
# script is sourced (BASH_SOURCE may be unset in that case).
if [ "${BASH_SOURCE[0]:-$0}" = "${0}" ]; then
  case "${1:-}" in
    --list|"")
      _vision_section_flag_map_list
      ;;
    *)
      printf 'vision-section-flag-map: unknown arg: %s\n' "$1" >&2
      exit 1
      ;;
  esac
fi
