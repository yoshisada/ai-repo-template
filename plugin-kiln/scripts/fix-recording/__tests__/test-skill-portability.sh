#!/usr/bin/env bash
# test-skill-portability.sh
# Tests FR-025 (plugin portability — no hardcoded repo-relative plugin paths
# in the skill or team briefs outside HTML comment blocks and non-shell fenced
# code). Acceptance scenario: US10 #1 — every script path resolves via a
# plugin-dir-aware mechanism.

set -u
LC_ALL=C
export LC_ALL

here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd -- "$here/../../../.." && pwd)
skill_dir="$repo_root/plugin-kiln/skills/fix"

targets=(
  "$skill_dir/SKILL.md"
  "$skill_dir/team-briefs/fix-record.md"
  "$skill_dir/team-briefs/fix-reflect.md"
)

# For each target, strip out:
#   1. HTML comment blocks `<!-- ... -->` (possibly multi-line).
#   2. Triple-backtick fenced code blocks labeled with a non-shell language
#      (i.e., the fence line is ``` followed by an identifier that is NOT
#      `bash`, `sh`, `shell`, or empty).
# Then grep for the forbidden literals.

forbidden_patterns=("plugin-shelf/scripts/" "plugin-kiln/skills/")
fail=0

for f in "${targets[@]}"; do
  if [ ! -f "$f" ]; then
    printf 'FAIL: target missing: %s\n' "$f" >&2
    fail=1
    continue
  fi

  # awk filter — produce only lines that are (a) outside HTML comments AND
  # (b) outside fenced code blocks labeled with a non-shell language.
  filtered=$(awk '
    BEGIN { in_comment = 0; in_nonshell_fence = 0 }
    {
      line = $0

      # Entering an HTML comment.
      if (in_comment == 0 && match(line, /<!--/)) {
        # Strip the portion before the `<!--` so it is still scanned.
        pre = substr(line, 1, RSTART - 1)
        # Does the comment also close on this line?
        rest = substr(line, RSTART)
        if (match(rest, /-->/)) {
          post = substr(rest, RSTART + RLENGTH)
          print pre post
          next
        } else {
          print pre
          in_comment = 1
          next
        }
      }
      if (in_comment == 1) {
        if (match(line, /-->/)) {
          post = substr(line, RSTART + RLENGTH)
          print post
          in_comment = 0
          next
        } else {
          next
        }
      }

      # Entering/leaving a fenced code block.
      if (line ~ /^```/) {
        # Fence start or end.
        if (in_nonshell_fence == 1) {
          in_nonshell_fence = 0
          next
        }
        # New fence — inspect the language tag.
        tag = line
        sub(/^```/, "", tag)
        # Strip trailing whitespace.
        sub(/[[:space:]].*$/, "", tag)
        # Non-shell fence: any tag that is not empty and not bash/sh/shell.
        if (tag != "" && tag != "bash" && tag != "sh" && tag != "shell") {
          in_nonshell_fence = 1
          next
        }
        # Shell fence or unlabeled fence: scan its contents.
        next
      }
      if (in_nonshell_fence == 1) {
        next
      }

      # Line is eligible for scanning.
      print line
    }
  ' "$f")

  for pat in "${forbidden_patterns[@]}"; do
    if printf '%s\n' "$filtered" | grep -Fq "$pat"; then
      printf 'FAIL: %s contains forbidden literal %q outside comments/non-shell fences\n' "$f" "$pat" >&2
      printf '  offending line(s):\n' >&2
      printf '%s\n' "$filtered" | grep -Fn "$pat" | sed 's/^/    /' >&2
      fail=1
    fi
  done
done

if [ "$fail" -ne 0 ]; then
  exit 1
fi
exit 0
