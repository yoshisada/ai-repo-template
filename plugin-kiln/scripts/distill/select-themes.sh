#!/usr/bin/env bash
# select-themes.sh — multi-select picker normalizer for kiln-distill.
#
# FR-017 of spec `coach-driven-capture-ergonomics`: after the theme-grouping
# step, the distill skill MUST offer a multi-select picker. This script is
# the picker's machine-readable layer — it reads the grouped-themes JSON and
# the user's selection spec, then emits the canonical SELECTION JSON that
# downstream disambiguation + emission loops consume.
#
# Per contracts/interfaces.md §Module: plugin-kiln/scripts/distill/ →
# select-themes.sh, the script takes the grouped-themes JSON path (positional)
# and emits `{"selected_slugs": [...]}` on stdout. Signature is frozen.
#
# Input-resolution precedence (this is the picker "UX" — the SKILL.md body
# decides which channel to use before shelling out):
#
#   1. $DISTILL_SELECTION_INDICES env var — comma- or space-separated 1-based
#      indices (e.g. "1,2" or "1 3"). Indices refer to positions in the
#      grouped-themes JSON array.
#   2. $DISTILL_SELECTION_SLUGS env var — comma- or space-separated slugs.
#      Exact match against the `slug` field of each theme.
#   3. stdin — only when `DISTILL_SELECTION_FROM_STDIN=1` is explicitly set;
#      then reads one line from stdin and parses it as indices (or slugs on
#      non-numeric tokens). The opt-in guard prevents hangs in the common
#      case where stdin is a closed pipe but `-t 0` returns false.
#   4. Fallback: select ALL themes (conservative default — preserves the
#      legacy single-theme byte-identical behavior in the N=1 case per
#      FR-021 / NFR-005).
#
# Exit codes:
#   0 — user selected N>=1 themes; SELECTION JSON on stdout.
#   1 — user cancelled (explicit empty selection, e.g. DISTILL_SELECTION_INDICES=""
#       with DISTILL_SELECTION_CANCEL=1 sentinel). Stdout is empty.
#   2 — usage error.
#
# Determinism: selection preserves INPUT ORDER (spec FR-017 + contract
# "Selection MUST preserve input order"). Do NOT alphabetize — downstream
# slug disambiguation handles collisions deterministically.

set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: select-themes.sh <grouped-themes-json>

  <grouped-themes-json> — path to a JSON file produced by the distill
  theme-grouping step. Schema:
    [
      { "slug": "<theme-slug>",
        "entries": [ ... ],
        "severity_hint": "foundational|highest|med|low|null"   (optional)
      }, ...
    ]

Env:
  DISTILL_SELECTION_INDICES — 1-based indices, comma/space separated.
  DISTILL_SELECTION_SLUGS   — explicit slugs, comma/space separated.
  DISTILL_SELECTION_CANCEL  — set to "1" to simulate user cancel.

Exit codes:
  0 success, 1 cancelled, 2 usage error.
EOF
  exit 2
}

