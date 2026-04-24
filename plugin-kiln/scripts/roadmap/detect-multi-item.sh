#!/usr/bin/env bash
# detect-multi-item.sh — detect multi-item free-text input
#
# FR-018a / PRD FR-018a: bullets / numbered lists / "and also" / newlines → N items
# Contract: specs/structured-roadmap/contracts/interfaces.md §2.10
#
# Usage:   detect-multi-item.sh <description>
# Output:  stdout = JSON {"is_multi": <bool>, "items": [<string>, ...]}
# Exit:    0 on success

set -u

DESC="${1:-}"
if [ -z "$DESC" ]; then
  printf '{"is_multi":false,"items":[""]}\n'
  exit 0
fi

json_string() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\t'/\\t}"
  printf '%s' "$s"
}

declare -a ITEMS=()

# Strategy 1: bullet list (- /* ) — one item per bullet
if [[ "$DESC" == *$'\n'* ]] && printf '%s' "$DESC" | grep -qE '^[[:space:]]*[-*][[:space:]]+'; then
  while IFS= read -r line; do
    if [[ "$line" =~ ^[[:space:]]*[-*][[:space:]]+(.*)$ ]]; then
      val="${BASH_REMATCH[1]}"
      [ -n "$val" ] && ITEMS+=("$val")
    fi
  done <<< "$DESC"
fi

# Strategy 2: numbered list (1. 2. …)
if [ "${#ITEMS[@]}" -eq 0 ] && [[ "$DESC" == *$'\n'* ]] && printf '%s' "$DESC" | grep -qE '^[[:space:]]*[0-9]+\.[[:space:]]+'; then
  while IFS= read -r line; do
    if [[ "$line" =~ ^[[:space:]]*[0-9]+\.[[:space:]]+(.*)$ ]]; then
      val="${BASH_REMATCH[1]}"
      [ -n "$val" ] && ITEMS+=("$val")
    fi
  done <<< "$DESC"
fi

# Strategy 3: "and also" / "plus" / "as well as" splits within a single-line input
if [ "${#ITEMS[@]}" -eq 0 ]; then
  # Case-insensitive replace via GNU sed? Use awk for portability (BSD sed lacks -E with \b consistently).
  split_text="$(printf '%s' "$DESC" | awk '
    {
      out = $0
      # Normalize the three conjunctions to a unique sentinel, preserving case-insensitive match.
      gsub(/[[:space:]]+[Aa][Nn][Dd][[:space:]]+[Aa][Ll][Ss][Oo][[:space:]]+/, "\x01", out)
      gsub(/[[:space:]]+[Pp][Ll][Uu][Ss][[:space:]]+/, "\x01", out)
      gsub(/[[:space:]]+[Aa][Ss][[:space:]]+[Ww][Ee][Ll][Ll][[:space:]]+[Aa][Ss][[:space:]]+/, "\x01", out)
      print out
    }')"
  if [[ "$split_text" == *$'\x01'* ]]; then
    IFS=$'\x01' read -ra parts <<< "$split_text"
    for p in "${parts[@]}"; do
      t="$(printf '%s' "$p" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
      [ -n "$t" ] && ITEMS+=("$t")
    done
  fi
fi

# Strategy 4: newline-separated thing-to-build lines (≥2 non-blank lines)
if [ "${#ITEMS[@]}" -eq 0 ] && [[ "$DESC" == *$'\n'* ]]; then
  declare -a tmp=()
  while IFS= read -r line; do
    t="$(printf '%s' "$line" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
    [ -n "$t" ] && tmp+=("$t")
  done <<< "$DESC"
  if [ "${#tmp[@]}" -ge 2 ]; then
    ITEMS=("${tmp[@]}")
  fi
fi

# Fallback: single item
if [ "${#ITEMS[@]}" -le 1 ]; then
  printf '{"is_multi":false,"items":["%s"]}\n' "$(json_string "$DESC")"
  exit 0
fi

# Emit multi
out="["
first=1
for it in "${ITEMS[@]}"; do
  if [ "$first" -eq 1 ]; then first=0; else out+=","; fi
  out+="\"$(json_string "$it")\""
done
out+="]"
printf '{"is_multi":true,"items":%s}\n' "$out"
