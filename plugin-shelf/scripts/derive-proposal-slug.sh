#!/usr/bin/env bash
# derive-proposal-slug.sh
# FR-010
#
# Deterministic slug derivation for a manifest-improvement proposal filename.
# Reads the `why` sentence from stdin, applies the FR-10 pipeline, emits a
# kebab-case slug on stdout.
#
# Properties:
#   - Lowercase.
#   - Stop-words removed (closed English set — see STOPWORDS below).
#   - Non-alphanumeric runs collapsed to `-`.
#   - Consecutive `-` collapsed.
#   - No leading/trailing `-`.
#   - ≤50 characters, truncated at a `-` boundary (never mid-word).
#   - LC_ALL=C so locale never alters the outcome — same input, same slug.
#
# Exit codes:
#   0 — slug emitted on stdout.
#   1 — stdin was empty after stripping / produced an empty slug.

set -u
LC_ALL=C
export LC_ALL

# Closed stop-word list. Matches FR-010 intent plus the set used by
# kiln:mistake's slug step (so slugs derived across the two
# workflows stay consistent).
STOPWORDS="the a an is was were are of in on at to for and or but that this these those it its"

raw=$(cat)
if [ -z "$raw" ]; then
  exit 1
fi

# 1. Lowercase.
lowered=$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]')

# 2. Remove stop-words as whole words. We wrap the text with spaces and then
#    strip ` <word> ` occurrences; repeat until no change.
padded=" $lowered "
# Normalize internal newlines/tabs to spaces first so stopword bounds work.
padded=$(printf '%s' "$padded" | tr '\n\t' '  ')
for sw in $STOPWORDS; do
  # Replace all " <sw> " with a single " ".
  while :; do
    next=${padded// $sw / }
    if [ "$next" = "$padded" ]; then
      break
    fi
    padded=$next
  done
done

# 3. Non-alphanumeric runs -> `-`.
hyphenated=$(printf '%s' "$padded" | tr -c '[:alnum:]' '-')

# 4. Collapse consecutive `-`.
collapsed=$(printf '%s' "$hyphenated" | tr -s '-')

# 5. Strip leading/trailing `-`.
trimmed=${collapsed#-}
trimmed=${trimmed%-}

if [ -z "$trimmed" ]; then
  exit 1
fi

# 6. Truncate to ≤50 chars at a `-` boundary. If slug <= 50, emit as-is.
if [ ${#trimmed} -le 50 ]; then
  printf '%s\n' "$trimmed"
  exit 0
fi

head50=${trimmed:0:50}
# Cut back to the last `-` in that 50-char window (never mid-word).
truncated=${head50%-*}
# If no `-` exists in the first 50 chars (one very long token), fall back to
# the full 50-char prefix.
if [ "$truncated" = "$head50" ]; then
  truncated=$head50
fi
# Strip trailing `-` if the cut left one.
truncated=${truncated%-}
if [ -z "$truncated" ]; then
  exit 1
fi
printf '%s\n' "$truncated"
exit 0