if [[ $# -ne 1 ]]; then
  usage
fi

INPUT="$1"

if [[ ! -f "$INPUT" ]]; then
  echo "error: grouped-themes JSON not found: $INPUT" >&2
  exit 2
fi

# Validate input shape — must be a non-empty JSON array with .slug on each row.
if ! jq -e 'type == "array" and length > 0 and all(.[]; has("slug"))' "$INPUT" >/dev/null; then
  echo "error: input must be a non-empty JSON array of {slug, ...}" >&2
  exit 2
fi

# Explicit cancel sentinel — empty stdout, exit 1.
if [[ "${DISTILL_SELECTION_CANCEL:-}" == "1" ]]; then
  exit 1
fi

# Build the available-slugs array (preserves input order).
mapfile -t AVAILABLE < <(jq -r '.[].slug' "$INPUT")
TOTAL=${#AVAILABLE[@]}

# Normalize a comma/space-separated list into a bash array.
normalize_list() {
  # Split on comma/space, drop empties.
  local raw="$1"
  echo "$raw" | tr ',' ' ' | tr -s ' ' '\n' | sed '/^$/d'
}

SELECTED_SLUGS=()

# Channel 1 — indices.
if [[ -n "${DISTILL_SELECTION_INDICES:-}" ]]; then
  while IFS= read -r idx; do
    if ! [[ "$idx" =~ ^[0-9]+$ ]]; then
      echo "error: non-numeric index in DISTILL_SELECTION_INDICES: '$idx'" >&2
      exit 2
    fi
    if (( idx < 1 || idx > TOTAL )); then
      echo "error: index $idx out of range [1..$TOTAL]" >&2
      exit 2
    fi
    SELECTED_SLUGS+=("${AVAILABLE[$((idx - 1))]}")
  done < <(normalize_list "$DISTILL_SELECTION_INDICES")

# Channel 2 — slugs.
elif [[ -n "${DISTILL_SELECTION_SLUGS:-}" ]]; then
  while IFS= read -r want; do
    # Find position of `want` in AVAILABLE; keep input order from the env var.
    local_found=0
    for slug in "${AVAILABLE[@]}"; do
      if [[ "$slug" == "$want" ]]; then
        SELECTED_SLUGS+=("$slug")
        local_found=1
        break
      fi
    done
    if [[ "$local_found" -eq 0 ]]; then
      echo "error: slug not found in grouped-themes: '$want'" >&2
      exit 2
    fi
  done < <(normalize_list "$DISTILL_SELECTION_SLUGS")

# Channel 3 — stdin line.
#
# Only triggered when BOTH:
#   (a) stdin is not a terminal (i.e., something is piping in);
#   (b) `DISTILL_SELECTION_FROM_STDIN=1` is explicitly set.
#
# The explicit opt-in guards against hangs in CI-style environments where
# stdin is /dev/null-shaped but -t 0 returns false. Callers that want
# stdin-piping MUST set the env var — matches the principle of least
# surprise for skill bodies that shell out via the Bash tool.
elif [[ ! -t 0 && "${DISTILL_SELECTION_FROM_STDIN:-}" == "1" ]]; then
  # Try reading one line; if empty, fall through to channel 4.
  if IFS= read -r stdin_line && [[ -n "$stdin_line" ]]; then
    # Numeric-indices path.
    all_numeric=1
    while IFS= read -r tok; do
      if ! [[ "$tok" =~ ^[0-9]+$ ]]; then
        all_numeric=0
        break
      fi
    done < <(normalize_list "$stdin_line")

    if [[ "$all_numeric" -eq 1 ]]; then
      while IFS= read -r idx; do
        if (( idx < 1 || idx > TOTAL )); then
          echo "error: stdin index $idx out of range [1..$TOTAL]" >&2
          exit 2
        fi
        SELECTED_SLUGS+=("${AVAILABLE[$((idx - 1))]}")
      done < <(normalize_list "$stdin_line")
    else
      while IFS= read -r want; do
        found=0
        for slug in "${AVAILABLE[@]}"; do
          if [[ "$slug" == "$want" ]]; then
            SELECTED_SLUGS+=("$slug")
            found=1
            break
          fi
        done
        if [[ "$found" -eq 0 ]]; then
          echo "error: stdin slug not found: '$want'" >&2
          exit 2
        fi
      done < <(normalize_list "$stdin_line")
    fi
  fi
fi

# Channel 4 — fallback: select ALL.
# Also handles N=1 case: FR-021 / NFR-005 byte-identical single-theme —
# no env vars, no stdin → auto-select the lone theme.
if [[ "${#SELECTED_SLUGS[@]}" -eq 0 ]]; then
  for slug in "${AVAILABLE[@]}"; do
    SELECTED_SLUGS+=("$slug")
  done
fi

# Emit the selection JSON.
# `jq -n --argjson` with a constructed array preserves insertion order.
JSON_ARR=$(printf '%s\n' "${SELECTED_SLUGS[@]}" | jq -R . | jq -s .)
jq -n --argjson sel "$JSON_ARR" '{selected_slugs: $sel}'
